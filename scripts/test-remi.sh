#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/librechat"

echo "==> REMi API tests (store, service, routes)"
(cd api && npx jest --ci \
  server/services/remi/handoffStore.spec.js \
  server/services/remi/handoffService.spec.js \
  server/services/remi/inferenceService.spec.js \
  server/services/remi/queryHandler.spec.js \
  server/services/remi/deviceAuthService.spec.js \
  server/routes/__tests__/remi.spec.js)

echo "==> REMi client tests"
(cd client && npx jest --ci src/components/Remi/MouseHistoryPanel.spec.tsx)

echo "==> REMi data-provider endpoint tests"
(cd packages/data-provider && npx jest --ci specs/remi-endpoints.spec.ts)

echo "All REMi tests passed."
