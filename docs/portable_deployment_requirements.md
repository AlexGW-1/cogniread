# Требования к серверной инфраструктуре и переносимому деплою (GCP → VPS)

> Документ фиксирует единые требования к развёртыванию серверной части проекта в Google Cloud так, чтобы дальнейший перенос на любой VPS/другой провайдер был максимально простым и предсказуемым.

---

## 1) Цели

### 1.1 Основная цель
Обеспечить переносимость серверной части между:
- Google Cloud (MVP/первый прод)
- Любой VPS/другой облачный провайдер

…с минимальными изменениями: в идеале перенос = **смена конфигурации + миграция данных**, без переписывания кода и без переделки пайплайнов.

### 1.2 Нецели (на MVP)
- Автоскейлинг на уровне нескольких регионов
- Полный SRE-стек уровня enterprise
- Сложная multi-tenant изоляция на уровне инфраструктуры (достаточно логической)

---

## 2) Область применения и компоненты

### 2.1 Сервисы
- **API** (`api`) — NestJS: auth, библиотека, заметки, прогресс чтения, синхронизация, доступ к файлам, маршрутизация AI.
- **AI** (`ai`) — FastAPI + LangChain: чанкование, эмбеддинги, retrieval, генерация summary/объяснений, запись результатов в граф/БД.
- **Worker** (`worker`) — фоновые задачи (рекомендуется): эмбеддинги, индексирование, построение связей и тяжёлые операции.

### 2.2 Хранилища и базы
- **PostgreSQL** (`postgres`) — основная реляционная БД.
- **Redis** (`redis`) — очередь/кэш/локи (BullMQ или эквивалент).
- **Qdrant** (`qdrant`) — векторная БД.
- **Neo4j** (`neo4j`) — граф знаний.
- **Object Storage** (`object-storage`) — **S3-compatible** (рекомендуется MinIO или внешний S3-провайдер).  
  Допускается GCS, но только через адаптер.

### 2.3 Входной трафик
- Reverse proxy / TLS termination (Nginx/Traefik/Caddy)
- Домены/сертификаты — без привязки к конкретному провайдеру

---

## 3) Базовые принципы переносимости

1. **Docker-first**: всё запускается контейнерами.
2. **Compose как контракт запуска**: `compose.yaml` — “источник правды” для local/dev/VPS и как эталон для GCP.
3. **Конфиг только через ENV**: приложение не требует provider-специфичных настроек.
4. **Хранилище файлов через абстракцию**: переключение провайдера хранения **без изменения кода**.
5. **Stateful по стандартным протоколам**: Postgres/Redis/Qdrant/Neo4j доступны по обычным URL/портам.
6. **Операционность = часть продукта**: backup/restore/migrations/smoke-tests обязательны.
7. **Никаких “скрытых зависимостей”**: деплой не должен зависеть от ручных кликов в консоли.

---

## 4) Целевая логика развёртывания

### 4.1 Канонический запуск (local/dev/VPS)
- Полный стек поднимается командой:
  - `docker compose --env-file .env up -d`
- Для каждого сервиса:
  - фиксированное имя
  - healthcheck
  - неизменяемые порты внутри сети compose
  - корректное завершение (SIGTERM) и graceful shutdown

### 4.2 Логика GCP для минимизации боли
Разрешены 2 режима, **базовым должен быть один**:

#### Режим A — “GCP как VPS” (максимальная переносимость)
- 1–2 Compute Engine VM
- На VM: Docker + Docker Compose
- Reverse proxy на VM
- Все базы/хранилища также на VM (или вынесены на managed аналоги, но без изменения интерфейсов приложений)

Плюсы: перенос на VPS почти 1:1.  
Минусы: меньше managed удобств.

#### Режим B — “Stateless на Cloud Run, stateful на VM” (компромисс)
- Cloud Run: `api`, `ai`, `worker`
- Compute Engine VM: `postgres`, `redis`, `qdrant`, `neo4j`, `minio`
- Связь Cloud Run → VM: приватная сеть (VPC connector), **без публичного доступа к stateful**

