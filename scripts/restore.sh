#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/infra/compose/compose.yaml}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/infra/compose/.env}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-compose}"
BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"
BACKUP_NAME="${1:-}"

if [[ -z "$BACKUP_NAME" ]]; then
  echo "Usage: $0 <backup-folder>"
  echo "Example: $0 20260204-210000"
  exit 1
fi

SRC_DIR="$BACKUP_DIR/$BACKUP_NAME"
if [[ ! -d "$SRC_DIR" ]]; then
  echo "Backup folder not found: $SRC_DIR"
  exit 1
fi

echo "Using compose file: $COMPOSE_FILE"
echo "Using env file: $ENV_FILE"
echo "Project name: $PROJECT_NAME"

echo "Stopping stack..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down

echo "Restoring volumes..."
QDRANT_VOL="${PROJECT_NAME}_qdrant-data"
MINIO_VOL="${PROJECT_NAME}_minio-data"

if [[ -f "$SRC_DIR/qdrant-data.tar.gz" ]]; then
  docker run --rm -v "$QDRANT_VOL":/data -v "$SRC_DIR":/backup alpine \
    sh -c "rm -rf /data/* && tar -xzf /backup/qdrant-data.tar.gz -C /data"
fi

if [[ -f "$SRC_DIR/minio-data.tar.gz" ]]; then
  docker run --rm -v "$MINIO_VOL":/data -v "$SRC_DIR":/backup alpine \
    sh -c "rm -rf /data/* && tar -xzf /backup/minio-data.tar.gz -C /data"
fi

# Start postgres/neo4j containers for restore operations

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d postgres neo4j

POSTGRES_USER="${POSTGRES_USER:-cogniread}"
POSTGRES_DB="${POSTGRES_DB:-cogniread}"
POSTGRES_CONTAINER="${PROJECT_NAME}-postgres-1"
NEO4J_CONTAINER="${PROJECT_NAME}-neo4j-1"

# Restore Postgres
if [[ -f "$SRC_DIR/postgres.dump" ]]; then
  echo "Restoring Postgres from $SRC_DIR/postgres.dump"
  cat "$SRC_DIR/postgres.dump" | docker exec -i -e PGPASSWORD="${POSTGRES_PASSWORD:-password}" \
    "$POSTGRES_CONTAINER" pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists
fi

# Restore Neo4j (offline)
if [[ -f "$SRC_DIR/neo4j.dump" ]]; then
  echo "Restoring Neo4j from $SRC_DIR/neo4j.dump"
  docker stop "$NEO4J_CONTAINER" >/dev/null
  docker run --rm \
    --volumes-from "$NEO4J_CONTAINER" \
    -v "$SRC_DIR":/backup \
    neo4j:5.23 \
    neo4j-admin database load neo4j --from-path=/backup --overwrite-destination=true
  docker start "$NEO4J_CONTAINER" >/dev/null
fi

echo "Starting full stack..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d

echo "Restore complete."
