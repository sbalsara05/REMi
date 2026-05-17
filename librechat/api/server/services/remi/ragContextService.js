const fs = require('fs');
const os = require('os');
const path = require('path');
const axios = require('axios');
const FormData = require('form-data');
const { logger } = require('@librechat/data-schemas');
const { logAxiosError, generateShortLivedToken } = require('@librechat/api');
const handoffStore = require('./handoffStore');

const DEFAULT_RETRIEVE_LIMIT = 30;
const QUERY_K = 4;
let ragHealthy = null;
let ragHealthCheckedAt = 0;
const RAG_HEALTH_TTL_MS = 60_000;

function entityIdForUser(userId) {
  return `remi-user:${userId}`;
}

function isRagConfigured() {
  return Boolean(process.env.RAG_API_URL);
}

async function checkRagHealth() {
  if (!isRagConfigured()) {
    return false;
  }
  const now = Date.now();
  if (ragHealthy != null && now - ragHealthCheckedAt < RAG_HEALTH_TTL_MS) {
    return ragHealthy;
  }
  try {
    const response = await axios.get(`${process.env.RAG_API_URL}/health`, { timeout: 5000 });
    ragHealthy = response?.status === 200 || response?.statusText === 'OK';
  } catch (error) {
    logAxiosError({ error, message: '[remi-rag] health check failed' });
    ragHealthy = false;
  }
  ragHealthCheckedAt = now;
  return ragHealthy;
}

function buildFileId(interactionId, seq) {
  return `remi-${interactionId}-${seq}`;
}

function formatCaptureDocument({ appName, text, interactionId }) {
  const lines = [
    '# REMi context capture',
    `interaction: ${interactionId}`,
    `captured_at: ${new Date().toISOString()}`,
  ];
  if (appName) {
    lines.push(`app: ${appName}`);
  }
  lines.push('', text.trim());
  return lines.join('\n');
}

function formatTurnDocument({ query, response, interactionId }) {
  return [
    '# REMi conversation turn',
    `interaction: ${interactionId}`,
    `recorded_at: ${new Date().toISOString()}`,
    '',
    `User: ${query.trim()}`,
    '',
    `Assistant: ${response.trim()}`,
  ].join('\n');
}

async function embedTextDocument({ req, fileId, text, kind }) {
  if (!isRagConfigured()) {
    return { indexed: false, fileId: null, reason: 'RAG_API_URL not configured' };
  }
  if (!(await checkRagHealth())) {
    return { indexed: false, fileId: null, reason: 'RAG API unavailable' };
  }

  const userId = req.user?.id;
  if (!userId) {
    return { indexed: false, fileId: null, reason: 'No user' };
  }

  const trimmed = typeof text === 'string' ? text.trim() : '';
  if (!trimmed) {
    return { indexed: false, fileId: null, reason: 'Empty text' };
  }

  const tmpDir = path.join(os.tmpdir(), 'remi-rag');
  fs.mkdirSync(tmpDir, { recursive: true });
  const tmpPath = path.join(tmpDir, `${fileId}.md`);

  try {
    fs.writeFileSync(tmpPath, trimmed, 'utf8');
    const jwtToken = generateShortLivedToken(userId);
    const formData = new FormData();
    formData.append('file_id', fileId);
    formData.append('file', fs.createReadStream(tmpPath));
    formData.append('entity_id', entityIdForUser(userId));

    const response = await axios.post(`${process.env.RAG_API_URL}/embed`, formData, {
      headers: {
        Authorization: `Bearer ${jwtToken}`,
        accept: 'application/json',
        ...formData.getHeaders(),
      },
      timeout: 120_000,
    });

    if (!response.data?.status) {
      return { indexed: false, fileId: null, reason: 'Embed failed' };
    }

    handoffStore.insertRagChunk({
      fileId,
      userId,
      interactionId: kind.interactionId,
      kind: kind.type,
    });

    return { indexed: true, fileId };
  } catch (error) {
    logAxiosError({ error, message: '[remi-rag] embed failed' });
    return { indexed: false, fileId: null, reason: error.message || 'Embed error' };
  } finally {
    try {
      fs.unlinkSync(tmpPath);
    } catch {
      // ignore
    }
  }
}

