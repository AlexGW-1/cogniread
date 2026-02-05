# План следующих этапов (Draft)

Формат: **1 issue ≈ 1 PR ≈ 1 день**.  
Статусы: `done` / `planned` / `partial`. PR указывается, если известен; иначе `—`.

Шаблон Issue (для GitHub):
```
## Context

## Checklist
- [ ]

## Acceptance Criteria
- [ ]

## Test Plan
- [ ]
```

## Milestone M1 — Глобальные разделы и UX
Цель: сделать удобные глобальные разделы и довести поиск/заметки до “пользовательского качества”.

### M1-1 Global Search v2 (FTS-индекс, диагностика, rebuild)
Issue ID: `M1-1`
Статус: `done` • PR: —  
Scope: см. `docs/search_global_v2.md`.

Acceptance Criteria:
- [x] Полнотекст по книгам/заметкам/выделениям.
- [x] Jump-to-location в Reader.
- [x] Диагностика + rebuild индекса.

Test Plan:
- Поиск по 2–3 книгам, переход в Reader.
- Перестроить индекс, убедиться, что ошибки понятны.

### M1-2 Global Notes/Highlights v1
Issue ID: `M1-2`
Статус: `done` • PR: —  
Scope: см. `docs/notes_screen_v1.md`.

Checklist:
- [x] Глобальный список notes/highlights с поиском и фильтрами.
- [x] Группировка по книгам + лента.
- [x] Free notes (без книги) + синхронизация.
- [x] Массовые действия: экспорт/удаление.

Acceptance Criteria:
- [x] Раздел “Заметки” не placeholder.
- [x] Поиск/фильтры работают; переход в Reader по anchor.

Test Plan:
- Создать 3–5 заметок/выделений в разных книгах.
- Проверить поиск и фильтры, открыть пару элементов в Reader.

### M1-3 Закладки: несколько на книгу + управление
Issue ID: `M1-3`
Статус: `done` • PR: —

Checklist:
- [x] Хранить список закладок, а не одну.
- [x] UI списка + удаление/переименование.
- [x] Навигация в Reader по anchor.

Acceptance Criteria:
- [x] Можно создать 3+ закладок в одной книге.
- [x] Удаление не ломает текущую позицию чтения.

Test Plan:
- Создать/удалить/переименовать закладки, перейти по ним.

### M1-4 Экспорт заметок/выделений (JSON + Markdown)
Issue ID: `M1-4`
Статус: `done` • PR: —

Checklist:
- [x] Экспорт выбранных элементов в zip (`notes.json`, `notes.md`).
- [x] Включить метаданные книги и anchor.

Acceptance Criteria:
- [x] Экспорт создается, структура совпадает с PRD.

Test Plan:
- Экспорт 5 элементов, проверить содержимое файлов.

### M1-5 Обновление тест-плана под новые разделы
Issue ID: `M1-5`
Статус: `done` • PR: —

Checklist:
- [x] Обновить `docs/test_plan_stage1_sync.md` при изменениях синка.
- [x] Добавить тест-план для Notes/Global Search (если нет).

Acceptance Criteria:
- [x] Есть воспроизводимые ручные сценарии.

---
## Milestone M2 — Стабилизация синхронизации
Цель: повысить надежность и прозрачность file-based sync без изменения модели данных.

### M2-1 Статусы синка и понятные ошибки
Issue ID: `M2-1`
Статус: `done` • PR: —

Checklist:
- [x] Ясные состояния: success/error/paused.
- [x] Тексты ошибок без утечек секретов.

Аудит (факт):
- [x] Success/error фиксируются и показываются в UI (`SyncStatusSnapshot`, экран настроек).
- [x] Paused: добавлен явный статус "paused" + сохранение и отображение.
- [x] Маскирование секретов в пользовательских сообщениях.

### M2-2 Retry/backoff и лимиты API
Issue ID: `M2-2`
Статус: `done` • PR: —

Checklist:
- [x] Экспоненциальный backoff на сетевые ошибки.
- [x] Раздельные таймауты request/transfer.