Плюсы: удобство для stateless; можно масштабировать по нагрузке.  
Минусы: появляется слой Cloud Run, но перенос всё ещё возможен без переписывания кода.

---
## 8) Текущий статус

На 2026-02-04 выбран режим B в упрощённой форме:
- Cloud Run: `api` (Sync Gateway backend)
- Cloud SQL: managed Postgres (временно)

Документация развертывания: `infra/gcp/README.md`.

---

## 5) Требования к репозиторию

### 5.1 Структура
```text
/infra
  /compose
    compose.yaml
    .env.example
    README.md
  /gcp
    README.md
    runbooks/
      backup.md
      restore.md
      migration.md
      smoke-tests.md
  /vps
    README.md
    runbooks/
      backup.md
      restore.md
      hardening.md
/.github/workflows
  build-and-push.yml
  deploy-gcp.yml
  deploy-vps.yml (опционально)
/scripts
  backup.sh
  restore.sh
  smoke.sh
  migrate.sh
```

### 5.2 Обязательные артефакты
- `infra/compose/compose.yaml` — канонический контракт
- `.env.example` — полный список ENV + комментарии
- Runbooks + scripts: backup/restore/migrate/smoke

---

## 6) Требования к Docker Compose

### 6.1 Обязательные сервисы
- `api`, `ai`, `postgres`, `redis`, `qdrant`, `neo4j`, `object-storage` (MinIO)
- `worker` — обязательно, если есть тяжёлые фоновые операции

### 6.2 Volumes и данные
- Postgres: отдельный volume
- Neo4j: отдельные volumes для data/logs
- Qdrant: отдельный volume
- MinIO: отдельный volume

### 6.3 Healthchecks
- `api`: `GET /health` → 200
- `ai`: `GET /health` → 200
- `postgres`: readiness через `pg_isready`
- `redis`: ping
- `qdrant`: health endpoint
- `neo4j`: bolt/http readiness
- `minio`: health endpoint

### 6.4 Сети
- Внутренний network для сервисов
- Наружу публикуются только:
  - reverse proxy (80/443)
  - (опционально) админ-панель/метрики — строго по whitelist/VPN

---

## 7) Конфигурация и секреты

### 7.1 Общее правило
- Приложения читают конфиг **только из ENV**
- Секреты **никогда** не коммитятся
- В GCP секреты могут храниться в Secret Manager, на VPS — в Vault/`.env`/другом менеджере, но интерфейс одинаковый (ENV)

### 7.2 Минимальный набор ENV (контракт)

#### API (`api`)
- `PORT=8080`
- `NODE_ENV=production`
- `DATABASE_URL=postgres://user:pass@postgres:5432/db`
- `REDIS_URL=redis://redis:6379`
- `AI_SERVICE_URL=http://ai:8080`
- `QDRANT_URL=http://qdrant:6333`
- `NEO4J_URI=bolt://neo4j:7687`
- `NEO4J_USER=neo4j`
- `NEO4J_PASSWORD=...`
- `JWT_SECRET=...`
- `STORAGE_PROVIDER=s3|gcs` (по умолчанию `s3`)
- `S3_ENDPOINT=http://object-storage:9000`
- `S3_ACCESS_KEY=...`
- `S3_SECRET_KEY=...`
- `S3_BUCKET=...`
- `S3_REGION=...` (если требуется)
- `SENTRY_DSN=...` (опционально)

#### AI (`ai`)
- `PORT=8080`
- `QDRANT_URL=...`
- `NEO4J_URI=...`
- `NEO4J_USER=...`
- `NEO4J_PASSWORD=...`
- `STORAGE_PROVIDER=...`
- `S3_*` (если AI читает/пишет артефакты)
- `GCS_BUCKET=...` (если используется GCS)
- `GCS_PROJECT_ID=...` (опционально)
- `GCS_KEYFILE=...` (опционально)
- `REDIS_URL=...` (если AI/worker используют очередь)
- `AI_WORKER_QUEUE=ai-tasks` (опционально)
- `EMBEDDINGS_DIM=16` (опционально)
- `SENTRY_DSN=...` (опционально)

