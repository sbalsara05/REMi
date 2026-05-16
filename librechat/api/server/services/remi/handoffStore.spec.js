const fs = require('fs');
const os = require('os');
const path = require('path');

const ONE_BY_ONE_PNG_BASE64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';

describe('handoffStore', () => {
  let tempDir;
  let handoffStore;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'remi-handoff-test-'));
    process.env.REMI_HANDOFF_DB_PATH = path.join(tempDir, 'interactions.sqlite');
    jest.resetModules();
    handoffStore = require('./handoffStore');
  });

  afterEach(() => {
    handoffStore.closeDb();
    delete process.env.REMI_HANDOFF_DB_PATH;
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it('returns empty list for a new database', () => {
    const result = handoffStore.listInteractions({ limit: 25 });
    expect(result).toEqual({ interactions: [], nextCursor: null });
  });

  it('upserts and retrieves an interaction', () => {
    const created = handoffStore.upsertInteraction({
      id: 'interaction-1',
      prompt: 'What is on screen?',
      response_so_far: 'A toolbar.',
    });

    expect(created).toMatchObject({
      id: 'interaction-1',
      prompt: 'What is on screen?',
      responseSoFar: 'A toolbar.',
      syncedToChat: false,
      conversationId: null,
    });
    expect(created.createdAt).toEqual(expect.any(Number));

    const fetched = handoffStore.getInteraction('interaction-1');
    expect(fetched).toEqual(created);
  });

  it('merges fields on conflict without wiping existing values', () => {
    handoffStore.upsertInteraction({
      id: 'interaction-merge',
      prompt: 'Initial prompt',
      response_so_far: 'Initial response',
    });

    handoffStore.upsertInteraction({
      id: 'interaction-merge',
      prompt: 'Updated prompt',
    });

    const row = handoffStore.getInteraction('interaction-merge');
    expect(row.prompt).toBe('Updated prompt');
    expect(row.responseSoFar).toBe('Initial response');
  });

  it('writes screenshot files from base64 and data-uri payloads', () => {
    const withRaw = handoffStore.upsertInteraction({
      id: 'shot-raw',
      screenshot: ONE_BY_ONE_PNG_BASE64,
    });
    expect(withRaw.screenshotPath).toBeTruthy();
    expect(fs.existsSync(withRaw.screenshotPath)).toBe(true);

    const withDataUri = handoffStore.upsertInteraction({
      id: 'shot-uri',
      screenshot: `data:image/png;base64,${ONE_BY_ONE_PNG_BASE64}`,
    });
    expect(withDataUri.screenshotPath).toBeTruthy();
    expect(fs.existsSync(withDataUri.screenshotPath)).toBe(true);
  });

  it('rejects path traversal in interaction id when writing screenshots', () => {
    const evilId = '../../../tmp/evil';
    const escapeTarget = path.resolve(handoffStore.getScreenshotsDir(), `${evilId}.png`);
    const outsideScreenshotsDir = !escapeTarget.startsWith(
      `${path.resolve(handoffStore.getScreenshotsDir())}${path.sep}`,
    );
    expect(outsideScreenshotsDir).toBe(true);

    expect(() =>
      handoffStore.upsertInteraction({
        id: evilId,
        screenshot: ONE_BY_ONE_PNG_BASE64,
      }),
    ).toThrow('Invalid interactionId');

    expect(fs.existsSync(escapeTarget)).toBe(false);
  });

  it('stores screenshots only inside the screenshots directory', () => {
    const created = handoffStore.upsertInteraction({
      id: 'safe-shot',
      screenshot: ONE_BY_ONE_PNG_BASE64,
    });
    const screenshotsDir = path.resolve(handoffStore.getScreenshotsDir());
    const resolved = path.resolve(created.screenshotPath);
    expect(resolved.startsWith(`${screenshotsDir}${path.sep}`)).toBe(true);
  });

  it('paginates interactions by created_at descending', () => {
    const base = Date.now();
    for (let i = 0; i < 3; i += 1) {
      handoffStore.upsertInteraction({
        id: `page-${i}`,
        created_at: base - i * 1000,
        prompt: `Prompt ${i}`,
      });
    }

    const firstPage = handoffStore.listInteractions({ limit: 2 });
    expect(firstPage.interactions).toHaveLength(2);
    expect(firstPage.interactions[0].id).toBe('page-0');
    expect(firstPage.nextCursor).toBe(String(firstPage.interactions[1].createdAt));

    const secondPage = handoffStore.listInteractions({
      limit: 2,
      cursor: firstPage.nextCursor,
    });
    expect(secondPage.interactions).toHaveLength(1);
    expect(secondPage.interactions[0].id).toBe('page-2');
    expect(secondPage.nextCursor).toBeNull();
  });

  it('marks an interaction as synced with a conversation id', () => {
    handoffStore.upsertInteraction({ id: 'sync-me', prompt: 'Hello' });
    const synced = handoffStore.markSynced('sync-me', 'convo-abc');

    expect(synced).toMatchObject({
      id: 'sync-me',
      syncedToChat: true,
      conversationId: 'convo-abc',
    });
  });
});
