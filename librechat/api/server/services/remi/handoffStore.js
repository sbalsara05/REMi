const fs = require('fs');
const path = require('path');
const os = require('os');
const { v4: uuidv4 } = require('uuid');
const Database = require('better-sqlite3');
const { logger } = require('@librechat/data-schemas');

const SCHEMA = `
CREATE TABLE IF NOT EXISTS interactions (
  id TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL,
  prompt TEXT,
  response_so_far TEXT,
  screenshot_path TEXT,
  model TEXT,
  crop_hash TEXT,
  synced_to_chat INTEGER DEFAULT 0,
  conversation_id TEXT
);
CREATE INDEX IF NOT EXISTS idx_interactions_created_at ON interactions(created_at DESC);

CREATE TABLE IF NOT EXISTS remi_rag_chunks (
  file_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  interaction_id TEXT,
  kind TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rag_user_created ON remi_rag_chunks(user_id, created_at DESC);
`;

let dbInstance;

function expandHome(filePath) {
  if (filePath.startsWith('~/')) {
    return path.join(os.homedir(), filePath.slice(2));
  }
  return filePath;
}

function getDefaultDbPath() {
  return path.join(os.homedir(), 'Library', 'Application Support', 'REMi', 'interactions.sqlite');
}

function getDbPath() {
  return expandHome(process.env.REMI_HANDOFF_DB_PATH || getDefaultDbPath());
}

function getScreenshotsDir() {
  return path.join(path.dirname(getDbPath()), 'screenshots');
}

/** Host Application Support path when DB stores Docker volume paths (/remi-handoff/...). */
function getDefaultHandoffRoot() {
  return path.join(os.homedir(), 'Library', 'Application Support', 'REMi');
}

function remapDockerScreenshotPath(storedPath) {
  if (!storedPath || typeof storedPath !== 'string') {
    return null;
  }
  if (!storedPath.startsWith('/remi-handoff/')) {
    return storedPath;
  }
  return path.join(getDefaultHandoffRoot(), storedPath.slice('/remi-handoff/'.length));
}

/** Resolves a readable screenshot file for an interaction (DB path, Docker remap, or {id}.png). */
function resolveInteractionScreenshotPath(interaction) {
  if (!interaction?.id) {
    return null;
  }

  const candidates = [];
  if (interaction.screenshotPath) {
    candidates.push(interaction.screenshotPath);
    candidates.push(remapDockerScreenshotPath(interaction.screenshotPath));
  }

  try {
    candidates.push(resolveScreenshotPath(interaction.id));
  } catch {
    // invalid id shape — skip canonical fallback
  }

  for (const candidate of candidates) {
    if (candidate && fs.existsSync(candidate)) {
      return candidate;
    }
  }

  return null;
}

function ensureDirs() {
  const dbPath = getDbPath();
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  fs.mkdirSync(getScreenshotsDir(), { recursive: true });
}

function getDb() {
  if (dbInstance) {
    return dbInstance;
  }
  ensureDirs();
  dbInstance = new Database(getDbPath());
  dbInstance.pragma('journal_mode = WAL');
  dbInstance.exec(SCHEMA);
  logger.info(`[remi] Handoff SQLite: ${getDbPath()}`);
  return dbInstance;
}

function mapRow(row) {
  if (!row) {
    return null;
  }
  const interaction = {
    id: row.id,
    createdAt: row.created_at,
    prompt: row.prompt,
    responseSoFar: row.response_so_far,
    screenshotPath: row.screenshot_path,
    model: row.model,
    cropHash: row.crop_hash,
    syncedToChat: Boolean(row.synced_to_chat),
    conversationId: row.conversation_id,
  };
  const resolvedScreenshotPath = resolveInteractionScreenshotPath(interaction);
  return {
    ...interaction,
    screenshotPath: resolvedScreenshotPath,
    hasScreenshot: Boolean(resolvedScreenshotPath),
  };
}

function listInteractions({ cursor, limit = 25 }) {
  const db = getDb();
  const params = [];
  let sql = `SELECT id, created_at, prompt, response_so_far, screenshot_path, model, crop_hash,
    synced_to_chat, conversation_id FROM interactions`;
  if (cursor) {
    sql += ` WHERE created_at < ?`;
    params.push(Number(cursor));
  }
  sql += ` ORDER BY created_at DESC LIMIT ?`;
  params.push(limit + 1);

  const rows = db.prepare(sql).all(...params);
  const hasMore = rows.length > limit;
  const interactions = (hasMore ? rows.slice(0, limit) : rows).map(mapRow);
  const nextCursor = hasMore ? String(interactions[interactions.length - 1].createdAt) : null;
  return { interactions, nextCursor };
}

