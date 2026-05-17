# REMi parallel execution contracts

## Objective

Ship LibreChat as a REMi-usable fork with handoff APIs, mouse-history UI, and the in-repo macOS overlay (`UI/`, `MagicPointer.app`) sharing the same SQLite handoff contract.

## Non-negotiable Constraints

- Chat persistence remains MongoDB (Docker dev).
- Handoff log is SQLite only; schema in `docs/remi-handoff.md` is frozen for v1.
- REMi feature code under `api/server/routes/remi`, `api/server/services/remi`, `client/src/components/Remi`, and macOS `UI/`.
- Spritesheet source of truth: `librechat/client/public/assets/mouse-spritesheet.png` (sync to `UI/Resources/` via `scripts/sync-mouse-spritesheet.sh`).

## Parallel Workstreams

| ID | Owner | Deliverable |
|----|-------|-------------|
| WS-A | Platform | `config/`, `scripts/`, env sync, Docker overlay, README |
| WS-B | Web REMi UX | `client/src/components/Remi/`, Icons/sprites, branding |
| WS-C | macOS overlay | `UI/`, `MagicPointer.xcodeproj`, SQLite writer, `/api/remi` client |
| WS-D | Release (later) | DMG, embedded Mongo/Meili |

## Data and Interface Contracts

### C1: Handoff SQLite

- **Producer:** MagicPointer (`UI/`) — INSERT/UPDATE rows + PNG files.
- **Consumer:** LibreChat `handoffStore.js`.
- **Path:** `REMI_HANDOFF_DB_PATH` or default `~/Library/Application Support/REMi/interactions.sqlite`.
- **Validation:** Row round-trip + `POST /handoff` creates Mongo conversation.

### C2: REST `/api/remi`

- **Producer:** LibreChat API.
- **Consumer:** LibreChat UI + MagicPointer (JWT).
- **Inputs/outputs:** See `docs/remi-handoff.md`.
- **Errors:** 400 validation, 404 missing interaction, 500 store/attach failures.

### C3: Spritesheet asset

- **Producer:** Web public asset + `scripts/label-mouse-spritesheet.py`.
- **Consumer:** `mouseSpriteCatalog.ts`, `RemiSpriteView.swift`.
- **Sync:** `./scripts/sync-mouse-spritesheet.sh` copies web → `UI/Resources/`.

## Restrictions and Guardrails

- Do not change `interactions` column names without bumping contract doc version.
- MagicPointer must not import LibreChat internals; HTTP + SQLite only.
- Docker API must use local `build api` image when using REMi routes (`better-sqlite3`).
- Only WS-C (or the sync script) should commit changes to `UI/Resources/mouse-spritesheet.png`.

## Integration Plan

1. Platform/env changes land first (`scripts/load-env.sh`, compose).
2. Web and macOS workstreams use C1 + C2; run sprite sync before overlay QA.
3. E2E: overlay → SQLite → Open in Chat → thread in UI.
4. Optional: overlay calls `POST /context` during stream.

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Docker image lacks native module | Local API build in `docker-compose.remi.yaml` |
| JWT from Swift | Document login + bearer token in handoff doc |
| Large screenshots | Resize before POST; 3MB JSON limit |
| Sprite drift web vs macOS | `sync-mouse-spritesheet.sh` in dev workflow |

## Done Criteria

- [ ] `./scripts/start-mac.sh` serves UI with OpenRouter
- [ ] Side panel “Mouse history” lists SQLite rows
- [ ] `POST /handoff` opens new conversation with prompt (+ image when present)
- [ ] `docs/remi-handoff.md` matches implementation
- [ ] Web and macOS spritesheets match after sync
