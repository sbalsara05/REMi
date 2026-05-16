const { logger } = require('@librechat/data-schemas');
const { resolveOpenRouterModel } = require('./modelMap');
const { buildMessages } = require('./promptBuilder');

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';

function getOpenRouterHeaders() {
  const apiKey = process.env.OPENROUTER_KEY;
  if (!apiKey) {
    const error = new Error('OPENROUTER_KEY is not configured');
    error.status = 503;
    throw error;
  }

  const referer = process.env.DOMAIN_SERVER || process.env.DOMAIN_CLIENT || 'http://localhost:3080';
  return {
    Authorization: `Bearer ${apiKey}`,
    'Content-Type': 'application/json',
    'HTTP-Referer': referer,
    'X-Title': process.env.APP_TITLE || 'REMi',
  };
}

function extractDeltaContent(parsed) {
  const delta = parsed?.choices?.[0]?.delta;
  if (!delta) {
    return '';
  }
  if (typeof delta.content === 'string') {
    return delta.content;
  }
  if (Array.isArray(delta.content)) {
    return delta.content
      .filter((part) => part?.type === 'text' && typeof part.text === 'string')
      .map((part) => part.text)
      .join('');
  }
  return '';
}

function parseOpenRouterSseLines(buffer) {
  const events = [];
  const lines = buffer.split('\n');
  const remainder = lines.pop() ?? '';

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed.startsWith('data:')) {
      continue;
    }
    const data = trimmed.slice(5).trim();
    if (!data || data === '[DONE]') {
      continue;
    }
    try {
      events.push(JSON.parse(data));
    } catch {
      logger.warn('[remi] Skipping malformed OpenRouter SSE chunk');
    }
  }

  return { events, remainder };
}

async function* streamOpenRouterCompletion(payload) {
  const model = resolveOpenRouterModel(payload.llm);
  const body = {
    model,
    stream: true,
    messages: buildMessages(payload),
  };

  const response = await fetch(OPENROUTER_URL, {
    method: 'POST',
    headers: getOpenRouterHeaders(),
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const text = await response.text().catch(() => '');
    const error = new Error(text || `OpenRouter request failed (${response.status})`);
    error.status = response.status >= 500 ? 502 : response.status;
    throw error;
  }

  if (!response.body) {
    const error = new Error('OpenRouter returned no response body');
    error.status = 502;
    throw error;
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    buffer += decoder.decode(value, { stream: true });
    const { events, remainder } = parseOpenRouterSseLines(buffer);
    buffer = remainder;

    for (const event of events) {
      const token = extractDeltaContent(event);
      if (token) {
        yield token;
      }
    }
  }

  if (buffer.trim()) {
    const { events } = parseOpenRouterSseLines(`${buffer}\n`);
    for (const event of events) {
      const token = extractDeltaContent(event);
      if (token) {
        yield token;
      }
    }
  }
}

module.exports = {
  OPENROUTER_URL,
  extractDeltaContent,
  parseOpenRouterSseLines,
  streamOpenRouterCompletion,
};
