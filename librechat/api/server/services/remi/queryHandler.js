const { logger } = require('@librechat/data-schemas');
const handoffStore = require('./handoffStore');
const { resolveOpenRouterModel } = require('./modelMap');
const { streamOpenRouterCompletion } = require('./inferenceService');

const HANDOFF_DEBOUNCE_MS = 400;

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
  };
}

async function handleRemiQuery(req, res) {
  let payload;
  try {
    payload = validateQueryBody(req.body);
  } catch (error) {
    return res.status(error.status || 400).json({ error: error.message });
  }

  const model = resolveOpenRouterModel(payload.llm);

  handoffStore.upsertInteraction({
    id: payload.interactionId,
    prompt: payload.query,
    screenshot: payload.screenshotBase64,
    model,
  });

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');
  res.flushHeaders?.();

  let accumulated = '';
  let debounceTimer = null;
  let ended = false;
  let clientDisconnected = false;

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

  const endStream = (errorMessage) => {
    if (ended) {
      return;
    }
    ended = true;
    if (debounceTimer) {
      clearTimeout(debounceTimer);
      debounceTimer = null;
    }
    flushHandoff();
    if (errorMessage) {
      writeSse(res, `[ERROR] ${errorMessage}`);
    } else {
      writeSse(res, '[DONE]');
    }
    res.end();
  };

  req.on('close', () => {
    clientDisconnected = true;
    if (debounceTimer) {
      clearTimeout(debounceTimer);
      debounceTimer = null;
    }
    flushHandoff();
  });

  try {
    for await (const token of streamOpenRouterCompletion(payload)) {
      accumulated += token;
      writeSse(res, token);
      scheduleHandoffFlush();
    }
    endStream();
  } catch (error) {
    logger.error('[remi] query stream failed', error);
    if (!res.headersSent) {
      return res.status(error.status || 502).json({ error: error.message || 'Inference failed' });
    }
    endStream(error.message || 'Inference failed');
  }
}

module.exports = {
  validateQueryBody,
  handleRemiQuery,
};
