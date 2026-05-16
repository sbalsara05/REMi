# REMi

OpenRouter-powered chat on your Mac, built on [LibreChat](https://github.com/danny-avila/LibreChat).

## Prerequisites

- [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/) (Apple Silicon or Intel)
- An [OpenRouter API key](https://openrouter.ai/keys)

## Quick start

1. **Create local env at the repo root**

```bash
cp env.local.example env.local
# Edit env.local and set OPENROUTER_KEY=sk-or-v1-...
```

2. **Build API image once** (includes REMi handoff / SQLite support)

```bash
cd librechat
docker compose -f docker-compose.yml -f ../config/docker-compose.remi.yaml --env-file ../env.local build api
cd ..
```

3. **Start REMi**

```bash
chmod +x scripts/start-mac.sh
./scripts/start-mac.sh
```

4. Open **http://localhost:3080**, register a local account, and select **OpenRouter** models.

## Environment layout

| File | Purpose |
|------|---------|
| `env.local.example` | Committed template — copy to `env.local` |
| `env.local` | Your secrets and settings (gitignored) |
| `config/librechat.yaml` | OpenRouter endpoint + REMi UI flags |
| `config/docker-compose.remi.yaml` | Mounts env, config, and handoff SQLite dir into API |
| `docs/remi-handoff.md` | Mouse layer ↔ LibreChat integration contract |

Default models: `openai/gpt-4o-mini`, `anthropic/claude-sonnet-4`, `google/gemini-2.5-flash-preview`. With `fetch: true`, the full OpenRouter catalog loads at runtime.

## REMi fork layout

REMi-specific LibreChat code lives under:

- `librechat/api/server/routes/remi/`
- `librechat/api/server/services/remi/`
- `librechat/client/src/components/Remi/`

To publish as a proper fork: push `librechat/` to `REMi-LibreChat` on GitHub (`remi` branch) and replace the directory with a git submodule.

## Commands

```bash
# Follow API logs
cd librechat && docker compose -f docker-compose.yml -f ../config/docker-compose.remi.yaml --env-file ../env.local logs -f api

# Stop everything
cd librechat && docker compose -f docker-compose.yml -f ../config/docker-compose.remi.yaml --env-file ../env.local down
```

## Development mode (optional)

Docker for databases, native Node for hot reload (REMi routes work without image rebuild):

```bash
./scripts/dev-mac.sh
cd librechat
npm run smart-reinstall   # first time only
npm run backend:dev       # terminal 1
npm run frontend:dev      # terminal 2 → http://localhost:3090
```

`dev-mac.sh` links `librechat/.env` → `../env.local` so LibreChat’s dotenv loader picks up the root file.

## Tests

REMi uses LibreChat’s existing Jest setup. From the repo root:

```bash
chmod +x scripts/test-remi.sh
./scripts/test-remi.sh
```

Or run suites individually from `librechat/`:

```bash
cd api && npx jest --ci server/services/remi/handoffStore.spec.js server/services/remi/handoffService.spec.js server/routes/__tests__/remi.spec.js
cd client && npx jest --ci src/components/Remi/MouseHistoryPanel.spec.tsx
cd packages/data-provider && npx jest --ci specs/remi-endpoints.spec.ts
```

Coverage map (see [docs/remi-handoff-test-prd.md](docs/remi-handoff-test-prd.md)):

| Area | Location |
|------|----------|
| SQLite store | `api/server/services/remi/handoffStore.spec.js` |
| Handoff → chat | `api/server/services/remi/handoffService.spec.js` |
| `/api/remi/*` routes | `api/server/routes/__tests__/remi.spec.js` |
| Mouse History UI | `client/src/components/Remi/MouseHistoryPanel.spec.tsx` |
| API URL builders | `packages/data-provider/specs/remi-endpoints.spec.ts` |

First-time setup: run `npm run smart-reinstall` inside `librechat/` so workspace dependencies (including `better-sqlite3`) are installed.

## Mouse layer

See [docs/remi-handoff.md](docs/remi-handoff.md) for the SQLite schema and `/api/remi/*` endpoints the Swift overlay branch should use.
