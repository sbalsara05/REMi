const fs = require('fs');
const path = require('path');
const os = require('os');
const { v4: uuidv4 } = require('uuid');
const Database = require('better-sqlite3');
const { logger } = require('@librechat/data-schemas');

const SCHEMA = `
CREATE TABLE IF NOT EXISTS interactions (
  id TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL,
  prompt TEXT,
  response_so_far TEXT,
  screenshot_path TEXT,
  model TEXT,
  crop_hash TEXT,
  synced_to_chat INTEGER DEFAULT 0,
  conversation_id TEXT
);
CREATE INDEX IF NOT EXISTS idx_interactions_created_at ON interactions(created_at DESC);
`;

let dbInstance;

function expandHome(filePath) {
  if (filePath.startsWith('~/')) {
    return path.join(os.homedir(), filePath.slice(2));
  }
  return filePath;
}

function getDefaultDbPath() {
  return path.join(os.homedir(), 'Library', 'Application Support', 'REMi', 'interactions.sqlite');
}

function getDbPath() {
  return expandHome(process.env.REMI_HANDOFF_DB_PATH || getDefaultDbPath());
}

function getScreenshotsDir() {
  return path.join(path.dirname(getDbPath()), 'screenshots');
}

function ensureDirs() {
  const dbPath = getDbPath();
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  fs.mkdirSync(getScreenshotsDir(), { recursive: true });
}

function getDb() {
  if (dbInstance) {
    return dbInstance;
  }
  ensureDirs();
  dbInstance = new Database(getDbPath());
  dbInstance.pragma('journal_mode = WAL');
  dbInstance.exec(SCHEMA);
  logger.info(`[remi] Handoff SQLite: ${getDbPath()}`);
  return dbInstance;
}

function mapRow(row) {
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    createdAt: row.created_at,
    prompt: row.prompt,
    responseSoFar: row.response_so_far,
    screenshotPath: row.screenshot_path,
    model: row.model,
    cropHash: row.crop_hash,
    syncedToChat: Boolean(row.synced_to_chat),
    conversationId: row.conversation_id,
  };
}

function listInteractions({ cursor, limit = 25 }) {
  const db = getDb();
  const params = [];
  let sql = `SELECT id, created_at, prompt, response_so_far, screenshot_path, model, crop_hash,
    synced_to_chat, conversation_id FROM interactions`;
  if (cursor) {
    sql += ` WHERE created_at < ?`;
    params.push(Number(cursor));
  }
  sql += ` ORDER BY created_at DESC LIMIT ?`;
  params.push(limit + 1);

  const rows = db.prepare(sql).all(...params);
  const hasMore = rows.length > limit;
  const interactions = (hasMore ? rows.slice(0, limit) : rows).map(mapRow);
  const nextCursor = hasMore ? String(interactions[interactions.length - 1].createdAt) : null;
  return { interactions, nextCursor };
}

function getInteraction(id) {
  const db = getDb();
  const row = db.prepare(`SELECT * FROM interactions WHERE id = ?`).get(id);
  return mapRow(row);
}

function writeScreenshotFromBase64(base64, interactionId) {
  const buffer = Buffer.from(base64, 'base64');
  const filename = `${interactionId}.png`;
  const dest = path.join(getScreenshotsDir(), filename);
  fs.writeFileSync(dest, buffer);
  return dest;
}

function upsertInteraction(data) {
  const db = getDb();
  const id = data.id ?? data.interactionId ?? uuidv4();
  const now = data.created_at ?? Date.now();

  let screenshotPath = data.screenshot_path ?? null;
  if (data.screenshot && typeof data.screenshot === 'string') {
    const raw = data.screenshot.replace(/^data:image\/\w+;base64,/, '');
    screenshotPath = writeScreenshotFromBase64(raw, id);
  }

  db.prepare(
    `INSERT INTO interactions (id, created_at, prompt, response_so_far, screenshot_path, model, crop_hash)
     VALUES (@id, @created_at, @prompt, @response_so_far, @screenshot_path, @model, @crop_hash)
     ON CONFLICT(id) DO UPDATE SET
       prompt = COALESCE(excluded.prompt, interactions.prompt),
       response_so_far = COALESCE(excluded.response_so_far, interactions.response_so_far),
       screenshot_path = COALESCE(excluded.screenshot_path, interactions.screenshot_path),
       model = COALESCE(excluded.model, interactions.model),
       crop_hash = COALESCE(excluded.crop_hash, interactions.crop_hash)`,
  ).run({
    id,
    created_at: now,
    prompt: data.prompt ?? null,
    response_so_far: data.response_so_far ?? null,
    screenshot_path: screenshotPath,
    model: data.model ?? null,
    crop_hash: data.crop_hash ?? null,
  });

  return getInteraction(id);
}

function markSynced(id, conversationId) {
  const db = getDb();
  db.prepare(
    `UPDATE interactions SET synced_to_chat = 1, conversation_id = ? WHERE id = ?`,
  ).run(conversationId, id);
  return getInteraction(id);
}

function closeDb() {
  if (dbInstance) {
    dbInstance.close();
    dbInstance = null;
  }
}

module.exports = {
  getDbPath,
  getScreenshotsDir,
  listInteractions,
  getInteraction,
  upsertInteraction,
  markSynced,
  closeDb,
};
