# CogniRead (MVP skeleton)

Monorepo for:
- **app/** — Flutter client
- **backend/api/** — NestJS API
- **backend/ai/** — FastAPI + LangChain service
- **infra/** — docker/dev tooling
- **docs/** — architecture/ADR/diagrams

## Quick start (local dev)

1) Copy env templates:
```bash
cp infra/env/.env.example .env
cp backend/api/.env.example backend/api/.env
cp backend/ai/.env.example backend/ai/.env
```

2) Start services:
```bash
docker compose up --build
```

3) Endpoints:
- API health: http://localhost:8080/health
- API docs:   http://localhost:8080/docs
- AI health:  http://localhost:8090/health
- Postgres:   localhost:5432
- Qdrant:     http://localhost:6333
- Neo4j:      http://localhost:7474 (bolt: 7687)

## Development
See **CONTRIBUTING.md** for branch/commit rules and local commands.
