const { logger } = require('@librechat/data-schemas');
const handoffStore = require('./handoffStore');
const { resolveOpenRouterModel } = require('./modelMap');
const { streamOpenRouterCompletion } = require('./inferenceService');
const { buildSystemPrompt } = require('./promptBuilder');
const ragContextService = require('./ragContextService');
const { parseQueryDirectives } = require('./queryDirectives');
const { getRemiCatalog, resolveDefaultAgentId } = require('./catalogService');
const { runAgentQuery } = require('./agentQueryBridge');

const HANDOFF_DEBOUNCE_MS = 400;
const HANDOFF_PROMPT_MAX_LEN = 8000;

function buildHandoffPrompt(interactionId, newQuery) {
  const existing = handoffStore.getInteraction(interactionId);
  if (!existing?.prompt?.trim() || !existing?.responseSoFar?.trim()) {
    return newQuery;
  }
  const transcript = [
    `User: ${existing.prompt.trim()}`,
    `Assistant: ${existing.responseSoFar.trim()}`,
    `User: ${newQuery}`,
  ].join('\n\n');
  return transcript.length > HANDOFF_PROMPT_MAX_LEN
    ? transcript.slice(0, HANDOFF_PROMPT_MAX_LEN)
    : transcript;
}

function writeSse(res, data) {
  res.write(`data: ${data}\n\n`);
}

function validateQueryBody(body) {
  const {
    interactionId,
    query,
    llm,
    captureMode,
    cursorX,
    cursorY,
    selectionRect,
    hoveredText,
    appName,
    screenshotBase64,
    additionalScreenshotsBase64,
    mergedContextText,
    screenshotCount,
    agentId,
    manualSkills,
  } = body ?? {};

  if (!interactionId || typeof interactionId !== 'string') {
    const error = new Error('interactionId is required');
    error.status = 400;
    throw error;
  }
  handoffStore.validateInteractionId(interactionId);

  if (!query || typeof query !== 'string' || !query.trim()) {
    const error = new Error('query is required');
    error.status = 400;
    throw error;
  }

  if (!llm || typeof llm !== 'string') {
    const error = new Error('llm is required');
    error.status = 400;
    throw error;
  }

  const bodyManualSkills = Array.isArray(manualSkills)
    ? manualSkills.filter((s) => typeof s === 'string' && s.trim())
    : [];

  return {
    interactionId,
    query: query.trim(),
    llm,
    captureMode: captureMode === 'selection' ? 'selection' : 'cursor',
    cursorX: Number(cursorX) || 0,
    cursorY: Number(cursorY) || 0,
    selectionRect: selectionRect ?? null,
    hoveredText: hoveredText ?? null,
    appName: appName ?? null,
    screenshotBase64: screenshotBase64 ?? null,
    additionalScreenshotsBase64: Array.isArray(additionalScreenshotsBase64)
      ? additionalScreenshotsBase64.filter((item) => typeof item === 'string' && item.length > 0)
      : [],
    mergedContextText: typeof mergedContextText === 'string' ? mergedContextText : null,
    screenshotCount: Number.isFinite(Number(screenshotCount)) ? Number(screenshotCount) : 0,
    agentId: typeof agentId === 'string' && agentId.trim() ? agentId.trim() : null,
    manualSkills: bodyManualSkills,
  };
}

async function resolveDirectives(req, payload) {
  const catalog = await getRemiCatalog(req);
  const parsed = parseQueryDirectives(payload.query, catalog);

  let agentId = payload.agentId || parsed.agentId;
  const manualSkills = [
    ...new Set([...(payload.manualSkills ?? []), ...(parsed.manualSkills ?? [])]),
  ];

  if (!agentId && manualSkills.length > 0) {
    agentId = await resolveDefaultAgentId(req);
    if (!agentId) {
      const error = new Error('Pick an agent with @name to use /skills, or set REMI_DEFAULT_AGENT_ID');
      error.status = 400;
      throw error;
    }
  }

  return {
    cleanQuery: parsed.cleanQuery,
    agentId,
    manualSkills,
  };
}