async function indexCapture({ req, interactionId, text, appName }) {
  handoffStore.validateInteractionId(interactionId);
  const seq = handoffStore.nextRagSeq(interactionId);
  const fileId = buildFileId(interactionId, seq);
  const document = formatCaptureDocument({ appName, text, interactionId });
  return embedTextDocument({
    req,
    fileId,
    text: document,
    kind: { type: 'capture', interactionId },
  });
}

async function indexTurn({ req, interactionId, query, response }) {
  if (!query?.trim() || !response?.trim()) {
    return { indexed: false, fileId: null, reason: 'Empty turn' };
  }
  handoffStore.validateInteractionId(interactionId);
  const seq = handoffStore.nextRagSeq(interactionId);
  const fileId = buildFileId(interactionId, seq);
  const document = formatTurnDocument({ query, response, interactionId });
  return embedTextDocument({
    req,
    fileId,
    text: document,
    kind: { type: 'turn', interactionId },
  });
}

function extractChunkText(resultData) {
  if (!resultData) {
    return '';
  }
  if (typeof resultData === 'string') {
    return resultData;
  }
  if (Array.isArray(resultData)) {
    const [docInfo, _distance] = resultData;
    if (typeof docInfo === 'string') {
      return docInfo;
    }
    if (docInfo && typeof docInfo === 'object') {
      return docInfo.page_content || docInfo.content || docInfo.text || JSON.stringify(docInfo);
    }
  }
  if (typeof resultData === 'object') {
    return resultData.page_content || resultData.content || resultData.text || '';
  }
  return '';
}

async function queryFile({ req, userId, fileId, query }) {
  const jwtToken = generateShortLivedToken(userId);
  const body = {
    file_id: fileId,
    query,
    k: QUERY_K,
    entity_id: entityIdForUser(userId),
  };
  const response = await axios.post(`${process.env.RAG_API_URL}/query`, body, {
    headers: {
      Authorization: `Bearer ${jwtToken}`,
      'Content-Type': 'application/json',
    },
    timeout: 30_000,
  });
  const rows = Array.isArray(response.data) ? response.data : [];
  return rows
    .map((row) => ({
      text: extractChunkText(row),
      distance: Array.isArray(row) ? row[1] : undefined,
    }))
    .filter((row) => row.text && row.text.trim().length > 0);
}

async function retrieveForQuery({ req, query, limit = DEFAULT_RETRIEVE_LIMIT }) {
  if (!isRagConfigured() || !(await checkRagHealth())) {
    return '';
  }
  const userId = req.user?.id;
  if (!userId || !query?.trim()) {
    return '';
  }

  const fileIds = handoffStore.listRagFileIdsForUser(userId, limit);
  if (fileIds.length === 0) {
    return '';
  }

  const results = await Promise.all(
    fileIds.map((fileId) =>
      queryFile({ req, userId, fileId, query }).catch((error) => {
        logAxiosError({ error, message: `[remi-rag] query failed for ${fileId}` });
        return [];
      }),
    ),
  );

  const merged = results
    .flat()
    .sort((a, b) => (a.distance ?? 1) - (b.distance ?? 1))
    .slice(0, QUERY_K * 2);

  const seen = new Set();
  const snippets = [];
  for (const item of merged) {
    const key = item.text.slice(0, 120);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    snippets.push(item.text.trim());
    if (snippets.length >= QUERY_K * 2) {
      break;
    }
  }

  if (snippets.length === 0) {
    return '';
  }

  return snippets.map((s, i) => `[${i + 1}] ${s}`).join('\n\n');
}

module.exports = {
  indexCapture,
  indexTurn,
  retrieveForQuery,
  isRagConfigured,
};
