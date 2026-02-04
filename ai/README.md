# AI service

Build:

```bash
$ docker build -t cogniread-ai .
```

Run:

```bash
$ docker run --rm -p 8080:8080 \\
  -e REDIS_URL=redis://host.docker.internal:6379/0 \\
  -e AI_WORKER_QUEUE=ai-tasks \\
  -e EMBEDDINGS_DIM=16 \\
  cogniread-ai
```

Health:

```bash
$ curl -f http://localhost:8080/health
```

Endpoints:
- `POST /embed` `{ "text": "..." }`
- `POST /ingest` `{ "texts": ["...", "..."] }`

Required ENV:
- `REDIS_URL`

Optional ENV:
- `AI_WORKER_QUEUE`
- `EMBEDDINGS_DIM`
- `LOG_LEVEL`