async function handleRemiQuery(req, res) {
  let payload;
  try {
    payload = validateQueryBody(req.body);
  } catch (error) {
    return res.status(error.status || 400).json({ error: error.message });
  }

  let directives;
  try {
    directives = await resolveDirectives(req, payload);
  } catch (error) {
    return res.status(error.status || 400).json({ error: error.message });
  }

  const queryText = directives.cleanQuery;
  let ragContext = '';
  try {
    ragContext = await ragContextService.retrieveForQuery({ req, query: queryText });
  } catch (error) {
    logger.warn('[remi] RAG retrieve failed', error);
  }

  const model = resolveOpenRouterModel(payload.llm);
  const systemPrompt = buildSystemPrompt({
    captureMode: payload.captureMode,
    appName: payload.appName,
    hoveredText: payload.hoveredText,
    cursorX: payload.cursorX,
    cursorY: payload.cursorY,
    selectionRect: payload.selectionRect,
    mergedContextText: payload.mergedContextText,
    screenshotCount: payload.screenshotCount,
    ragContext,
    manualSkills: directives.manualSkills,
  });

  const handoffPrompt = buildHandoffPrompt(payload.interactionId, queryText);

  handoffStore.upsertInteraction({
    id: payload.interactionId,
    prompt: handoffPrompt,
    screenshot: payload.screenshotBase64,
    additionalScreenshots: payload.additionalScreenshotsBase64,
    model,
    appName: payload.appName,
    hoveredText: payload.hoveredText,
    mergedContextText: payload.mergedContextText,
    screenshotCount: payload.screenshotCount,
  });

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');
  res.flushHeaders?.();

  let accumulated = '';
  let debounceTimer = null;
  let ended = false;

  const flushHandoff = () => {
    if (!accumulated) {
      return;
    }
    try {
      handoffStore.patchResponseSoFar(payload.interactionId, accumulated);
    } catch (err) {
      logger.warn('[remi] Failed to patch response_so_far:', err);
    }
  };

  const scheduleHandoffFlush = () => {
    if (debounceTimer) {
      clearTimeout(debounceTimer);
    }
    debounceTimer = setTimeout(() => {
      debounceTimer = null;
      flushHandoff();
    }, HANDOFF_DEBOUNCE_MS);
  };

  const endStream = async (errorMessage) => {
    if (ended) {
      return;
    }
    ended = true;
    if (debounceTimer) {
      clearTimeout(debounceTimer);
      debounceTimer = null;
    }
    flushHandoff();
    if (!errorMessage && accumulated) {
      ragContextService
        .indexTurn({
          req,
          interactionId: payload.interactionId,
          query: queryText,
          response: accumulated,
        })
        .catch((err) => logger.warn('[remi] RAG index turn failed', err));
    }
    if (errorMessage) {
      writeSse(res, `[ERROR] ${errorMessage}`);
    } else {
      writeSse(res, '[DONE]');
    }
    res.end();
  };

  req.on('close', () => {
    if (debounceTimer) {
      clearTimeout(debounceTimer);
      debounceTimer = null;
    }
    flushHandoff();
  });

  if (directives.agentId) {
    try {
      const finalText = await runAgentQuery({
        req,
        res,
        agentId: directives.agentId,
        query: queryText,
        interactionId: payload.interactionId,
        manualSkills: directives.manualSkills,
        ragContext,
      });
      accumulated = finalText || accumulated;
      if (debounceTimer) {
        clearTimeout(debounceTimer);
        debounceTimer = null;
      }
      flushHandoff();
      ragContextService
        .indexTurn({
          req,
          interactionId: payload.interactionId,
          query: queryText,
          response: accumulated,
        })
        .catch((err) => logger.warn('[remi] RAG index turn failed', err));
      return;
    } catch (error) {
      logger.error('[remi] agent query stream failed', error);
      if (!res.headersSent) {
        return res.status(error.status || 502).json({ error: error.message || 'Agent failed' });
      }
      return endStream(error.message || 'Agent failed');
    }
  }

  const inferencePayload = {
    ...payload,
    query: queryText,
    systemPrompt,
  };

  try {
    for await (const token of streamOpenRouterCompletion(inferencePayload)) {
      accumulated += token;
      writeSse(res, token);
      scheduleHandoffFlush();
    }
    await endStream();
  } catch (error) {
    logger.error('[remi] query stream failed', error);
    if (!res.headersSent) {
      return res.status(error.status || 502).json({ error: error.message || 'Inference failed' });
    }
    await endStream(error.message || 'Inference failed');
  }
}

module.exports = {
  validateQueryBody,
  handleRemiQuery,
};
