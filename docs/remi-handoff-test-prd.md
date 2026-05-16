# REMi LibreChat Handoff — Test Requirements (PRD)

## Overview

REMi mouse layer captures screen interactions (prompt, partial response, screenshot) in SQLite. LibreChat exposes JWT-protected REST APIs under `/api/remi` and a **Mouse History** sidebar panel when `interface.remi.mouseHistory: true` in `config/librechat.yaml`.

## Data layer (SQLite)

**Default DB (macOS):** `~/Library/Application Support/REMi/interactions.sqlite`  
**Screenshots:** `~/Library/Application Support/REMi/screenshots/{interactionId}.png`  
**Override:** `REMI_HANDOFF_DB_PATH` — must match between mouse app and LibreChat API.

### Schema

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT PK | UUID |
| created_at | INTEGER | Unix ms |
| prompt | TEXT | nullable |
| response_so_far | TEXT | nullable |
| screenshot_path | TEXT | absolute PNG path |
| model | TEXT | nullable |
| crop_hash | TEXT | nullable |
| synced_to_chat | INTEGER | 0/1, default 0 |
| conversation_id | TEXT | set on handoff |

Mouse branch **writes** rows and PNG files. LibreChat **reads** and updates `synced_to_chat` / `conversation_id` on handoff.

## Authentication

All `/api/remi/*` routes use `requireJwtAuth`.

- Missing `Authorization` header → **401**
- Invalid/expired JWT → **401**
- Valid `Authorization: Bearer <jwt>` from LibreChat login → allowed

## HTTP API

Base path: `/api/remi`

### POST /context

**Body (JSON):** `{ interactionId?, prompt?, response_so_far?, screenshot?, model?, crop_hash? }`

- At least one of `interactionId`, `prompt`, `response_so_far`, or `screenshot` required; else **400** `{ error: "Provide interactionId, prompt, response_so_far, or screenshot" }`
- Without `interactionId`, server generates UUID
- `screenshot`: raw base64 or `data:image/png;base64,...` — written to screenshots dir; max ~3MB JSON body (Express default)
- Upserts row (ON CONFLICT updates non-null fields via COALESCE)
- **200:** interaction object (`id`, `createdAt`, `prompt`, `responseSoFar`, `screenshotPath`, `model`, `cropHash`, `syncedToChat`, `conversationId`)

### GET /interactions

**Query:** `cursor` (created_at ms string), `limit` (default 25, max 100)

- **200:** `{ interactions: [...], nextCursor: string | null }`
- Ordered `created_at DESC`; cursor = `created_at < cursor`
- Empty DB → `{ interactions: [], nextCursor: null }`

### GET /interactions/:id

- Found → **200** interaction object
- Not found → **404** `{ error: "Interaction not found" }`

### GET /interactions/:id/screenshot

- Valid path on disk → PNG file (`sendFile`)
- Missing interaction, missing path, or file not on disk → **404** `{ error: "Screenshot not found" }`

### POST /handoff

**Body:** `{ interactionId }` (required)

- Missing `interactionId` → **400** `{ error: "interactionId is required" }`
- Unknown id → **404** `{ error: "Interaction not found" }`
- First handoff: creates LibreChat conversation + user message (prompt + optional screenshot attachment) + optional assistant message from `responseSoFar`; sets `synced_to_chat=1` and `conversation_id`
- **200:** `{ conversationId, alreadySynced: false }`
- Re-handoff when already synced: **200** `{ conversationId, alreadySynced: true }` (no duplicate conversation)

## UI — Mouse History panel

**Visibility:** Shown when `interface.remi.mouseHistory` is true in librechat.yaml.

**Behavior:**
- Loading: spinner
- API error: error message
- Empty list: "Mouse interactions from the REMi overlay will appear here."
- List items: timestamp, optional screenshot thumbnail (`/api/remi/interactions/:id/screenshot`), prompt/response preview
- Synced items: "· in chat" label, reduced opacity, button "Open chat"
- Unsynced: button "Open in Chat" → POST handoff then navigate to `/c/{conversationId}`
- Already has `conversationId`: navigate directly without handoff API

## Docker dev

`config/docker-compose.remi.yaml`:
- Mounts host `~/Library/Application Support/REMi` (or `REMI_HANDOFF_HOST_DIR`) → `/remi-handoff`
- `REMI_HANDOFF_DB_PATH=/remi-handoff/interactions.sqlite`
- API image must include `better-sqlite3` (local build)

**Tests:** API in container reads/writes same DB as host mouse app when mount and env align; wrong path → empty list or missing screenshots.

## Edge cases & non-functional

| Scenario | Expected |
|----------|----------|
| POST /handoff without interactionId | 400 |
| POST /handoff unknown id | 404 |
| POST /context empty body | 400 |
| GET screenshot for id without file | 404 |
| Large screenshot (>~3MB JSON) | 413 or request failure |
| Pagination: `limit=101` | capped at 100 |
| Handoff with screenshot upload failure | conversation still created (text only); warn in logs |
| WAL mode SQLite | concurrent read during mouse writes |

## Manual API smoke (reference)

```bash
curl -X POST http://localhost:3080/api/remi/context -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"prompt":"What is on screen?","response_so_far":"A sample response."}'
curl -X POST http://localhost:3080/api/remi/handoff -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"interactionId":"<id>"}'
```

## Test coverage areas (required)

1. **API:** POST /context, GET /interactions (pagination), GET /interactions/:id, GET screenshot, POST /handoff (new + alreadySynced)
2. **Auth:** missing/invalid JWT → 401
3. **SQLite:** empty DB, upsert, handoff marks synced_to_chat
4. **UI:** panel visible when flag on, Open in Chat navigation, empty state
5. **Docker:** REMI_HANDOFF_DB_PATH container vs host
6. **Edge:** missing interactionId, 404 handoff, large screenshot rejection
