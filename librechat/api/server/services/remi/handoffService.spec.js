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
    uploadImageBuffer.mockResolvedValue({ filepath: '/files/screenshot.png' });
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
