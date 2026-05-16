const fs = require('fs');
const os = require('os');
const path = require('path');
const express = require('express');
const request = require('supertest');

const ONE_BY_ONE_PNG_BASE64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';

jest.mock('@librechat/data-schemas', () => ({
  logger: {
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

const mockRequireJwtAuth = jest.fn((req, _res, next) => {
  req.user = { id: 'test-user-remi' };
  next();
});

jest.mock('~/server/middleware/requireJwtAuth', () => mockRequireJwtAuth);

jest.mock('~/server/services/remi/handoffService', () => ({
  handoffInteraction: jest.fn(),
}));

describe('REMi routes', () => {
  let app;
  let tempDir;
  let handoffStore;
  let handoffInteraction;

  beforeAll(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'remi-route-test-'));
    process.env.REMI_HANDOFF_DB_PATH = path.join(tempDir, 'interactions.sqlite');
    jest.resetModules();

    handoffStore = require('~/server/services/remi/handoffStore');
    ({ handoffInteraction } = require('~/server/services/remi/handoffService'));
    const remiRouter = require('../remi');

    app = express();
    app.use(express.json({ limit: '4mb' }));
    app.use('/api/remi', remiRouter);
  });

  afterAll(() => {
    handoffStore.closeDb();
    delete process.env.REMI_HANDOFF_DB_PATH;
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  beforeEach(() => {
    jest.clearAllMocks();
    mockRequireJwtAuth.mockImplementation((req, _res, next) => {
      req.user = { id: 'test-user-remi' };
      next();
    });
    handoffInteraction.mockReset();

    handoffStore.closeDb();
    const dbPath = handoffStore.getDbPath();
    if (fs.existsSync(dbPath)) {
      fs.unlinkSync(dbPath);
    }
    const screenshotsDir = handoffStore.getScreenshotsDir();
    if (fs.existsSync(screenshotsDir)) {
      fs.rmSync(screenshotsDir, { recursive: true, force: true });
    }
  });

  describe('authentication', () => {
    it('returns 401 when Authorization is missing', async () => {
      mockRequireJwtAuth.mockImplementation((_req, res) => {
        res.status(401).json({ message: 'Unauthorized' });
      });

      const response = await request(app).get('/api/remi/interactions');
      expect(response.status).toBe(401);
      expect(response.body).toEqual({ message: 'Unauthorized' });
    });
  });

  describe('POST /context', () => {
    it('returns 400 when the body is empty', async () => {
      const response = await request(app)
        .post('/api/remi/context')
        .set('Authorization', 'Bearer test-token')
        .send({});

      expect(response.status).toBe(400);
      expect(response.body.error).toContain('Provide interactionId');
    });

    it('upserts context and returns the interaction', async () => {
      const response = await request(app)
        .post('/api/remi/context')
        .set('Authorization', 'Bearer test-token')
        .send({
          interactionId: 'ctx-1',
          prompt: 'What is on screen?',
          response_so_far: 'A dock.',
        });

      expect(response.status).toBe(200);
      expect(response.body).toMatchObject({
        id: 'ctx-1',
        prompt: 'What is on screen?',
        responseSoFar: 'A dock.',
        syncedToChat: false,
      });
    });

    it('returns 500 when interactionId would escape the screenshots directory', async () => {
      const escapeTarget = path.resolve(
        handoffStore.getScreenshotsDir(),
        '../../../tmp/evil.png',
      );

      const response = await request(app)
        .post('/api/remi/context')
        .set('Authorization', 'Bearer test-token')
        .send({
          interactionId: '../../../tmp/evil',
          screenshot: ONE_BY_ONE_PNG_BASE64,
        });

      expect(response.status).toBe(500);
      expect(response.body).toEqual({ error: 'Failed to save context' });
      expect(fs.existsSync(escapeTarget)).toBe(false);
    });
  });

  describe('GET /interactions', () => {
    it('returns an empty list for a fresh database', async () => {
      const response = await request(app)
        .get('/api/remi/interactions')
        .set('Authorization', 'Bearer test-token');

      expect(response.status).toBe(200);
      expect(response.body).toEqual({ interactions: [], nextCursor: null });
    });

    it('caps limit at 100', async () => {
      const response = await request(app)
        .get('/api/remi/interactions?limit=101')
        .set('Authorization', 'Bearer test-token');

      expect(response.status).toBe(200);
      expect(response.body.interactions).toEqual([]);
    });
  });

  describe('GET /interactions/:id', () => {
    it('returns 404 for unknown ids', async () => {
      const response = await request(app)
        .get('/api/remi/interactions/missing')
        .set('Authorization', 'Bearer test-token');

      expect(response.status).toBe(404);
      expect(response.body).toEqual({ error: 'Interaction not found' });
    });
  });

  describe('GET /interactions/:id/screenshot', () => {
    it('returns 404 when no screenshot exists', async () => {
      handoffStore.upsertInteraction({ id: 'no-shot', prompt: 'Text only' });

      const response = await request(app)
        .get('/api/remi/interactions/no-shot/screenshot')
        .set('Authorization', 'Bearer test-token');

      expect(response.status).toBe(404);
      expect(response.body).toEqual({ error: 'Screenshot not found' });
    });

    it('serves a PNG when a screenshot file exists', async () => {
      handoffStore.upsertInteraction({
        id: 'with-shot',
        screenshot: ONE_BY_ONE_PNG_BASE64,
      });

      const response = await request(app)
        .get('/api/remi/interactions/with-shot/screenshot')
        .set('Authorization', 'Bearer test-token');

      expect(response.status).toBe(200);
      expect(response.headers['content-type']).toMatch(/image\/png|application\/octet-stream/);
    });
  });

  describe('POST /handoff', () => {
    it('returns 400 when interactionId is missing', async () => {
      const response = await request(app)
        .post('/api/remi/handoff')
        .set('Authorization', 'Bearer test-token')
        .send({});

      expect(response.status).toBe(400);
      expect(response.body).toEqual({ error: 'interactionId is required' });
    });

    it('returns 404 when interactionId is unknown', async () => {
      handoffInteraction.mockRejectedValue(
        Object.assign(new Error('Interaction not found'), { status: 404 }),
      );

      const response = await request(app)
        .post('/api/remi/handoff')
        .set('Authorization', 'Bearer test-token')
        .send({ interactionId: 'missing' });

      expect(response.status).toBe(404);
      expect(response.body).toEqual({ error: 'Interaction not found' });
    });

    it('returns conversationId from the handoff service', async () => {
      handoffInteraction.mockResolvedValue({
        conversationId: 'convo-123',
        alreadySynced: false,
      });

      const response = await request(app)
        .post('/api/remi/handoff')
        .set('Authorization', 'Bearer test-token')
        .send({ interactionId: 'ctx-1' });

      expect(response.status).toBe(200);
      expect(response.body).toEqual({
        conversationId: 'convo-123',
        alreadySynced: false,
      });
      expect(handoffInteraction).toHaveBeenCalledWith(
        expect.objectContaining({ user: { id: 'test-user-remi' } }),
        'ctx-1',
      );
    });
  });
});
