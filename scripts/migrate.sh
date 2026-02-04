#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/infra/compose/compose.yaml}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/infra/compose/.env}"

APP_SERVICE="${APP_SERVICE:-api}"

if ! docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps >/dev/null 2>&1; then
  echo "Compose stack is not available. Start it first."
  exit 1
fi

echo "Running migrations via $APP_SERVICE container..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec -T "$APP_SERVICE" \
  npx prisma migrate deploy

echo "Migrations complete."
