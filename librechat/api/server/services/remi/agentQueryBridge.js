const crypto = require('crypto');
const { logger } = require('@librechat/data-schemas');
const {
  Constants,
  EModelEndpoint,
  parseCompactConvo,
} = require('librechat-data-provider');
const { GenerationJobManager, disposeClient } = require('@librechat/api');
const { initializeClient } = require('~/server/services/Endpoints/agents');
const { buildOptions } = require('~/server/services/Endpoints/agents/build');
const { getAppConfig } = require('~/server/services/Config');

function writeSse(res, data) {
  res.write(`data: ${data}\n\n`);
}

function extractTokenFromAgentEvent(event) {
  if (!event || typeof event !== 'object') {
    return '';
  }
  if (event.event === 'on_message_delta') {
    const text = event.data?.delta?.content?.text;
    return typeof text === 'string' ? text : '';
  }
  if (event.type === 'text' && typeof event.text === 'string') {
    return event.text;
  }
  return '';
}

function wrapResponseForRemiTokens(res) {
  let buffer = '';
  const origWrite = res.write.bind(res);
  res.write = function (chunk, encoding, cb) {
    buffer += chunk?.toString?.() ?? '';
    const parts = buffer.split('\n\n');
    buffer = parts.pop() ?? '';
    for (const part of parts) {
      for (const line of part.split('\n')) {
        if (!line.startsWith('data: ')) {
          continue;
        }
        const raw = line.slice(6);
        if (raw === '[DONE]' || raw.startsWith('[ERROR]')) {
          continue;
        }
        try {
          const payload = JSON.parse(raw);
          const token = extractTokenFromAgentEvent(payload);
          if (token) {
            writeSse(res, token);
          }
        } catch {
          // ignore non-agent JSON lines
        }
      }
    }
    if (typeof cb === 'function') {
      cb();
    }
    return true;
  };
}

async function runAgentQuery({
  req,
  res,
  agentId,
  query,
  interactionId,
  manualSkills = [],
  ragContext,
}) {
  if (!req.config) {
    req.config = await getAppConfig({ role: req.user?.role, tenantId: req.user?.tenantId });
  }

  const userId = req.user.id;
  const conversationId = `remi-${interactionId}`;
  const streamId = conversationId;

  const savedBody = { ...req.body };
  req.body = {
    endpoint: EModelEndpoint.agents,
    agent_id: agentId,
    text: query,
    conversationId,
    parentMessageId: Constants.NO_PARENT,
    manualSkills: manualSkills.length > 0 ? manualSkills : undefined,
    isTemporary: true,
    files: [],
  };

  if (ragContext?.trim()) {
    req.body.promptPrefix = `Prior REMi context:\n${ragContext.trim()}`;
  }

  const parsedBody = parseCompactConvo({
    endpoint: EModelEndpoint.agents,
    conversation: req.body,
  });
  const endpointOption = await buildOptions(req, EModelEndpoint.agents, parsedBody, undefined);

  wrapResponseForRemiTokens(res);

  const abortController = new AbortController();
  let client = null;

  try {
    const job = await GenerationJobManager.createJob(streamId, userId, conversationId);
    res.on('close', () => {
      if (!job.abortController.signal.aborted) {
        job.abortController.abort();
      }
    });

    const result = await initializeClient({
      req,
      res,
      signal: job.abortController.signal,
      endpointOption,
    });
    client = result.client;

    const messageOptions = {
      user: userId,
      conversationId,
      parentMessageId: Constants.NO_PARENT,
      abortController: job.abortController,
      userMCPAuthMap: result.userMCPAuthMap,
      progressOptions: { res },
    };

    const response = await client.sendMessage(query, messageOptions);
    const finalText = response?.text ?? '';
    if (finalText && typeof finalText === 'string') {
      // sendMessage may have already streamed deltas; avoid duplicate full text
    }

    await GenerationJobManager.completeJob(streamId);
    writeSse(res, '[DONE]');
    res.end();
    return finalText;
  } catch (error) {
    logger.error('[remi] agent query failed', error);
    if (!res.headersSent) {
      throw error;
    }
    writeSse(res, `[ERROR] ${error.message || 'Agent failed'}`);
    res.end();
    throw error;
  } finally {
    req.body = savedBody;
    if (client) {
      disposeClient(client);
    }
  }
}

module.exports = {
  runAgentQuery,
};
