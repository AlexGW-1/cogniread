# Sync Policy (Draft v0.1)

## 1. Принципы
- Источник правды: event log.
- Идемпотентность: событие с тем же `id` повторно не применяется.
- Конфликты: LWW по `updatedAt` внутри payload.

---
## 2. LWW правила
- Для `note`, `highlight`, `bookmark`, `reading_position` сравниваем `payload.updatedAt`.
- Если `updatedAt` отсутствует — событие считается менее свежим и может быть отклонено.
- На равных `updatedAt`: сервер оставляет текущую запись, возвращает `ack: rejected` с reason.

---
## 3. Протокол ACK
- `accepted`: событие записано в event_log и (при необходимости) применено к state.
- `rejected`: событие не применено. Причины: `stale`, `invalid`, `duplicate`.
- `duplicate`: событие уже было применено (idempotent).

---
## 4. Обновление materialized state
- Сервер может поддерживать `reading_position` как materialized view для быстрых запросов.
- При `reading_position` событии сервер применяет LWW и обновляет таблицу.

---
## 5. Повторная доставка
- Клиент хранит локальный event log и повторяет отправку до `accepted`.
- Сервер допускает повторную отправку событий (idempotent).

---
## 6. Ошибки
- `409 conflict` для конфликтов LWW.
- `422 invalid` при некорректном payload.
