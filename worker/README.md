# Worker service

Build:

```bash
$ docker build -t cogniread-worker .
```

Run:

```bash
$ docker run --rm -p 8081:8081 \\
  -e REDIS_URL=redis://host.docker.internal:6379/0 \\
  -e AI_WORKER_QUEUE=ai-tasks \\
  -e LOG_LEVEL=info \\
  cogniread-worker
```

Health:

```bash
$ curl -f http://localhost:8081/health
```

Required ENV:
- `REDIS_URL`

Optional ENV:
- `AI_WORKER_QUEUE`
- `LOG_LEVEL`
