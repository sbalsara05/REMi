const { validateQueryBody } = require('./queryHandler');

jest.mock('./handoffStore', () => ({
  validateInteractionId: jest.fn((id) => {
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(id)) {
      throw new Error('Invalid interactionId');
    }
  }),
}));

describe('queryHandler.validateQueryBody', () => {
  it('accepts a valid payload', () => {
    const result = validateQueryBody({
      interactionId: 'abc-123',
      query: '  What is this?  ',
      llm: 'claude',
      captureMode: 'selection',
      cursorX: 1,
      cursorY: 2,
    });
    expect(result).toMatchObject({
      interactionId: 'abc-123',
      query: 'What is this?',
      llm: 'claude',
      captureMode: 'selection',
    });
  });

  it('rejects missing interactionId', () => {
    expect(() => validateQueryBody({ query: 'hi', llm: 'claude' })).toThrow('interactionId');
  });

  it('rejects path traversal interactionId', () => {
    expect(() =>
      validateQueryBody({
        interactionId: '../evil',
        query: 'hi',
        llm: 'claude',
      }),
    ).toThrow('Invalid interactionId');
  });

  it('rejects empty query', () => {
    expect(() =>
      validateQueryBody({
        interactionId: 'ok',
        query: '   ',
        llm: 'claude',
      }),
    ).toThrow('query is required');
  });
});
