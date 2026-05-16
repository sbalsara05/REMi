const DEFAULT_MODEL_MAP = {
  claude: 'anthropic/claude-sonnet-4',
  chatgpt: 'openai/gpt-4o-mini',
  gemini: 'google/gemini-2.5-flash-preview',
};

function resolveOpenRouterModel(llm) {
  const key = typeof llm === 'string' ? llm.toLowerCase() : '';
  const model = DEFAULT_MODEL_MAP[key];
  if (!model) {
    const error = new Error(`Unknown llm: ${llm}`);
    error.status = 400;
    throw error;
  }
  return model;
}

module.exports = {
  DEFAULT_MODEL_MAP,
  resolveOpenRouterModel,
};