function getInteraction(id) {
  const db = getDb();
  const row = db.prepare(`SELECT * FROM interactions WHERE id = ?`).get(id);
  return mapRow(row);
}

const INTERACTION_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

function validateInteractionId(id) {
  if (!id || typeof id !== 'string' || !INTERACTION_ID_PATTERN.test(id)) {
    throw new Error('Invalid interactionId');
  }
}

function resolveScreenshotPath(interactionId) {
  validateInteractionId(interactionId);
  const screenshotsDir = path.resolve(getScreenshotsDir());
  const dest = path.resolve(path.join(screenshotsDir, `${interactionId}.png`));
  if (!dest.startsWith(`${screenshotsDir}${path.sep}`)) {
    throw new Error('Invalid interactionId');
  }
  return dest;
}

function writeScreenshotFromBase64(base64, interactionId) {
  const dest = resolveScreenshotPath(interactionId);
  const buffer = Buffer.from(base64, 'base64');
  fs.writeFileSync(dest, buffer);
  return dest;
}

function patchResponseSoFar(id, responseSoFar) {
  validateInteractionId(id);
  const db = getDb();
  db.prepare(`UPDATE interactions SET response_so_far = ? WHERE id = ?`).run(
    responseSoFar,
    id,
  );
  return getInteraction(id);
}

function upsertInteraction(data) {
  const db = getDb();
  const rawId = data.id ?? data.interactionId;
  const id = rawId ?? uuidv4();
  if (rawId) {
    validateInteractionId(id);
  }
  const now = data.created_at ?? Date.now();

  let screenshotPath = data.screenshot_path ?? null;
  if (data.screenshot && typeof data.screenshot === 'string') {
    const raw = data.screenshot.replace(/^data:image\/\w+;base64,/, '');
    screenshotPath = writeScreenshotFromBase64(raw, id);
  }

  db.prepare(
    `INSERT INTO interactions (id, created_at, prompt, response_so_far, screenshot_path, model, crop_hash)
     VALUES (@id, @created_at, @prompt, @response_so_far, @screenshot_path, @model, @crop_hash)
     ON CONFLICT(id) DO UPDATE SET
       prompt = COALESCE(excluded.prompt, interactions.prompt),
       response_so_far = COALESCE(excluded.response_so_far, interactions.response_so_far),
       screenshot_path = COALESCE(excluded.screenshot_path, interactions.screenshot_path),
       model = COALESCE(excluded.model, interactions.model),
       crop_hash = COALESCE(excluded.crop_hash, interactions.crop_hash)`,
  ).run({
    id,
    created_at: now,
    prompt: data.prompt ?? null,
    response_so_far: data.response_so_far ?? null,
    screenshot_path: screenshotPath,
    model: data.model ?? null,
    crop_hash: data.crop_hash ?? null,
  });

  return getInteraction(id);
}

function markSynced(id, conversationId) {
  const db = getDb();
  db.prepare(
    `UPDATE interactions SET synced_to_chat = 1, conversation_id = ? WHERE id = ?`,
  ).run(conversationId, id);
  return getInteraction(id);
}

function insertRagChunk({ fileId, userId, interactionId, kind }) {
  const db = getDb();
  db.prepare(
    `INSERT OR REPLACE INTO remi_rag_chunks (file_id, user_id, interaction_id, kind, created_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).run(fileId, userId, interactionId ?? null, kind, Date.now());
}

function nextRagSeq(interactionId) {
  const db = getDb();
  const row = db
    .prepare(`SELECT COUNT(*) AS count FROM remi_rag_chunks WHERE interaction_id = ?`)
    .get(interactionId);
  return (row?.count ?? 0) + 1;
}

function listRagFileIdsForUser(userId, limit = 30) {
  const db = getDb();
  const rows = db
    .prepare(
      `SELECT file_id FROM remi_rag_chunks
       WHERE user_id = ?
       ORDER BY created_at DESC
       LIMIT ?`,
    )
    .all(userId, limit);
  return rows.map((r) => r.file_id);
}

function closeDb() {
  if (dbInstance) {
    dbInstance.close();
    dbInstance = null;
  }
}

module.exports = {
  getDbPath,
  getScreenshotsDir,
  validateInteractionId,
  resolveInteractionScreenshotPath,
  listInteractions,
  getInteraction,
  upsertInteraction,
  patchResponseSoFar,
  markSynced,
  insertRagChunk,
  nextRagSeq,
  listRagFileIdsForUser,
  closeDb,
};