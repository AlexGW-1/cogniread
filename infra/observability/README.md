# Observability (Prometheus + Grafana) — локальный минимальный дашборд

## 1) Запуск
```bash
cd infra/observability
docker compose up -d
```

Prometheus: http://localhost:9090  
Grafana: http://localhost:3002 (login `admin` / `admin`)

## 2) Источник данных в Grafana
Datasource и дашборд создаются автоматически через provisioning.
Если нужно вручную:
- Add data source → Prometheus
- URL: `http://prometheus:9090`

## 3) Минимальный дашборд
Автосозданный дашборд: **Cogniread Sync**.
Панели:
- `rate(http_requests_total[5m])` по `status`
- `histogram_quantile(0.95, sum(rate(http_request_duration_ms_bucket[5m])) by (le))`
- `rate(sync_events_accepted_total[5m])`
- `rate(sync_events_rejected_total[5m])`
- `rate(sync_ws_connected_total[5m])` и `rate(sync_ws_disconnects_total[5m])`

## 4) Target приложения
По умолчанию Prometheus читает `host.docker.internal:3000`.
Если приложение на другом хосте/порту, обнови `infra/observability/prometheus.yml`.

### Проверка target (JSON)
```bash
curl -sS http://localhost:9090/api/v1/targets | \
  grep -E "\"job\":\"cogniread-sync\"|\"health\"|\"lastError\"|\"scrapeUrl\""
```
Ожидаем `health: "up"` и пустой `lastError`.
