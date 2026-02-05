# GCP Deploy (Cloud Run + Cloud SQL) — временный путь

Проект: `cogniread-485918`  
Регион: `europe-west4`  
Cloud Run: публичный доступ

Ниже — полный воспроизводимый путь деплоя.

---
## 0) Предусловия
- Установлен `gcloud` и выполнен `gcloud auth login`.
- Установлен `docker`.
- В репозитории есть `server/Dockerfile` и `/health` (уже добавлено).

Установить проект и регион:
```bash
gcloud config set project cogniread-485918
gcloud config set run/region europe-west4
```

Включить API:
```bash
gcloud services enable run.googleapis.com sqladmin.googleapis.com artifactregistry.googleapis.com
```

---
## 1) Cloud SQL (PostgreSQL)
Создать инстанс:
```bash
gcloud sql instances create cogniread-sql \
  --database-version=POSTGRES_16 \
  --region=europe-west4 \
  --cpu=2 \
  --memory=7680MB
```

Создать БД и пользователя:
```bash
gcloud sql databases create cogniread --instance=cogniread-sql
gcloud sql users create cogniread_app --instance=cogniread-sql --password=CHANGE_ME
```

Получить `INSTANCE_CONNECTION_NAME`:
```bash
gcloud sql instances describe cogniread-sql --format="value(connectionName)"
```

---
## 2) Artifact Registry
Создать репозиторий:
```bash
gcloud artifacts repositories create cogniread \
  --repository-format=docker \
  --location=europe-west4
```

Настроить docker:
```bash
gcloud auth configure-docker europe-west4-docker.pkg.dev
```

---
## 3) Build & Push образа
```bash
cd /Users/estron/Desktop/WorkSpace/cogniread/server
docker build -t europe-west4-docker.pkg.dev/cogniread-485918/cogniread/sync:latest .
docker push europe-west4-docker.pkg.dev/cogniread-485918/cogniread/sync:latest
```

---
## 4) ENV для Cloud Run
Скопируй пример:
```bash
cp infra/gcp/prod.env.example infra/gcp/prod.env
```

Заполни `DATABASE_URL` (через Unix socket):
```
DATABASE_URL=postgresql://cogniread_app:CHANGE_ME@localhost/cogniread?host=/cloudsql/PROJECT:REGION:INSTANCE
```

---
## 5) Деплой Cloud Run
Рекомендуемый подход — деплоить **конкретный тег**, а не `latest`.

Получить тег (SHA коммита):
```bash
git rev-parse --short HEAD
```

```bash
gcloud run deploy cogniread-sync \
  --image=europe-west4-docker.pkg.dev/cogniread-485918/cogniread/sync:TAG \
  --region=europe-west4 \
  --allow-unauthenticated \
  --add-cloudsql-instances=PROJECT:REGION:INSTANCE \
  --env-vars-file=infra/gcp/prod.env
```

Проверить, какой образ реально запущен:
```bash
gcloud run services describe cogniread-sync \
  --region=europe-west4 \
  --format="value(status.traffic[0].revisionName,spec.template.spec.containers[0].image)"
```

---
## 6) Миграции
Рекомендуемый путь: **Cloud Run job** (не зависит от локальной сети/прокси).

Создать job для миграций:
```bash
gcloud run jobs create cogniread-sync-migrate \
  --image=europe-west4-docker.pkg.dev/cogniread-485918/cogniread/sync:TAG \
  --region=europe-west4 \
  --add-cloudsql-instances=PROJECT:REGION:INSTANCE \
  --env-vars-file=infra/gcp/prod.env \
  --command=npx \
  --args=prisma,migrate,deploy
```

Запустить job:
```bash
gcloud run jobs execute cogniread-sync-migrate --region=europe-west4
```

При необходимости удалить job:
```bash
gcloud run jobs delete cogniread-sync-migrate --region=europe-west4
```

---
## 7) Smoke-check
- `GET /health` → `200` `{ "status": "ok" }`
- `POST /sync/events` → `accepted`
- `GET /sync/events` → `200`
- WS `/sync/ws` → события

Быстрая проверка:
```bash
SERVICE_URL="$(gcloud run services describe cogniread-sync --region=europe-west4 --format='value(status.url)')"
curl -i "${SERVICE_URL}/health"
```

---
## 8) Tracing (OpenTelemetry)

### 8.1) Deploy OTEL collector (Cloud Run)
Минимальный collector, который пишет в Cloud Trace и stdout.

Создать сервисный аккаунт и права:
```bash
gcloud iam service-accounts create cogniread-otel \
  --display-name "cogniread-otel"

gcloud projects add-iam-policy-binding cogniread-485918 \
  --member "serviceAccount:cogniread-otel@cogniread-485918.iam.gserviceaccount.com" \
  --role "roles/cloudtrace.agent"
```

Загрузить конфиг:
```bash
gcloud secrets create otel-collector-config --data-file=infra/gcp/otel-collector.yaml
gcloud secrets add-iam-policy-binding otel-collector-config \
  --member "serviceAccount:cogniread-otel@cogniread-485918.iam.gserviceaccount.com" \
  --role "roles/secretmanager.secretAccessor"
```

Деплой collector:
```bash
gcloud run deploy cogniread-otel \
  --image=otel/opentelemetry-collector-contrib:0.101.0 \
  --region=europe-west4 \
  --allow-unauthenticated \
  --service-account=cogniread-otel@cogniread-485918.iam.gserviceaccount.com \
  --args="--config=/etc/otelcol-contrib/config.yaml" \
  --set-secrets="/etc/otelcol-contrib/config.yaml=otel-collector-config:latest"
```

URL collector:
```bash
gcloud run services describe cogniread-otel \
  --region=europe-west4 \
  --format="value(status.url)"
```

### 8.2) Подключить tracing в Cloud Run service
Добавить env vars:
```
OTEL_TRACING_ENABLED=true
OTEL_EXPORTER_OTLP_ENDPOINT=https://<collector-url>/v1/traces
OTEL_SERVICE_NAME=cogniread-sync
OTEL_ENVIRONMENT=production
```

### 8.3) Проверка
- `curl https://<service-url>/health`
- В Cloud Trace должны появиться spans с `http.target=/health`.

---
## 9) Переносимость на VPS
Соблюдаем контракт:
- `DATABASE_URL`, `HOST`, `PORT`, `NODE_ENV` — единственные обязательные ENV.
- Никаких GCP‑специфичных SDK/кодов в приложении.
