# Sync Gateway — технический план задач

Формат: 1 issue ≈ 1 PR ≈ 1 день.

---
## 1) API scaffold (NestJS)
**Цель:** каркас сервиса sync-gateway.

**Checklist**
- [x] NestJS проект: модуль `sync`.
- [x] Endpoints: `POST /sync/events`, `GET /sync/events`.
- [x] JWT guard (Bearer).
- [x] DTO + basic validation.

---
## 2) EventLog storage + migrations
**Цель:** схема хранения событий.

**Checklist**
- Таблица `event_log` + индексы (см. `docs/sync_gateway_storage.md`).
- Миграции.
- Репозиторий/DAO.

---
## 3) Idempotency + ACK
**Цель:** надёжная обработка повторных событий.

**Checklist**
- Dedup по `id`.
- Ответ `accepted|rejected|duplicate`.
- 409/422 для конфликтов и валидатора.

---
## 4) Pull API (cursor-based)
**Цель:** выдача событий по курсору.

**Checklist**
- Cursor‑based paging.
- Лимиты (`limit <= 200`).
- Корректные `serverCursor`.

---
## 5) Materialized `reading_position`
**Цель:** быстрый доступ к прогрессу чтения.

**Checklist**
- Таблица `reading_position`.
- LWW на сервере.
- Тесты на update/override.

---
## 6) WebSocket notifications
**Цель:** push‑уведомления о новых событиях.

**Checklist**
- WS endpoint `/sync/ws`.
- `hello`, `events_available`, `pull`.
- Отработка reconnect.

---
## 7) Observability
**Цель:** метрики, логи, трейсинг.

**Checklist**
- Метрики из `docs/sync_observability.md`.
- Логи sync‑операций.
- Трейсинг REST + WS.

---
## 8) Contract tests
**Цель:** защита контракта и валидаций.

**Checklist**
- DTO validation tests.
- Negative cases (invalid schema, stale events).
- Golden tests для примеров из `docs/sync_gateway_api.md`.