#### Worker (`worker`) — если есть
- `DATABASE_URL=...`
- `REDIS_URL=...`
- `AI_WORKER_QUEUE=ai-tasks` (опционально)
- `LOG_LEVEL=info` (опционально)
- `QDRANT_URL=...`
- `NEO4J_URI=...`
- `STORAGE_PROVIDER=...`
- `S3_*` (при необходимости)
- `GCS_BUCKET=...` (если используется GCS)
- `GCS_PROJECT_ID=...` (опционально)
- `GCS_KEYFILE=...` (опционально)

---

## 8) Требования к файловому хранилищу (снижение боли миграции)

### 8.1 Обязательная абстракция
Должен быть интерфейс `FileStorage` (или эквивалент) минимум с:
- `putObject(path, stream|bytes, contentType, metadata?)`
- `getObject(path)`
- `deleteObject(path)`
- `generatePresignedUploadUrl(path, ttl, contentType?)`
- `generatePresignedDownloadUrl(path, ttl)`

### 8.2 Приоритетный провайдер
- По умолчанию **S3-compatible** (MinIO/внешний S3).
- GCS допускается только как подключаемый адаптер, без “протекания” SDK наружу.

### 8.3 Acceptance
- Переход с GCS ↔ S3/MinIO (или S3-провайдера) должен выполняться **только изменением ENV**, без изменений кода и схем БД.

---

## 9) Требования к данным и миграциям

### 9.1 Postgres
- Миграции управляются штатным миграционным инструментом (выбранным в проекте)
- Есть команда/скрипт:
  - `./scripts/migrate.sh`
- При старте `api` не должен “молчаливо” ломаться при отсутствии миграций — нужен понятный фейл и лог.

### 9.2 Qdrant / Neo4j
- Инициализация коллекций/индексов/констрейнтов должна быть:
  - либо декларативной (скрипт/миграции),
  - либо идемпотентной при старте.

---

## 10) Бэкапы, восстановление и проверка (обязательное)

### 10.1 Скрипты
- `./scripts/backup.sh`:
  - Postgres dump (`pg_dump`)
  - снапшот Qdrant (или бэкап volume по документированному сценарию)
  - бэкап Neo4j (volume snapshot или `neo4j-admin`-процедура)
  - манифест по объектному хранилищу (если нужно для сверки)
- `./scripts/restore.sh <backup_dir>`:
  - восстановление всех компонент
- `./scripts/smoke.sh`:
  - healthchecks
  - запись/чтение тестовой сущности в Postgres
  - тест загрузки файла (presigned upload) + скачивание
  - простой AI-запрос (минимальный эндпойнт) и проверка ответа

### 10.2 Acceptance
- На staging окружении должно быть подтверждено:
  - backup → restore → smoke = PASS

---

## 11) Наблюдаемость и диагностика

### 11.1 Логи
- Все сервисы пишут логи в stdout/stderr (контейнерный стандарт)
- Уровни логов задаются ENV (например `LOG_LEVEL`)

### 11.2 Ошибки
- Sentry подключается одинаково на всех платформах (через ENV)

### 11.3 Метрики (можно после MVP)
- Допускается добавить Prometheus/Grafana/Loki, но без vendor lock-in.

---

## 12) Security требования (MVP без критических дыр)

1. Stateful сервисы **не доступны из интернета**:
   - Postgres/Redis/Qdrant/Neo4j/MinIO — только внутренняя сеть.
2. Публичный доступ только через reverse proxy к `api` (и при необходимости к `ai`, но лучше только внутренний).
3. TLS обязателен (Let’s Encrypt на proxy).
4. Админ-порты (если есть) — только через VPN/SSH tunnel/whitelist.
5. Секреты — только через секрет-хранилище/ENV, не в коде.