Аудит (факт):
- [x] Экспоненциальный backoff + retry реализованы (`ResilientSyncAdapter`).
- [x] Раздельные таймауты есть для WebDAV (request/transfer).
- [x] Лимиты API: 429 учитывает Retry-After, добавлены per-provider лимиты.

### M2-3 Диагностика и метрики
Issue ID: `M2-3`
Статус: `done` • PR: —

Checklist:
- [x] Время синка, объемы данных, счетчики ошибок.
- [x] Экспорт отчета для поддержки.

Аудит (факт):
- [x] Добавлены структурированные метрики синка (время, объёмы, счетчики ошибок).
- [x] Отчёт для саппорта добавлен в диагностику (sync_report.json).

### M2-5 Google Drive/OneDrive: решение и план
Issue ID: `M2-5`
Статус: `done` • PR: —

Checklist:
- [x] Решение по OAuth/UX подключения.
- [x] Подготовка acceptance criteria и тест-плана.
- [x] Инструкции по настройке провайдеров (Google + Microsoft/OneDrive).
Ссылки: `docs/deferred_features.md`.

Аудит (факт):
- [x] OAuth для Google Drive/OneDrive реализован в коде, решение/план в документах зафиксированы.
- [x] Acceptance criteria и тест‑план для этих провайдеров выделены.
- [x] Google Drive sync работает на macOS, iOS, Android.
- [x] OneDrive sync работает на macOS, iOS, Android.

Решение по OAuth/UX подключения (фиксируем):
- Публичное consumer‑приложение: OAuth‑клиенты (clientId/redirectUri) встроены в сборку, пользователь НЕ вводит ключи.
- OAuth 2.0 Authorization Code + PKCE, запуск через системный браузер.
- Минимальные scope: доступ только к папке приложения (Google Drive: appDataFolder или app‑specific folder; OneDrive: app folder).
- Хранение refresh token в secure storage (Keychain/Keystore).
- Единый UX: выбор провайдера → системный логин → подтверждение доступа → создание/выбор папки синка → статус “Connected”.
- Явный “Disconnect” с удалением токенов и локального статуса провайдера.
- Ошибки: показываем пользовательское сообщение + код/тип ошибки в диагностике, без утечек секретов.

Acceptance Criteria:
- [x] Пользователь может подключить Google Drive/OneDrive без ввода ключей/JSON/технических настроек.
- [x] Подключение Google Drive и OneDrive через системный браузер с PKCE работает на iOS/Android.
- [x] После подключения создается/используется папка приложения и выполняется первый sync.
- [x] Refresh token сохраняется и работает при перезапуске приложения.
- [x] “Disconnect” удаляет токены и блокирует доступ к провайдеру до нового подключения.
- [x] Ошибки авторизации (revoked/expired/denied) понятны пользователю и видны в диагностике.

Test Plan:
- [x] Убедиться, что в UI нет экранов ввода clientId/clientSecret/redirectUri для Google/OneDrive.
- [x] Подключить Google Drive и OneDrive на “чистом” устройстве; убедиться, что первый sync проходит.
- [x] Перезапустить приложение; убедиться, что повторный логин не требуется и sync доступен.
- [x] Отозвать доступ в настройках провайдера; проверить, что приложение показывает ошибку и предлагает переподключение.
- [x] Нажать “Disconnect”; убедиться, что токены удалены и sync невозможен без повторного входа.
- [x] Проверить, что создается только app-folder, нет доступа к “всем файлам”.

Инструкции по настройке провайдеров:
Google (Google Cloud Console):
- Создать проект и включить Google Drive API.
- Настроить OAuth Consent Screen (User Type: External/Internal), указать app name, support email, добавить scopes (минимальные).
- Создать OAuth Client ID: Android/iOS/Web (в зависимости от платформы).
- Для iOS: добавить Bundle ID и настроить URL scheme.
- Для Android: указать package name и SHA-1/256 сертификаты подписи.
- Перед релизом: обновить release SHA‑1/256, включить Custom URI scheme для Android‑клиента, проверить redirect URI/URL scheme во всех клиентах.
- Включить redirect URI для desktop/system browser (если требуется библиотекой).

