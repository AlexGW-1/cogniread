# Smoke Tests (GCP)

## Command
```
$ ./scripts/smoke.sh
```

## Manual quick check
```
$ SERVICE_URL="$(gcloud run services describe cogniread-sync --region=europe-west4 --format='value(status.url)')"
$ curl -i "${SERVICE_URL}/health"
```
