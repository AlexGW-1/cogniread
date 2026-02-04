# Backup (GCP)

Run from repo root with Docker/Compose access to the stack.

## Prereqs
- Stack is running
- `infra/compose/.env` is configured

## Command
```
$ BACKUP_DIR=./backups ./scripts/backup.sh
```

## Output
- `backups/<timestamp>/postgres.dump`
- `backups/<timestamp>/neo4j.dump`
- `backups/<timestamp>/qdrant-data.tar.gz`
- `backups/<timestamp>/minio-data.tar.gz`