Microsoft/OneDrive (Microsoft Entra ID / Azure Portal):
- Создать App Registration.
- Включить Microsoft Graph permissions (Files.ReadWrite.AppFolder минимально).
- Добавить Redirect URI для mobile (custom scheme) и/или system browser flow.
- Включить “Allow public client flows” (для mobile + PKCE).
- Для iOS/Android указать bundle/package и signature hashes, если применимо.
- Скопировать Client ID и Tenant ID; сохранить в конфиг приложения.

---
## Milestone M3 — Stage 2: Sync Gateway (backend)
Цель: собственный backend с курсорной синхронизацией и realtime каналом.

### M3-1 API scaffold + auth
Issue ID: `M3-1`
Статус: `done` • PR: —

Checklist:
- [x] NestJS scaffold, DTO validation, JWT guard.

### M3-2 Storage + DAO + миграции
Issue ID: `M3-2`
Статус: `done` • PR: —

Checklist:
- [x] Таблицы event_log и reading_position.
- [x] Миграции и репозитории.

Аудит (факт):
- [x] Схема Prisma содержит `EventLog`, `ReadingPosition` и `SyncCursor`.
- [x] Миграции есть, репозитории/DAO добавлены для `EventLog`/`SyncCursor`/`ReadingPosition`.

### M3-3 Idempotency/Dedup + ACK
Issue ID: `M3-3`
Статус: `done` • PR: —

Checklist:
- [x] Dedup по id.
- [x] Ответы accepted/rejected/duplicate.

Аудит (факт):
- [x] Dedup по id реализован через проверку в БД.
- [x] ACK возвращает `accepted/rejected/duplicate`.

### M3-4 Pull API (cursor-based)
Issue ID: `M3-4`
Статус: `done` • PR: —

Checklist:
- [x] Cursor paging, лимиты, serverCursor.

Аудит (факт):
- [x] Cursor/limit реализованы, курсор устойчив к перезапуску (хранение в БД).

### M3-5 WebSocket уведомления
Issue ID: `M3-5`
Статус: `done` • PR: —

Checklist:
- [x] WS endpoint, reconnect, events_available.

Аудит (факт):
- [x] WS endpoint `/sync/ws` добавлен (hello/pull/events/events_available).

### M3-6 Observability + контрактные тесты
Issue ID: `M3-6`
Статус: `done` • PR: —

Checklist:
- [x] Метрики/логи/трейсинг.
- [x] Contract tests по `docs/sync_gateway_api.md`.

Аудит (факт):
- [x] Метрики и структурированные логи добавлены, endpoint `/metrics`.
- [x] Контрактные тесты добавлены (REST + WS + негативные кейсы).
- [x] Трейсинг (OpenTelemetry) добавлен, управляется через env.

---
## Milestone M4 — Stage 3: AI и база знаний
Цель: AI-функции поверх локальных/синхронизированных данных.

### M4-1 Summaries + Q&A
Issue ID: `M4-1`
Статус: `done` • PR: —

### M4-2 Семантический поиск (эмбеддинги)
Issue ID: `M4-2`
Статус: `done` • PR: —

### M4-3 Knowledge graph (прототип)
Issue ID: `M4-3`
Статус: `planned` • PR: —

Checklist:
- Граф сущностей для одной книги: Book/Chapter/Highlight/Note.
- Backlinks для Note и Concept.
- AI извлечение концептов из чанков и из note text (явные `[[...]]` + AI).
- Graph view (минимальный) с фильтром по книге.
- Binder (минимальный): создать, добавить book/note, фильтровать граф по binder.

Acceptance Criteria:
- Создали highlight и note → в графе есть `Chapter -> Highlight` и `Note -> ABOUT -> Highlight`.
- В карточке Note отображаются outgoing links (concepts) и backlinks (notes/concepts).
- AI summary создаёт `Summary` и связь `SUMMARIZES`.
- AI extraction создаёт `Concept` и связь `MENTIONS (source=ai, confidence=...)`.
- Binder ограничивает граф и списки сущностей (scope “только внутри binder”).

