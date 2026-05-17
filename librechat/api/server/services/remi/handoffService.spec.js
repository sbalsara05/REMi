const fs = require('fs');
const os = require('os');
const path = require('path');

jest.mock('~/server/services/Files/process', () => ({
  uploadImageBuffer: jest.fn(),
}));

jest.mock('~/models', () => ({
  saveMessage: jest.fn(),
  saveConvo: jest.fn(),
}));

describe('handoffService', () => {
  let tempDir;
  let handoffStore;
  let handoffService;
  let db;
  let uploadImageBuffer;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'remi-handoff-service-'));
    process.env.REMI_HANDOFF_DB_PATH = path.join(tempDir, 'interactions.sqlite');
    jest.resetModules();

    handoffStore = require('./handoffStore');
    handoffService = require('./handoffService');
    db = require('~/models');
    ({ uploadImageBuffer } = require('~/server/services/Files/process'));

    db.saveMessage.mockImplementation(async (_ctx, payload) => payload);
    db.saveConvo.mockResolvedValue(undefined);
    uploadImageBuffer.mockResolvedValue({
      file_id: 'file-shot-1',
      filepath: '/files/screenshot.png',
      filename: 'screenshot.png',
      width: 64,
      height: 64,
    });
  });

  afterEach(() => {
    handoffStore.closeDb();
    delete process.env.REMI_HANDOFF_DB_PATH;
    fs.rmSync(tempDir, { recursive: true, force: true });
    jest.clearAllMocks();
  });

  const req = {
    user: { id: 'user-1' },
    config: { interfaceConfig: {} },
  };

  it('returns 404-shaped error for unknown interactions', async () => {
    await expect(handoffService.handoffInteraction(req, 'missing-id')).rejects.toMatchObject({
      status: 404,
      message: 'Interaction not found',
    });
  });

  it('creates a conversation and marks the interaction synced on first handoff', async () => {
    handoffStore.upsertInteraction({
      id: 'handoff-new',
      prompt: 'Explain this UI',
      response_so_far: 'It is a settings panel.',
    });

    const result = await handoffService.handoffInteraction(req, 'handoff-new');

    expect(result.alreadySynced).toBe(false);
    expect(result.conversationId).toEqual(expect.any(String));
    expect(db.saveMessage).toHaveBeenCalled();
    expect(db.saveConvo).toHaveBeenCalled();

    const row = handoffStore.getInteraction('handoff-new');
    expect(row.syncedToChat).toBe(true);
    expect(row.conversationId).toBe(result.conversationId);
  });

  it('attaches screenshot as IMAGE_FILE content when a screenshot exists', async () => {
    const { ContentTypes } = require('librechat-data-provider');
    const screenshotPath = handoffStore.upsertInteraction({
      id: 'handoff-shot',
      prompt: 'What is this?',
      screenshot: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==',
    }).screenshotPath;

    expect(screenshotPath).toBeTruthy();

    await handoffService.handoffInteraction(req, 'handoff-shot');

    const userSave = db.saveMessage.mock.calls.find(
      ([, payload]) => payload.isCreatedByUser === true,
    );
    expect(userSave).toBeDefined();
    const imagePart = userSave[1].content?.find((part) => part.type === ContentTypes.IMAGE_FILE);
    expect(imagePart).toEqual(
      expect.objectContaining({
        type: ContentTypes.IMAGE_FILE,
        [ContentTypes.IMAGE_FILE]: expect.objectContaining({
          file_id: 'file-shot-1',
          filepath: '/files/screenshot.png',
        }),
      }),
    );
    expect(userSave[1].files).toEqual([
      expect.objectContaining({
        file_id: 'file-shot-1',
        filepath: '/files/screenshot.png',
        type: expect.stringContaining('image'),
      }),
    ]);
  });

  it('attaches multiple IMAGE_FILE parts when extra screenshots exist', async () => {
    const { ContentTypes } = require('librechat-data-provider');
    handoffStore.upsertInteraction({
      id: 'handoff-multi',
      prompt: 'Compare these screens',
      screenshot: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==',
      additionalScreenshots: [
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==',
      ],
    });

    let callCount = 0;
    uploadImageBuffer.mockImplementation(async () => {
      callCount += 1;
      return {
        file_id: `file-shot-${callCount}`,
        filepath: `/files/screenshot-${callCount}.png`,
        filename: `screenshot-${callCount}.png`,
        width: 64,
        height: 64,
      };
    });

    await handoffService.handoffInteraction(req, 'handoff-multi');

    const userSave = db.saveMessage.mock.calls.find(
      ([, payload]) => payload.isCreatedByUser === true,
    );
    const imageParts = userSave[1].content?.filter((part) => part.type === ContentTypes.IMAGE_FILE);
    expect(imageParts).toHaveLength(2);
    expect(userSave[1].files).toHaveLength(2);
  });

  it('patches response_so_far from handoff body before creating messages', async () => {
    handoffStore.upsertInteraction({
      id: 'handoff-response',
      prompt: 'Explain this',
      response_so_far: 'Partial',
    });

    await handoffService.handoffInteraction(req, 'handoff-response', {
      response_so_far: 'Full overlay answer',
    });

    const assistantSave = db.saveMessage.mock.calls.find(
      ([, payload]) => payload.isCreatedByUser === false,
    );
    expect(assistantSave[1].text).toBe('Full overlay answer');
  });

  it('returns alreadySynced without creating a new conversation', async () => {
    handoffStore.upsertInteraction({ id: 'handoff-repeat', prompt: 'Again' });
    handoffStore.markSynced('handoff-repeat', 'existing-convo');

    const result = await handoffService.handoffInteraction(req, 'handoff-repeat');

    expect(result).toEqual({
      conversationId: 'existing-convo',
      alreadySynced: true,
    });
    expect(db.saveMessage).not.toHaveBeenCalled();
    expect(db.saveConvo).not.toHaveBeenCalled();
  });
});
