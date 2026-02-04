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
- Полнотекст по книгам/заметкам/выделениям.
- Jump-to-location в Reader.
- Диагностика + rebuild индекса.

Test Plan:
- Поиск по 2–3 книгам, переход в Reader.
- Перестроить индекс, убедиться, что ошибки понятны.

### M1-2 Global Notes/Highlights v1
Issue ID: `M1-2`
Статус: `done` • PR: —  
Scope: см. `docs/notes_screen_v1.md`.

Checklist:
- Глобальный список notes/highlights с поиском и фильтрами.
- Группировка по книгам + лента.
- Free notes (без книги) + синхронизация.
- Массовые действия: экспорт/удаление.

Acceptance Criteria:
- Раздел “Заметки” не placeholder.
- Поиск/фильтры работают; переход в Reader по anchor.

Test Plan:
- Создать 3–5 заметок/выделений в разных книгах.
- Проверить поиск и фильтры, открыть пару элементов в Reader.

### M1-3 Закладки: несколько на книгу + управление
Issue ID: `M1-3`
Статус: `done` • PR: —

Checklist:
- Хранить список закладок, а не одну.
- UI списка + удаление/переименование.
- Навигация в Reader по anchor.

Acceptance Criteria:
- Можно создать 3+ закладок в одной книге.
- Удаление не ломает текущую позицию чтения.

Test Plan:
- Создать/удалить/переименовать закладки, перейти по ним.

### M1-4 Экспорт заметок/выделений (JSON + Markdown)
Issue ID: `M1-4`
Статус: `done` • PR: —

Checklist:
- Экспорт выбранных элементов в zip (`notes.json`, `notes.md`).
- Включить метаданные книги и anchor.

Acceptance Criteria:
- Экспорт создается, структура совпадает с PRD.

Test Plan:
- Экспорт 5 элементов, проверить содержимое файлов.

### M1-5 Обновление тест-плана под новые разделы
Issue ID: `M1-5`
Статус: `done` • PR: —

Checklist:
- Обновить `docs/test_plan_stage1_sync.md` при изменениях синка.
- Добавить тест-план для Notes/Global Search (если нет).

Acceptance Criteria:
- Есть воспроизводимые ручные сценарии.

---
## Milestone M2 — Стабилизация синхронизации
Цель: повысить надежность и прозрачность file-based sync без изменения модели данных.

### M2-1 Статусы синка и понятные ошибки
Issue ID: `M2-1`
Статус: `done` • PR: —

Checklist:
- Ясные состояния: success/error/paused.
- Тексты ошибок без утечек секретов.

Аудит (факт):
- [x] Success/error фиксируются и показываются в UI (`SyncStatusSnapshot`, экран настроек).
- [x] Paused: добавлен явный статус "paused" + сохранение и отображение.
- [x] Маскирование секретов в пользовательских сообщениях.

### M2-2 Retry/backoff и лимиты API
Issue ID: `M2-2`
Статус: `done` • PR: —

Checklist:
- Экспоненциальный backoff на сетевые ошибки.
- Раздельные таймауты request/transfer.

Аудит (факт):
- [x] Экспоненциальный backoff + retry реализованы (`ResilientSyncAdapter`).
- [x] Раздельные таймауты есть для WebDAV (request/transfer).
- [x] Лимиты API: 429 учитывает Retry-After, добавлены per-provider лимиты.

### M2-3 Диагностика и метрики
Issue ID: `M2-3`
Статус: `done` • PR: —

Checklist:
- Время синка, объемы данных, счетчики ошибок.
- Экспорт отчета для поддержки.

Аудит (факт):
- [x] Добавлены структурированные метрики синка (время, объёмы, счетчики ошибок).
- [x] Отчёт для саппорта добавлен в диагностику (sync_report.json).

### M2-5 Google Drive/OneDrive: решение и план
Issue ID: `M2-5`
Статус: `done` • PR: —

Checklist:
- Решение по OAuth/UX подключения.
- Подготовка acceptance criteria и тест-плана.
- Инструкции по настройке провайдеров (Google + Microsoft/OneDrive).
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
- NestJS scaffold, DTO validation, JWT guard.

### M3-2 Storage + DAO + миграции
Issue ID: `M3-2`
Статус: `done` • PR: —

Checklist:
- Таблицы event_log и reading_position.
- Миграции и репозитории.

Аудит (факт):
- [x] Схема Prisma содержит `EventLog`, `ReadingPosition` и `SyncCursor`.
- [x] Миграции есть, репозитории/DAO добавлены для `EventLog`/`SyncCursor`/`ReadingPosition`.

### M3-3 Idempotency/Dedup + ACK
Issue ID: `M3-3`
Статус: `done` • PR: —

Checklist:
- Dedup по id.
- Ответы accepted/rejected/duplicate.

Аудит (факт):
- [x] Dedup по id реализован через проверку в БД.
- [x] ACK возвращает `accepted/rejected/duplicate`.

### M3-4 Pull API (cursor-based)
Issue ID: `M3-4`
Статус: `done` • PR: —

Checklist:
- Cursor paging, лимиты, serverCursor.

Аудит (факт):
- [x] Cursor/limit реализованы, курсор устойчив к перезапуску (хранение в БД).

### M3-5 WebSocket уведомления
Issue ID: `M3-5`
Статус: `done` • PR: —

Checklist:
- WS endpoint, reconnect, events_available.

Аудит (факт):
- [x] WS endpoint `/sync/ws` добавлен (hello/pull/events/events_available).

