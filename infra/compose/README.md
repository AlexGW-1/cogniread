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

Verification (local):
- `curl -f http://localhost:3000/health`
- `curl -f http://localhost:8080/health`
- `curl -f http://localhost:8081/health`
- `curl -f http://localhost:6333/healthz`
- `curl -f http://localhost:9000/minio/health/ready`
- `docker compose -f infra/compose/compose.yaml --env-file infra/compose/.env.example exec -T redis redis-cli ping`
- `docker compose -f infra/compose/compose.yaml --env-file infra/compose/.env.example exec -T postgres psql -U cogniread -d cogniread -c "select 1;"`
- `docker compose -f infra/compose/compose.yaml --env-file infra/compose/.env.example exec -T neo4j cypher-shell -u neo4j -p changeme "RETURN 1;"`

AI/worker smoke:
- `curl -s -X POST http://localhost:8080/ingest -H 'content-type: application/json' -d '{"texts":["alpha","beta"]}'`
- `docker compose -f infra/compose/compose.yaml --env-file infra/compose/.env.example logs --since=2m worker | tail -n 50`
