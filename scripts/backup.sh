#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/infra/compose/compose.yaml}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/infra/compose/.env}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-compose}"
BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$BACKUP_DIR/$TIMESTAMP"

mkdir -p "$OUT_DIR"

echo "Using compose file: $COMPOSE_FILE"
echo "Using env file: $ENV_FILE"
echo "Project name: $PROJECT_NAME"
echo "Backup dir: $OUT_DIR"

POSTGRES_USER="${POSTGRES_USER:-cogniread}"
POSTGRES_DB="${POSTGRES_DB:-cogniread}"

POSTGRES_CONTAINER="${PROJECT_NAME}-postgres-1"
NEO4J_CONTAINER="${PROJECT_NAME}-neo4j-1"
QDRANT_CONTAINER="${PROJECT_NAME}-qdrant-1"
MINIO_CONTAINER="${PROJECT_NAME}-object-storage-1"

# Postgres logical dump
PG_DUMP_FILE="$OUT_DIR/postgres.dump"
echo "Backing up Postgres to $PG_DUMP_FILE"
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD:-password}" "$POSTGRES_CONTAINER" \
  pg_dump -Fc -U "$POSTGRES_USER" -d "$POSTGRES_DB" > "$PG_DUMP_FILE"

# Neo4j dump (requires offline)
NEO4J_DUMP_NAME="neo4j.dump"
echo "Stopping Neo4j for dump..."
docker stop "$NEO4J_CONTAINER" >/dev/null

echo "Backing up Neo4j to $OUT_DIR/$NEO4J_DUMP_NAME"
docker run --rm \
  --volumes-from "$NEO4J_CONTAINER" \
  -v "$OUT_DIR":/backup \
  neo4j:5.23 \
  neo4j-admin database dump neo4j --to-path=/backup --overwrite-destination=true

echo "Starting Neo4j..."
docker start "$NEO4J_CONTAINER" >/dev/null

# Qdrant data volume snapshot (tar)
QDRANT_VOL="${PROJECT_NAME}_qdrant-data"
echo "Backing up Qdrant volume $QDRANT_VOL"
docker run --rm -v "$QDRANT_VOL":/data -v "$OUT_DIR":/backup alpine \
  sh -c "tar -czf /backup/qdrant-data.tar.gz -C /data ."

# MinIO data volume snapshot (tar)
MINIO_VOL="${PROJECT_NAME}_minio-data"
echo "Backing up MinIO volume $MINIO_VOL"
docker run --rm -v "$MINIO_VOL":/data -v "$OUT_DIR":/backup alpine \
  sh -c "tar -czf /backup/minio-data.tar.gz -C /data ."

echo "Backup complete: $OUT_DIR"
