# REMi handoff contract (mouse layer ↔ LibreChat)

## SQLite

**Default path (macOS):** `~/Library/Application Support/REMi/interactions.sqlite`

**Screenshots:** `~/Library/Application Support/REMi/screenshots/{interactionId}.png`

**Override:** `REMI_HANDOFF_DB_PATH` (LibreChat API and mouse app must match).

### Schema

```sql
CREATE TABLE interactions (
  id TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL,  -- Unix ms
  prompt TEXT,
  response_so_far TEXT,
  screenshot_path TEXT,         -- absolute path to PNG on disk
  model TEXT,
  crop_hash TEXT,
  synced_to_chat INTEGER DEFAULT 0,
  conversation_id TEXT
);
```

Mouse branch **writes** rows (and PNG files). LibreChat **reads** and updates `synced_to_chat` / `conversation_id` on handoff.

## HTTP API (JWT required)

Base: `/api/remi`

| Method | Path | Body | Response |
|--------|------|------|----------|
| `POST` | `/context` | `{ interactionId?, prompt?, response_so_far?, screenshot?, model?, crop_hash? }` | Interaction object |
| `GET` | `/interactions?cursor=&limit=` | — | `{ interactions, nextCursor }` |
| `GET` | `/interactions/:id` | — | Interaction object |
| `GET` | `/interactions/:id/screenshot` | — | PNG bytes |
| `POST` | `/handoff` | `{ interactionId }` | `{ conversationId, alreadySynced? }` |

- `screenshot` in `/context`: base64 or `data:image/png;base64,...` (max ~3MB JSON body).
- Auth: `Authorization: Bearer <jwt>` from LibreChat login.

## Docker dev

[`config/docker-compose.remi.yaml`](../config/docker-compose.remi.yaml) mounts `~/Library/Application Support/REMi` → `/remi-handoff` and sets `REMI_HANDOFF_DB_PATH=/remi-handoff/interactions.sqlite`.

The API image must include `better-sqlite3` (build locally):

```bash
cd librechat
docker compose -f docker-compose.yml -f ../config/docker-compose.remi.yaml build api
```

## Manual test (no Swift)

```bash
# After login, set TOKEN and seed via API:
curl -s -X POST http://localhost:3080/api/remi/context \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"What is on screen?","response_so_far":"A sample response."}'

curl -s -X POST http://localhost:3080/api/remi/handoff \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"interactionId":"<id from above>"}'
```
