# Sync Observability (v0.2)

## Метрики (Prometheus)
Endpoint: `GET /metrics`

HTTP:
- `http_requests_total{method,route,status}`
- `http_request_duration_ms_bucket{method,route,status}`
- `http_request_duration_ms_sum{method,route,status}`
- `http_request_duration_ms_count{method,route,status}`

Sync:
- `sync_events_accepted_total`
- `sync_events_duplicate_total`
- `sync_events_rejected_total`
- `sync_events_pulled_total`
- `sync_state_updates_total`
- `sync_ws_connected_total`
- `sync_ws_disconnects_total`

Также доступны default‑метрики процесса Node.js от `prom-client`.

## Логи
Формат: JSON в stdout/stderr. Поля:
- `level`, `timestamp`, `message`
- `context` (если указан)
- `meta` (контекстные поля)

HTTP‑логи пишутся через `LoggingInterceptor`:
- `message: "http_request"` + `method`, `path`, `status`, `durationMs`, `requestId`, `userId`
- `message: "http_error"` + `error` (сообщение ошибки)

## Корреляция
Каждому запросу присваивается `x-request-id`:
- Если клиент прислал `x-request-id`, он сохраняется.
- Иначе генерируется UUID и возвращается в ответе.

## Трейсинг
Трассировка реализована через OpenTelemetry (Node SDK + автоинструментации).

Включение:
- `OTEL_TRACING_ENABLED=true` или `OTEL_EXPORTER_OTLP_ENDPOINT`
- `OTEL_SERVICE_NAME=cogniread-sync` (опционально)
- `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318/v1/traces`
- `OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer <token>` (опционально)
- `OTEL_ENVIRONMENT=production` (опционально)

Логика:
- Если endpoint не задан и `OTEL_TRACING_ENABLED` не `true`, SDK не стартует.
- Автоинструментации: http/express, без fs‑instrumentation.

## Минимальный дашборд
- Latency по `http_request_duration_ms` (p50/p95).
- Ошибки по `http_requests_total{status=~"4..|5.."}`.
- Поток событий (accepted/duplicate/rejected).
- Активность WS (connected/disconnects).
Локальный запуск Prometheus+Grafana: `infra/observability/README.md`.

## Smoke-тест трассировки
Локальный сценарий: `docs/sync_observability_smoke.md`.
