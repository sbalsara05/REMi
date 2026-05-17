const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const { ContentTypes, Constants, FileContext } = require('librechat-data-provider');
const { logger } = require('@librechat/data-schemas');
const { uploadImageBuffer } = require('~/server/services/Files/process');
const db = require('~/models');
const handoffStore = require('./handoffStore');

const DEFAULT_ENDPOINT = 'OpenRouter';
const DEFAULT_MODEL = 'openai/gpt-4o-mini';

async function attachScreenshotToContent({ req, screenshotPath, content }) {
  if (!screenshotPath || !fs.existsSync(screenshotPath)) {
    return content;
  }

  try {
    const buffer = fs.readFileSync(screenshotPath);
    const prevFile = req.file;
    req.file = { originalname: path.basename(screenshotPath), mimetype: 'image/png' };
    const file = await uploadImageBuffer({
      req,
      context: FileContext.message_attachment,
      metadata: { buffer, filename: path.basename(screenshotPath) },
    });
    req.file = prevFile;

    if (file?.filepath && file?.file_id) {
      content.push({
        type: ContentTypes.IMAGE_FILE,
        [ContentTypes.IMAGE_FILE]: {
          file_id: file.file_id,
          filename: file.filename,
          filepath: file.filepath,
          width: file.width,
          height: file.height,
        },
      });
    }
  } catch (error) {
    logger.warn('[remi] Screenshot attach failed, continuing with text only:', error);
  }

  return content;
}

async function createHandoffConversation(req, interaction) {
  const conversationId = uuidv4();
  const userMessageId = uuidv4();
  const endpoint = DEFAULT_ENDPOINT;
  const model = interaction.model || DEFAULT_MODEL;
  const reqCtx = {
    userId: req.user.id,
    interfaceConfig: req.config?.interfaceConfig,
  };

  const titleSource = (interaction.prompt || 'Mouse interaction').trim();
  const title = titleSource.length > 80 ? `${titleSource.slice(0, 77)}...` : titleSource;

  const content = [];
  if (interaction.prompt) {
    content.push({ type: ContentTypes.TEXT, text: interaction.prompt });
  }
  await attachScreenshotToContent({ req, screenshotPath: interaction.screenshotPath, content });

  const userPayload = {
    messageId: userMessageId,
    conversationId,
    text: interaction.prompt || 'Mouse interaction',
    user: req.user.id,
    isCreatedByUser: true,
    parentMessageId: Constants.NO_PARENT,
    endpoint,
    model,
  };
  if (content.length > 0) {
    userPayload.content = content;
  }

  const userMsg = await db.saveMessage(reqCtx, userPayload, { context: 'POST /api/remi/handoff' });
  await db.saveConvo(
    reqCtx,
    { ...userMsg, title },
    { context: 'POST /api/remi/handoff' },
  );

  if (interaction.responseSoFar) {
    const assistantMessageId = uuidv4();
    const assistantMsg = await db.saveMessage(
      reqCtx,
      {
        messageId: assistantMessageId,
        conversationId,
        text: interaction.responseSoFar,
        user: req.user.id,
        isCreatedByUser: false,
        parentMessageId: userMessageId,
        endpoint,
        model,
      },
      { context: 'POST /api/remi/handoff assistant' },
    );
    await db.saveConvo(reqCtx, assistantMsg, { context: 'POST /api/remi/handoff assistant' });
  }

  return conversationId;
}

async function handoffInteraction(req, interactionId) {
  const interaction = handoffStore.getInteraction(interactionId);
  if (!interaction) {
    const error = new Error('Interaction not found');
    error.status = 404;
    throw error;
  }

  if (interaction.syncedToChat && interaction.conversationId) {
    return { conversationId: interaction.conversationId, alreadySynced: true };
  }

  const conversationId = await createHandoffConversation(req, interaction);
  handoffStore.markSynced(interactionId, conversationId);
  return { conversationId, alreadySynced: false };
}

module.exports = {
  createHandoffConversation,
  handoffInteraction,
};
