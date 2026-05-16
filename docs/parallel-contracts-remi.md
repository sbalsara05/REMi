# REMi parallel execution contracts

## Objective

Ship LibreChat as a REMi-usable fork with handoff APIs and mouse-history UI while the Swift mouse branch writes to the same SQLite contract.

## Non-negotiable Constraints

- Mouse capture/inference stays on the other branch.
- Chat persistence remains MongoDB (Docker dev).
- Handoff log is SQLite only; schema in `docs/remi-handoff.md` is frozen for v1.
- All REMi code under `api/server/routes/remi`, `api/server/services/remi`, `client/src/components/Remi`.

## Parallel Workstreams

| ID | Owner | Deliverable |
|----|-------|-------------|
| WS-A | Chat (this branch) | `/api/remi/*`, handoff store, Docker overlay, README |
| WS-B | Mouse branch | SQLite writer, OpenRouter stream, overlay UI |
| WS-C | Release (later) | DMG, embedded Mongo/Meili |

## Data and Interface Contracts

### C1: Handoff SQLite

- **Producer:** Mouse branch (INSERT/UPDATE rows + PNG files).
- **Consumer:** LibreChat `handoffStore.js`.
- **Path:** `REMI_HANDOFF_DB_PATH` or default `~/Library/Application Support/REMi/interactions.sqlite`.
- **Validation:** Row round-trip + `POST /handoff` creates Mongo conversation.

### C2: REST `/api/remi`

- **Producer:** LibreChat API.
- **Consumer:** LibreChat UI + mouse branch (JWT).
- **Inputs/outputs:** See `docs/remi-handoff.md`.
- **Errors:** 400 validation, 404 missing interaction, 500 store/attach failures.

## Restrictions and Guardrails

- Do not change `interactions` column names without bumping contract doc version.
- Mouse branch must not import LibreChat internals; HTTP + SQLite only.
- Docker API must use local `build api` image when using REMi routes (`better-sqlite3`).

## Integration Plan

1. Merge WS-A (this branch).
2. Mouse branch implements C1 writer against same path.
3. E2E: overlay → SQLite → Open in Chat → thread in UI.
4. Optional: mouse calls `POST /context` during stream.

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Docker image lacks native module | Local API build in `docker-compose.remi.yaml` |
| JWT from Swift | Document login + bearer token in handoff doc |
| Large screenshots | Resize before POST; 3MB JSON limit |

## Done Criteria

- [ ] `./scripts/start-mac.sh` serves UI with OpenRouter
- [ ] Side panel “Mouse history” lists SQLite rows
- [ ] `POST /handoff` opens new conversation with prompt (+ image when present)
- [ ] `docs/remi-handoff.md` matches implementation
