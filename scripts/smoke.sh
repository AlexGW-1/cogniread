#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/infra/compose/compose.yaml}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/infra/compose/.env}"

API_PORT="${API_PORT:-3000}"
AI_PORT="${AI_PORT:-8080}"
WORKER_PORT="${WORKER_PORT:-8081}"
QDRANT_PORT="${QDRANT_PORT:-6333}"
MINIO_PORT="${MINIO_PORT:-9000}"

check_url() {
  local url="$1"
  local name="$2"
  echo "Checking $name: $url"
  curl -fsS "$url" >/dev/null
}

echo "Checking container health..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

echo "Checking endpoints..."
check_url "http://localhost:${API_PORT}/health" "api"
check_url "http://localhost:${AI_PORT}/health" "ai"
check_url "http://localhost:${WORKER_PORT}/health" "worker"
check_url "http://localhost:${QDRANT_PORT}/healthz" "qdrant"
check_url "http://localhost:${MINIO_PORT}/minio/health/ready" "minio"

echo "Smoke PASS"
