# REMi

OpenRouter-powered chat on your Mac, built on [LibreChat](https://github.com/danny-avila/LibreChat).

## Prerequisites

- [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/) (Apple Silicon or Intel)
- An [OpenRouter API key](https://openrouter.ai/keys)

## Quick start

1. **Create local env at the repo root** (or let `start-mac.sh` copy `env.local.example` on first run)

```bash
cp env.local.example env.local
# Edit env.local and set OPENROUTER_KEY=sk-or-v1-...
```

2. **Start REMi** (syncs config, links `librechat/.env`, starts MongoDB, Meilisearch, and the API container)

```bash
chmod +x scripts/start-mac.sh
./scripts/start-mac.sh
```

First run builds the local API image (`remi-librechat-api:local`, includes REMi handoff / SQLite). Rebuild after API changes:

```bash
cd librechat
docker compose -f docker-compose.yml -f ../config/docker-compose.remi.yaml --env-file ../env.local build api
cd ..
```

3. Open **http://localhost:3080**, register a local account, and select **OpenRouter** models.

## Environment layout

| File | Purpose |
|------|---------|
| `env.local.example` | Committed template — copy to `env.local` |
| `env.local` | Your secrets and settings (gitignored) |
| `config/librechat.yaml` | OpenRouter endpoint + REMi UI flags |
| `config/docker-compose.remi.yaml` | Mounts env, config, and handoff SQLite dir into API |
| `docs/remi-handoff.md` | MagicPointer ↔ LibreChat integration contract |
| `docs/design.md` | REMi brand system (sprites, glass, meta, motion) |
| `docs/parallel-contracts-remi.md` | Parallel workstream boundaries |

Default models: `openai/gpt-4o-mini`, `anthropic/claude-sonnet-4`, `google/gemini-2.5-flash-preview`. With `fetch: true`, the full OpenRouter catalog loads at runtime.

## REMi fork layout

REMi-specific LibreChat code lives under:

- `librechat/api/server/routes/remi/`
- `librechat/api/server/services/remi/`
- `librechat/client/src/components/Remi/`

macOS overlay (MagicPointer):

- `UI/` — Swift sources (`MagicPointer.swift`, `RemiSpriteView.swift`)
- `MagicPointer.xcodeproj` — builds `MagicPointer.app`

To publish as a proper fork: push `librechat/` to `REMi-LibreChat` on GitHub (`remi` branch) and replace the directory with a git submodule.

## Commands

```bash
# Follow API logs
cd librechat && docker compose -f docker-compose.yml -f ../config/docker-compose.remi.yaml --env-file ../env.local logs -f api

# Stop everything
cd librechat && docker compose -f docker-compose.yml -f ../config/docker-compose.remi.yaml --env-file ../env.local down
```

## Development mode (optional)

Docker for data services, native Node for hot reload (REMi routes work without rebuilding the API image):

```bash
./scripts/dev-mac.sh        # MongoDB, Meilisearch, vectordb, rag_api (Docker)
cd librechat
npm run build:client        # first time only — creates client/dist
npm run backend:dev         # terminal 1 — API @ http://localhost:3080
npm run frontend:dev        # terminal 2 — Vite @ http://localhost:3090
```

Scripts link `librechat/.env` → `../env.local` and copy `config/librechat.yaml` into `librechat/`. Set `RAG_OPENAI_API_KEY` in `env.local` (same OpenRouter key) if you use file uploads in dev.

### macOS overlay dev

```bash
chmod +x scripts/dev-watch.sh scripts/sync-mouse-spritesheet.sh
./scripts/sync-mouse-spritesheet.sh   # web spritesheet → UI/Resources/
./scripts/dev-watch.sh              # rebuild MagicPointer on UI/*.swift changes
```

After updating `librechat/client/public/assets/mouse-spritesheet.png`, run the sync script before testing the overlay.

## Tests

REMi uses LibreChat’s existing Jest setup. From the repo root:

```bash
chmod +x scripts/test-remi.sh
./scripts/test-remi.sh
```

Or run suites individually from `librechat/`:

```bash
cd api && npx jest --ci server/services/remi/handoffStore.spec.js server/services/remi/handoffService.spec.js server/services/remi/inferenceService.spec.js server/services/remi/queryHandler.spec.js server/services/remi/deviceAuthService.spec.js server/routes/__tests__/remi.spec.js
cd client && npx jest --ci src/components/Remi/MouseHistoryPanel.spec.tsx src/components/Remi/RemiCompanion.spec.tsx src/components/Remi/mouseSpritePools.spec.ts src/components/Icons/mouseSpriteCatalog.spec.ts src/components/Icons/mouseVariant.spec.ts
cd packages/data-provider && npx jest --ci specs/remi-endpoints.spec.ts
```

Coverage map (see [docs/remi-handoff-test-prd.md](docs/remi-handoff-test-prd.md)):

| Area | Location |
|------|----------|
| SQLite store | `api/server/services/remi/handoffStore.spec.js` |
| Handoff → chat | `api/server/services/remi/handoffService.spec.js` |
| Inference / query / device auth | `api/server/services/remi/*.spec.js` |
| `/api/remi/*` routes | `api/server/routes/__tests__/remi.spec.js` |
| Mouse History UI | `client/src/components/Remi/MouseHistoryPanel.spec.tsx` |
| API URL builders | `packages/data-provider/specs/remi-endpoints.spec.ts` |

First-time setup: from `librechat/`, run `npm run smart-reinstall` (workspace deps, including `better-sqlite3`) before `npm run backend:dev` or tests.

## Mouse layer

See [docs/remi-handoff.md](docs/remi-handoff.md) for the SQLite schema and `/api/remi/*` endpoints MagicPointer uses.
