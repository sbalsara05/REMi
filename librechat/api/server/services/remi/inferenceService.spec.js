const {
  extractDeltaContent,
  parseOpenRouterSseLines,
  streamOpenRouterCompletion,
} = require('./inferenceService');
const { resolveOpenRouterModel } = require('./modelMap');
const { buildMessages } = require('./promptBuilder');

describe('remi modelMap', () => {
  it('maps llm aliases to OpenRouter model ids', () => {
    expect(resolveOpenRouterModel('claude')).toBe('anthropic/claude-sonnet-4');
    expect(resolveOpenRouterModel('chatgpt')).toBe('openai/gpt-4o-mini');
    expect(resolveOpenRouterModel('gemini')).toBe('google/gemini-2.5-flash-preview');
  });

  it('throws for unknown llm', () => {
    expect(() => resolveOpenRouterModel('unknown')).toThrow('Unknown llm');
  });
});

describe('remi promptBuilder', () => {
  it('builds system and user messages with screenshot', () => {
    const messages = buildMessages({
      query: 'What is this?',
      captureMode: 'cursor',
      appName: 'Safari',
      hoveredText: 'Hello world',
      cursorX: 10,
      cursorY: 20,
      screenshotBase64: 'abc123',
    });

    expect(messages).toHaveLength(2);
    expect(messages[0].role).toBe('system');
    expect(messages[0].content).toContain('Safari');
    expect(messages[1].role).toBe('user');
    expect(messages[1].content).toHaveLength(2);
    expect(messages[1].content[1].image_url.url).toContain('abc123');
  });
});

describe('remi inferenceService SSE parsing', () => {
  it('extractDeltaContent reads string content', () => {
    expect(
      extractDeltaContent({
        choices: [{ delta: { content: 'hello' } }],
      }),
    ).toBe('hello');
  });

  it('parseOpenRouterSseLines yields parsed events', () => {
    const chunk =
      'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n' +
      'data: [DONE]\n\n' +
      'data: {"choices":[{"delta":{"content":" there"}}]}';

    const { events, remainder } = parseOpenRouterSseLines(chunk);
    expect(events).toHaveLength(1);
    expect(extractDeltaContent(events[0])).toBe('Hi');
    expect(remainder).toContain(' there');
  });
});

describe('streamOpenRouterCompletion', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
    delete process.env.OPENROUTER_KEY;
  });

  it('yields tokens from a mocked OpenRouter stream', async () => {
    process.env.OPENROUTER_KEY = 'test-key';

    const encoder = new TextEncoder();
    const stream = new ReadableStream({
      start(controller) {
        controller.enqueue(
          encoder.encode('data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n'),
        );
        controller.enqueue(
          encoder.encode('data: {"choices":[{"delta":{"content":"!"}}]}\n\n'),
        );
        controller.enqueue(encoder.encode('data: [DONE]\n\n'));
        controller.close();
      },
    });

    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      body: stream,
    });

    const tokens = [];
    for await (const token of streamOpenRouterCompletion({
      llm: 'claude',
      query: 'Hi',
      captureMode: 'cursor',
      cursorX: 0,
      cursorY: 0,
    })) {
      tokens.push(token);
    }

    expect(tokens).toEqual(['Hello', '!']);
    expect(global.fetch).toHaveBeenCalledWith(
      'https://openrouter.ai/api/v1/chat/completions',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          Authorization: 'Bearer test-key',
        }),
      }),
    );
  });
});