### M3-6 Observability + контрактные тесты
Issue ID: `M3-6`
Статус: `done` • PR: —

Checklist:
- Метрики/логи/трейсинг.
- Contract tests по `docs/sync_gateway_api.md`.

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
- Добавить `infra/compose`, `infra/gcp`, `infra/vps`, `infra/*/runbooks`.
- `infra/compose/README.md` с запуском local/dev/VPS.

Acceptance Criteria:
- В репозитории есть структура, совместимая с требованиями из `docs/portable_deployment_requirements.md`.

PR Draft:
```
Title: infra: add portable deployment skeleton

Checklist
- [ ] Create infra folders and minimal README stubs
- [ ] Add runbooks placeholders (backup/restore/migration/smoke)
- [ ] Document local/dev/VPS bootstrap entry point

Acceptance Criteria
- [ ] Infra tree matches portable deployment requirements
```

### M5-2 Dockerfiles и контейнеризация API
Issue ID: `INFRA-1B`
Статус: `planned` • PR: —

Checklist:
- `server/Dockerfile` + `.dockerignore`.
- Health endpoint (`/health`) документирован и доступен в контейнере.
- Базовый образ и команды запуска зафиксированы.

Acceptance Criteria:
- `docker build` для `server` проходит, контейнер отвечает на `/health`.

PR Draft:
```
Title: infra: dockerize api service

Checklist
- [ ] Add `server/Dockerfile` + `.dockerignore`
- [ ] Ensure `/health` is reachable in container
- [ ] Document build/run commands

Acceptance Criteria
- [ ] `docker build` and `docker run` succeed with `/health` 200
```

### M5-3 Dockerfiles для AI/Worker (если сервисы в этом репо)
Issue ID: `INFRA-1C`
Статус: `planned` • PR: —

Checklist:
- `ai/Dockerfile` и/или `worker/Dockerfile` (если сервисы есть/появятся).
- Health endpoint (`/health`) для каждого сервиса.

Acceptance Criteria:
- Образы `ai` и `worker` собираются и проходят healthcheck.

PR Draft:
```
Title: infra: dockerize ai/worker services

Checklist
- [ ] Add `ai/Dockerfile` and/or `worker/Dockerfile` (if services exist)
- [ ] Add minimal `/health` handlers
- [ ] Document build/run commands

Acceptance Criteria
- [ ] `docker build` succeeds for each service and `/health` responds
```

### M5-4 Canonical Compose + env контракт
Issue ID: `INFRA-1D`
Статус: `planned` • PR: —

Checklist:
- `infra/compose/compose.yaml` для api/ai/worker/postgres/redis/qdrant/neo4j/minio.
- Volumes + networks + healthchecks по требованиям.
- `.env.example` с полным списком ENV и комментариями.

Acceptance Criteria:
- Полный стек поднимается `docker compose --env-file .env up -d` локально/на VPS.
- Все healthchecks проходят.

Test Plan:
- Поднять стек, проверить `/health` у api/ai и readiness у stateful.

PR Draft:
```
Title: infra: add canonical compose and env contract

Checklist
- [ ] Create `infra/compose/compose.yaml` for api/ai/worker/postgres/redis/qdrant/neo4j/minio
- [ ] Add networks, volumes, healthchecks
- [ ] Add `.env.example` with full ENV list + comments

Acceptance Criteria
- [ ] `docker compose --env-file .env up -d` brings up full stack
- [ ] All healthchecks pass
```

### M5-5 FileStorage абстракция
Issue ID: `INFRA-2`
Статус: `planned` • PR: —

Checklist:
- Интерфейс `FileStorage` с put/get/delete + presigned upload/download.
- S3-adapter (default), GCS-adapter (опционально).
- Переключение провайдера только через ENV.

Acceptance Criteria:
- Смена `STORAGE_PROVIDER` не требует правок кода и схем БД.

Test Plan:
- Загрузка файла через presigned URL и скачивание в обоих режимах (S3/MinIO и GCS, если есть).

### M5-6 Backup/Restore/Smoke
Issue ID: `INFRA-3`
Статус: `planned` • PR: —

Checklist:
- `scripts/backup.sh`, `scripts/restore.sh`, `scripts/smoke.sh`.
- Runbooks для backup/restore/migration/smoke в `infra/*/runbooks`.

Acceptance Criteria:
- На staging пройден цикл backup → restore → smoke = PASS.

Test Plan:
- Выполнить backup, восстановить в чистом окружении, прогнать smoke.

### M5-7 GCP Deployment Mode (A или B)
Issue ID: `INFRA-4`
Статус: `done` • PR: —

Checklist:
- Выбран базовый режим (A или B).
- `infra/gcp/README.md` с пошаговым деплоем.
- (Если B) приватная сеть между Cloud Run и VM.

Acceptance Criteria:
- Деплой воспроизводим по инструкции и не требует ручных кликов сверх описанного.

### M5-8 VPS Runbook + hardening
Issue ID: `INFRA-5`
Статус: `planned` • PR: —

Checklist:
- `infra/vps/README.md` (docker, firewall, proxy, tls).
- `hardening.md` чек-лист.

Acceptance Criteria:
- VPS готов к поднятию compose стека и не экспонирует stateful наружу.

### M5-9 CI/CD
Issue ID: `INFRA-6`
Статус: `planned` • PR: —

Checklist:
- `build-and-push.yml` (api/ai/worker).
- `deploy-gcp.yml` (под выбранный режим).
- `deploy-vps.yml` (опционально, через SSH).

Acceptance Criteria:
- Образы публикуются с тегами `:sha`, `:main`, `:release`.