---

## 13) CI/CD требования

### 13.1 Build
- GitHub Actions собирает Docker images: `api`, `ai`, `worker` (если есть)
- Теги: минимум `:sha`, `:main`, `:release`

### 13.2 Deploy на GCP
- Режим A: деплой = обновление образов на VM + `docker compose pull && docker compose up -d`
- Режим B: деплой stateless сервисов + stateful остаётся на VM

### 13.3 Deploy на VPS
- Идентично режиму A: pull образов + `docker compose up -d`

---

## 14) План миграции GCP → VPS (runbook обязателен)

1. Подготовить VPS (Docker, firewall, reverse proxy, volumes)
2. Freeze writes (если нужно консистентное окно)
3. Выполнить `backup.sh` на текущей площадке
4. Перенести backup-артефакты на VPS
5. Поднять сервисы на VPS (compose)
6. `restore.sh`
7. `smoke.sh`
8. Переключить DNS
9. Мониторинг ошибок/latency/очередей первые часы/сутки

---

## 15) Требования к VPS (ориентиры для MVP)

> Точные цифры зависят от объёма данных/индекса/частоты AI-операций. Ниже профили для планирования.

### 15.1 Профиль S (минимальный, только для очень малого MVP)
- 2–4 vCPU
- 8–16 GB RAM (8 GB часто будет впритык из-за Neo4j/Qdrant)
- 100–200 GB SSD/NVMe
- Подходит для: небольшой базы пользователей, редкая индексация, малый граф/векторы

### 15.2 Профиль M (рекомендуемый старт)
- 4 vCPU
- 16 GB RAM
- 200–500 GB NVMe
- Подходит для: активной разработки, регулярной индексации, заметок/книг средней величины

### 15.3 Профиль L (если уже есть нагрузка)
- 8 vCPU
- 32 GB RAM
- 500 GB+ NVMe
- Желательно: разделение app/ai и databases по разным узлам

### 15.4 Обязательное независимо от профиля
- регулярные бэкапы + проверка восстановления
- мониторинг места на диске и RAM (не допускать swap-шторм)

---

## 16) Definition of Done (готово, когда)

- `compose.yaml` поднимает весь стек локально/на VPS без правок кода.
- На GCP развёртывание по выбранному режиму (A или B) описано в `infra/gcp/README.md` и воспроизводимо.
- Есть `backup/restore/migrate/smoke` скрипты и они проходят на staging.
- FileStorage абстракция есть; смена storage provider происходит конфигом.
- `api` и `ai` имеют `/health` и документированную проверку.
- Stateful сервисы не выставлены наружу.

---

## 17) Work Items для CODEX (пакеты задач)

### INFRA-1: Canonical Compose
- [ ] `infra/compose/compose.yaml` для api/ai/worker/postgres/redis/qdrant/neo4j/minio
- [ ] volumes + networks + healthchecks
- [ ] `.env.example` с комментариями

### INFRA-2: Storage Abstraction
- [ ] интерфейс FileStorage
- [ ] S3-adapter (default)
- [ ] (опционально) GCS-adapter
- [ ] presigned URLs (upload/download)

### INFRA-3: Backup/Restore/Smoke
- [ ] `scripts/backup.sh`
- [ ] `scripts/restore.sh`
- [ ] `scripts/smoke.sh`
- [ ] `infra/*/runbooks/*.md`

### INFRA-4: GCP Deployment Mode
- [ ] выбрать базовый режим A или B
- [ ] `infra/gcp/README.md` (пошагово)
- [ ] (если B) приватная сеть между Cloud Run и VM

### INFRA-5: VPS Runbook
- [ ] `infra/vps/README.md` (docker, firewall, proxy, tls)
- [ ] `hardening.md` чек-лист

### INFRA-6: CI/CD
- [ ] `build-and-push.yml`
- [ ] `deploy-gcp.yml` (под выбранный режим)
- [ ] `deploy-vps.yml` (опционально, через SSH)

---
