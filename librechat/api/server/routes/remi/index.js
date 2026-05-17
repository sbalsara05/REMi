const fs = require('fs');
const express = require('express');
const { logger } = require('@librechat/data-schemas');
const requireJwtAuth = require('~/server/middleware/requireJwtAuth');
const handoffStore = require('~/server/services/remi/handoffStore');
const { handoffInteraction } = require('~/server/services/remi/handoffService');
const { handleRemiQuery } = require('~/server/services/remi/queryHandler');
const { getRemiCatalog } = require('~/server/services/remi/catalogService');
const ragContextService = require('~/server/services/remi/ragContextService');
const deviceRouter = require('./device');

const router = express.Router();

router.use('/device', deviceRouter);
router.use(requireJwtAuth);

router.get('/interactions', (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit, 10) || 25, 100);
    const cursor = req.query.cursor;
    const result = handoffStore.listInteractions({ cursor, limit });
    res.status(200).json(result);
  } catch (error) {
    logger.error('[remi] list interactions failed', error);
    res.status(500).json({ error: 'Failed to list interactions' });
  }
});

router.get('/interactions/:id/screenshot', (req, res) => {
  try {
    const interaction = handoffStore.getInteraction(req.params.id);
    const screenshotPath = handoffStore.resolveInteractionScreenshotPath(interaction);
    if (!screenshotPath) {
      return res.status(404).json({ error: 'Screenshot not found' });
    }
    res.type('png');
    res.sendFile(screenshotPath);
  } catch (error) {
    logger.error('[remi] screenshot failed', error);
    res.status(500).json({ error: 'Failed to load screenshot' });
  }
});

router.get('/interactions/:id', (req, res) => {
  try {
    const interaction = handoffStore.getInteraction(req.params.id);
    if (!interaction) {
      return res.status(404).json({ error: 'Interaction not found' });
    }
    res.status(200).json(interaction);
  } catch (error) {
    logger.error('[remi] get interaction failed', error);
    res.status(500).json({ error: 'Failed to get interaction' });
  }
});

router.post('/query', handleRemiQuery);

router.get('/catalog', async (req, res) => {
  try {
    const catalog = await getRemiCatalog(req);
    res.status(200).json(catalog);
  } catch (error) {
    logger.error('[remi] catalog failed', error);
    res.status(500).json({ error: 'Failed to load catalog' });
  }
});

router.post('/index', async (req, res) => {
  try {
    const { interactionId, text, appName } = req.body ?? {};
    if (!interactionId || typeof interactionId !== 'string') {
      return res.status(400).json({ error: 'interactionId is required' });
    }
    handoffStore.validateInteractionId(interactionId);
    if (!text || typeof text !== 'string' || !text.trim()) {
      return res.status(400).json({ error: 'text is required' });
    }
    const result = await ragContextService.indexCapture({
      req,
      interactionId,
      text,
      appName: typeof appName === 'string' ? appName : null,
    });
    res.status(200).json({
      fileId: result.fileId,
      indexed: result.indexed === true,
      reason: result.reason,
    });
  } catch (error) {
    logger.error('[remi] index failed', error);
    res.status(500).json({ error: 'Failed to index context' });
  }
});

router.post('/context', async (req, res) => {
  try {
    const {
      screenshot,
      prompt,
      response_so_far,
      interactionId,
      model,
      crop_hash,
      hoveredText,
      appName,
    } = req.body ?? {};
    if (!interactionId && !prompt && !response_so_far && !screenshot) {
      return res.status(400).json({ error: 'Provide interactionId, prompt, response_so_far, or screenshot' });
    }

    const interaction = handoffStore.upsertInteraction({
      id: interactionId,
      prompt,
      response_so_far,
      screenshot,
      model,
      crop_hash,
    });

    const indexText =
      (typeof hoveredText === 'string' && hoveredText.trim()) ||
      (typeof prompt === 'string' && prompt.trim()) ||
      null;
    if (interactionId && indexText) {
      ragContextService
        .indexCapture({
          req,
          interactionId,
          text: indexText,
          appName: typeof appName === 'string' ? appName : null,
        })
        .catch((err) => logger.warn('[remi] RAG index capture failed', err));
    }

    res.status(200).json(interaction);
  } catch (error) {
    logger.error('[remi] context upsert failed', error);
    res.status(500).json({ error: 'Failed to save context' });
  }
});

router.post('/handoff', async (req, res) => {
  try {
    const { interactionId } = req.body ?? {};
    if (!interactionId) {
      return res.status(400).json({ error: 'interactionId is required' });
    }

    const result = await handoffInteraction(req, interactionId);
    res.status(200).json(result);
  } catch (error) {
    if (error.status === 404) {
      return res.status(404).json({ error: error.message });
    }
    logger.error('[remi] handoff failed', error);
    res.status(500).json({ error: 'Handoff failed' });
  }
});

module.exports = router;
