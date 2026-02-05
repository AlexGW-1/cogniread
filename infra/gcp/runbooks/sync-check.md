# Sync Check (GCP)

## 1) Быстрый health
```
$ SERVICE_URL="$(gcloud run services describe cogniread-sync --region=europe-west4 --format='value(status.url)')"
$ curl -f "${SERVICE_URL}/health"
```

## 2) Запустить синк на клиенте
Сделайте любое изменение (заметка/хайлайт) и нажмите “Sync now”.

## 3) Проверить логи запросов
```
$ gcloud logging read \
'logName="projects/cogniread-485918/logs/run.googleapis.com%2Frequests" resource.labels.service_name="cogniread-sync"' \
--freshness=10m --limit=50 --format='value(httpRequest.requestMethod,httpRequest.requestUrl,httpRequest.status)'
```

Ожидаемые записи:
- `POST .../sync/events` → `201`
- `POST .../sync/state` → `201`
- `GET  .../sync/events` → `200`
- `GET  .../sync/ws` → `101` (если включён realtime)

## 4) Проверить ошибки сервера
```
$ gcloud logging read \
'resource.type="cloud_run_revision" resource.labels.service_name="cogniread-sync" httpRequest.status>=500' \
--freshness=1h --limit=20 --format='json'
```
