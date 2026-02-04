# OpenTelemetry Smoke (Local)

Цель: убедиться, что traces отправляются в локальный OTLP collector.

## 1) Поднять collector
```bash
mkdir -p tmp
cat > tmp/otel-collector.yaml <<'EOF'
receivers:
  otlp:
    protocols:
      http:
      grpc:
exporters:
  logging:
    verbosity: detailed
service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [logging]
EOF

docker run -d --rm --name otel-smoke \
  -p 4318:4318 -p 4317:4317 \
  -v "$PWD/tmp/otel-collector.yaml:/etc/otelcol-contrib/config.yaml" \
  otel/opentelemetry-collector-contrib:0.101.0
```

## 2) Запустить сервер с OTel (используя реальный DATABASE_URL)
```bash
cd server
npm run build
set -a
source .env
set +a
PORT=3001 \
OTEL_TRACING_ENABLED=true \
OTEL_EXPORTER_OTLP_ENDPOINT="http://127.0.0.1:4318/v1/traces" \
node dist/src/main.js
```

## 3) Триггернуть запросы
```bash
curl -sS http://127.0.0.1:3001/health
curl -sS http://127.0.0.1:3001/metrics | head -n 5
```

## 4) Проверить traces
```bash
docker logs otel-smoke --tail 100
```
Должны появиться spans с `http.target=/health` и `http.target=/metrics`.

## 5) Cleanup
```bash
docker stop otel-smoke
rm -f tmp/otel-collector.yaml
```
