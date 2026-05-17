# REMi handoff contract (mouse layer ↔ LibreChat)

**Contract version:** v1.1 (multi-screenshot files + overlay handoff; SQLite columns unchanged)

## SQLite

**Default path (macOS):** `~/Library/Application Support/REMi/interactions.sqlite`

**Screenshots:**

- Primary: `~/Library/Application Support/REMi/screenshots/{interactionId}.png`
- Extras (from `additionalScreenshotsBase64` on `/query`): `{interactionId}-1.png`, `{interactionId}-2.png`, `{interactionId}-3.png`

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

## HTTP API

Base: `/api/remi`

### Device auth (no JWT required)

| Method | Path | Body | Response |
|--------|------|------|----------|
| `POST` | `/device/login` | `{ email, password }` | `{ token, refreshToken, expiresAt, user }` |
| `POST` | `/device/refresh` | `{ refreshToken }` | `{ token, refreshToken, expiresAt, user }` |

MagicPointer stores `token` / `refreshToken` in Keychain. Accounts with 2FA enabled receive `403` on device login.

### Authenticated routes (JWT required)

| Method | Path | Body | Response |
|--------|------|------|----------|
| `POST` | `/query` | See below | `text/event-stream` (SSE) |
| `POST` | `/context` | `{ interactionId?, prompt?, response_so_far?, screenshot?, model?, crop_hash? }` | Interaction object |
| `GET` | `/interactions?cursor=&limit=` | — | `{ interactions, nextCursor }` |
| `GET` | `/interactions/:id` | — | Interaction object |
| `GET` | `/interactions/:id/screenshot` | — | PNG bytes |
| `POST` | `/handoff` | `{ interactionId, response_so_far? }` | `{ conversationId, alreadySynced? }` |
| `GET` | `/catalog` | — | `{ agents: [{ id, name, description? }], skills: [{ name, displayName?, description? }] }` |
| `POST` | `/index` | `{ interactionId, text, appName? }` | `{ fileId, indexed, reason? }` |

Auth: `Authorization: Bearer <jwt>` from LibreChat login or device login.

### RAG persistent context

Requires `RAG_API_URL` (and `rag_api` + `vectordb` from `./scripts/dev-mac.sh`). Set `RAG_OPENAI_API_KEY` to your OpenRouter key for embeddings.

- Captures and completed Q&A turns are embedded under `entity_id = remi-user:{userId}`.
- `POST /index` or `POST /context` (with `hoveredText`) indexes text; `POST /query` retrieves relevant chunks into the system prompt.
- Chunk metadata is tracked in SQLite table `remi_rag_chunks` (same DB file as interactions).

### MagicPointer commands

In the overlay text field:

- `@AgentName` — run via LibreChat agents runtime (`agentId` in body)
- `/skill-name` — invoke skill(s); requires `@agent` or `REMI_DEFAULT_AGENT_ID`

Server also accepts explicit `agentId` and `manualSkills[]` on `POST /query`.

### `POST /query` (MagicPointer inference)

**Body:**

```json
{
  "interactionId": "uuid (required, [A-Za-z0-9_-]{1,128})",
  "query": "user question",
  "llm": "claude | chatgpt | gemini",
  "captureMode": "cursor | selection",
  "cursorX": 0,
  "cursorY": 0,
  "selectionRect": { "x", "y", "width", "height" },
  "hoveredText": "optional",
  "appName": "optional",
  "screenshotBase64": "optional",
  "mergedContextText": "optional",
  "screenshotCount": 0,
  "additionalScreenshotsBase64": ["optional"],
  "agentId": "optional",
  "manualSkills": ["optional"]
}
```

**SSE response** (MagicPointer-compatible):

- Token: `data: <plaintext>\n\n`
- Done: `data: [DONE]\n\n`
- Error (after stream started): `data: [ERROR] <message>\n\n`

Server upserts SQLite: `prompt`, primary `screenshot`, extra PNG files, `model` at start; debounced `response_so_far` during stream. Follow-up queries in the same overlay session reuse one `interactionId` and append prior Q/A into `prompt` (capped at 8k chars) before handoff.

### Overlay → chat handoff (MagicPointer)

1. Overlay opens with a stable `sessionInteractionId` (UUID for the panel lifetime).
2. `POST /query` streams the answer; optional `POST /context` patches `response_so_far` for Mouse History.
3. User clicks **Open in chat** (or ⌘⇧O) → `POST /handoff` → browser opens `{REMI_LIBRECHAT_WEB_URL or http://localhost:3090}/c/{conversationId}` (Vite dev UI; set `REMI_LIBRECHAT_WEB_URL=http://localhost:3080` when using Docker-only).
4. Chat user message includes text + all stored screenshots (`message.files` for inline display + `content` image parts).
5. Assistant message is pre-filled from `response_so_far` (overlay passes latest transcript on handoff).
6. Second open uses `alreadySynced` + stored `conversation_id` (no duplicate Mongo thread).

**Model map:**

| `llm` | OpenRouter model |
|-------|------------------|
| `claude` | `anthropic/claude-sonnet-4` |
| `chatgpt` | `openai/gpt-4o-mini` |
| `gemini` | `google/gemini-2.5-flash-preview` |

- `screenshot` in `/context` or `/query`: base64 or `data:image/png;base64,...` (max ~3MB JSON body).
- `interactionId` must not contain path segments (`..`, `/`); invalid ids return `400`/`500` on write.

## Docker dev

[`config/docker-compose.remi.yaml`](../config/docker-compose.remi.yaml) mounts `~/Library/Application Support/REMi` → `/remi-handoff` and sets `REMI_HANDOFF_DB_PATH=/remi-handoff/interactions.sqlite`.

The API image must include `better-sqlite3` (build locally):

```bash
cd librechat
docker compose -f docker-compose.yml -f ../config/docker-compose.remi.yaml build api
```

## Manual test (no Swift)

```bash
# After login, set TOKEN

# Catalog (agents + skills for overlay)
curl -s http://localhost:3080/api/remi/catalog -H "Authorization: Bearer $TOKEN"

# Index a capture chunk
curl -s -X POST http://localhost:3080/api/remi/index \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"interactionId":"test-capture-1","text":"User was reading about vector databases.","appName":"Safari"}'

# Query (SSE) — should include RAG context from prior index
curl -N -X POST http://localhost:3080/api/remi/query \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{"interactionId":"test-capture-1","query":"What was I reading about?","llm":"claude","captureMode":"cursor","cursorX":0,"cursorY":0}'

# Agent + skill (replace AGENT_ID)
curl -N -X POST http://localhost:3080/api/remi/query \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{"interactionId":"test-agent-1","query":"@MyAgent /my-skill hello","llm":"claude","captureMode":"cursor","cursorX":0,"cursorY":0,"agentId":"AGENT_ID","manualSkills":["my-skill"]}'

curl -s -X POST http://localhost:3080/api/remi/handoff \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"interactionId":"<id from above>"}'
```