Test Plan:
- Импортировать книгу, создать 2 highlights и 2 notes, проверить связи в graph view.
- Запустить AI summary/extraction и убедиться в появлении Concept/Summary.
- Создать binder, добавить book/note, проверить фильтрацию графа.

Аудит (факт):
- [ ] Neo4j/graph‑слой не интегрирован.
- [ ] Backlinks/graph view/binder отсутствуют в UI.

---
## Milestone M5 — Переносимый деплой и инфраструктура
Цель: единый контракт развёртывания (GCP ↔ VPS), без провайдер-специфичных зависимостей.

### M5-1 Инфра-скелет в репозитории
Issue ID: `INFRA-1A`
Статус: `done` • PR: —

Checklist:
- [x] Добавить `infra/compose`, `infra/gcp`, `infra/vps`, `infra/*/runbooks`.
- [x] `infra/compose/README.md` с запуском local/dev/VPS.

Acceptance Criteria:
- [x] В репозитории есть структура, совместимая с требованиями из `docs/portable_deployment_requirements.md`.

Аудит (факт, 2026-02-04):
- [x] Добавлены `infra/compose`, `infra/gcp`, `infra/vps`, runbooks.
- [x] Добавлены `scripts/backup.sh`, `scripts/restore.sh`, `scripts/migrate.sh`, `scripts/smoke.sh`.
- [x] Добавлены плейсхолдеры workflows для build/deploy.

PR Draft:
```
Title: infra: add portable deployment skeleton

Checklist
- [x] Create infra folders and minimal README stubs
- [x] Add runbooks placeholders (backup/restore/migration/smoke)
- [x] Document local/dev/VPS bootstrap entry point

Acceptance Criteria
- [x] Infra tree matches portable deployment requirements
```

### M5-2 Dockerfiles и контейнеризация API
Issue ID: `INFRA-1B`
Статус: `done` • PR: —

Checklist:
- [x] `server/Dockerfile` + `.dockerignore`.
- [x] Health endpoint (`/health`) документирован и доступен в контейнере.
- [x] Базовый образ и команды запуска зафиксированы.

Acceptance Criteria:
- [x] `docker build` для `server` проходит, контейнер отвечает на `/health`.

PR Draft:
```
Title: infra: dockerize api service

Checklist
- [x] Add `server/Dockerfile` + `.dockerignore`
- [x] Ensure `/health` is reachable in container
- [x] Document build/run commands

Acceptance Criteria
- [x] `docker build` and `docker run` succeed with `/health` 200
```

### M5-3 Dockerfiles для AI/Worker (если сервисы в этом репо)
Issue ID: `INFRA-1C`
Статус: `done` • PR: —

Checklist:
- [x] `ai/Dockerfile` и/или `worker/Dockerfile` (если сервисы есть/появятся).
- [x] Health endpoint (`/health`) для каждого сервиса.

Acceptance Criteria:
- [x] Образы `ai` и `worker` собираются и проходят healthcheck.

Аудит (факт, 2026-02-04):
- [x] `docker build` для `ai` и `worker` выполнен успешно.
- [x] `GET /health` для `ai` и `worker` возвращает 200.
- [x] `/ingest` в `ai` создаёт задачи, `worker` их обрабатывает (Celery + Redis).

PR Draft:
```
Title: infra: dockerize ai/worker services

Checklist
- [x] Add `ai/Dockerfile` and/or `worker/Dockerfile` (if services exist)
- [x] Add minimal `/health` handlers
- [x] Document build/run commands

Acceptance Criteria
- [x] `docker build` succeeds for each service and `/health` responds
```

### M5-4 Canonical Compose + env контракт
Issue ID: `INFRA-1D`
Статус: `done` • PR: —

Checklist:
- [x] `infra/compose/compose.yaml` для api/ai/worker/postgres/redis/qdrant/neo4j/minio.
- [x] Volumes + networks + healthchecks по требованиям.
- [x] `.env.example` с полным списком ENV и комментариями.

