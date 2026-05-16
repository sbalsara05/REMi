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

2. **Start REMi**

```bash
chmod +x scripts/start-mac.sh
./scripts/start-mac.sh
```

3. Open **http://localhost:3080**, register a local account, and select **OpenRouter** models.

## Environment layout

| File | Purpose |
|------|---------|
| `env.local.example` | Committed template — copy to `env.local` |
| `env.local` | Your secrets and settings (gitignored) |
| `config/librechat.yaml` | OpenRouter endpoint config |
| `librechat/docker-compose.override.yaml` | Mounts `../env.local` into containers |

Default models: `openai/gpt-4o-mini`, `anthropic/claude-sonnet-4`, `google/gemini-2.5-flash-preview`. With `fetch: true`, the full OpenRouter catalog loads at runtime.

## Commands

```bash
# Follow API logs
cd librechat && docker compose --env-file ../env.local logs -f api

# Stop everything
cd librechat && docker compose --env-file ../env.local down
```

## Development mode (optional)

Docker for databases, native Node for hot reload:

```bash
./scripts/dev-mac.sh
cd librechat
npm run smart-reinstall   # first time only
npm run backend:dev       # terminal 1
npm run frontend:dev      # terminal 2 → http://localhost:3090
```

`dev-mac.sh` links `librechat/.env` → `../env.local` so LibreChat’s dotenv loader picks up the root file.
