# Sync Observability (Draft v0.1)

## Метрики (минимум)
- `sync_events_uploaded_total`
- `sync_events_downloaded_total`
- `sync_events_rejected_total`
- `sync_request_latency_ms` (p50/p95)
- `sync_ws_connected_total`
- `sync_ws_disconnects_total`

## Логи
- `sync.upload` — batch size, cursor, deviceId
- `sync.pull` — cursor, limit, events count
- `sync.ack` — accepted/rejected counts, причины
- `sync.ws` — connect/disconnect, reason

## Трейсинг
- `sync.upload` span (REST)
- `sync.pull` span (REST)
- `sync.ws` span (handshake)

## Дашборд (минимум)
- Граф latency + rate ошибок
- Количество событий в минуту
- Количество активных WS‑соединений