Acceptance Criteria:
- [x] Полный стек поднимается `docker compose --env-file .env up -d` локально/на VPS.
- [x] Все healthchecks проходят.

Аудит (факт, 2026-02-04):
- [x] `docker compose -f infra/compose/compose.yaml --env-file infra/compose/.env.example up -d` проходит.
- [x] `/health` для `api`/`ai`/`worker` возвращает 200.
- [x] `qdrant` (`/healthz`) и `minio` (`/minio/health/ready`) возвращают 200.
- [x] `ai /ingest` создаёт задачу, `worker` её обрабатывает.

Test Plan:
- Поднять стек, проверить `/health` у api/ai и readiness у stateful.

PR Draft:
```
Title: infra: add canonical compose and env contract

Checklist
- [x] Create `infra/compose/compose.yaml` for api/ai/worker/postgres/redis/qdrant/neo4j/minio
- [x] Add networks, volumes, healthchecks
- [x] Add `.env.example` with full ENV list + comments

Acceptance Criteria
- [x] `docker compose --env-file .env up -d` brings up full stack
- [x] All healthchecks pass
```

### M5-5 FileStorage абстракция
Issue ID: `INFRA-2`
Статус: `done` • PR: —

Checklist:
- [x] Интерфейс `FileStorage` с put/get/delete + presigned upload/download.
- [x] S3-adapter (default), GCS-adapter (опционально).
- [x] Переключение провайдера только через ENV.

Acceptance Criteria:
- [x] Смена `STORAGE_PROVIDER` не требует правок кода и схем БД.

Test Plan:
- Загрузка файла через presigned URL и скачивание в обоих режимах (S3/MinIO и GCS, если есть).

Аудит (факт, 2026-02-05):
- [x] Presigned upload/download проверены для MinIO и GCS.

### M5-6 Backup/Restore/Smoke
Issue ID: `INFRA-3`
Статус: `done` • PR: —

Checklist:
- [x] `scripts/backup.sh`, `scripts/restore.sh`, `scripts/smoke.sh`.
- [x] Runbooks для backup/restore/migration/smoke в `infra/*/runbooks`.

Acceptance Criteria:
- [x] На staging пройден цикл backup → restore → smoke = PASS.

Аудит (факт, 2026-02-05):
- [x] `./scripts/backup.sh` создает дампы Postgres/Neo4j + архивы Qdrant/MinIO.
- [x] `./scripts/restore.sh <backup>` успешно восстанавливает данные.
- [x] `./scripts/smoke.sh` проходит (healthchecks OK).

Test Plan:
- Выполнить backup, восстановить в чистом окружении, прогнать smoke.

### M5-7 GCP Deployment Mode (A или B)
Issue ID: `INFRA-4`
Статус: `done` • PR: —

Checklist:
- [x] Выбран базовый режим (A или B).
- [x] `infra/gcp/README.md` с пошаговым деплоем.
- [x] (Если B) приватная сеть между Cloud Run и VM.

Acceptance Criteria:
- [x] Деплой воспроизводим по инструкции и не требует ручных кликов сверх описанного.

Аудит (факт, 2026-02-05):
- [x] `JWT_SECRET` обновлен в `infra/gcp/prod.env` и применен в Cloud Run.
- [x] После смены секрета требуется переподключить синхронизацию (новый ключ).

### M5-8 VPS Runbook + hardening
Issue ID: `INFRA-5`
Статус: `done` • PR: —

Checklist:
- [x] `infra/vps/README.md` (docker, firewall, proxy, tls).
- [x] `hardening.md` чек-лист.

Acceptance Criteria:
- [x] VPS готов к поднятию compose стека и не экспонирует stateful наружу.

### M5-9 CI/CD
Issue ID: `INFRA-6`
Статус: `done` • PR: —

Checklist:
- [x] `build-and-push.yml` (api/ai/worker).
- [x] `deploy-gcp.yml` (под выбранный режим).
- [x] `deploy-vps.yml` (опционально, через SSH).

Acceptance Criteria:
- [x] Образы публикуются с тегами `:sha`, `:main`, `:release`.
