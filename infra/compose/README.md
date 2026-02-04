# Compose (local/dev/VPS)

This folder is the canonical deployment contract for local/dev/VPS environments.

Entry point:
- `docker compose --env-file .env up -d`

Planned artifacts:
- `compose.yaml` (canonical service graph)
- `.env.example` (full ENV contract with comments)

Notes:
- Keep service names stable (api/ai/worker/postgres/redis/qdrant/neo4j/object-storage).
- Only reverse proxy should expose ports publicly.
