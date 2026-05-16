const fs = require('fs');
const express = require('express');
const { logger } = require('@librechat/data-schemas');
const requireJwtAuth = require('~/server/middleware/requireJwtAuth');
const handoffStore = require('~/server/services/remi/handoffStore');
const { handoffInteraction } = require('~/server/services/remi/handoffService');

const router = express.Router();
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
    if (!interaction?.screenshotPath || !fs.existsSync(interaction.screenshotPath)) {
      return res.status(404).json({ error: 'Screenshot not found' });
    }
    res.sendFile(interaction.screenshotPath);
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

router.post('/context', (req, res) => {
  try {
    const { screenshot, prompt, response_so_far, interactionId, model, crop_hash } = req.body ?? {};
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
