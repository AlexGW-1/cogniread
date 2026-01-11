# Sync Gateway API (Draft v0.1)

Цель: минимальный контракт для синхронизации по Event Log с LWW‑политикой на стороне клиента/сервера.
Транспорт: REST + WebSocket.  
Auth: Bearer token (JWT).

---
## Base
- Base URL: `/sync`
- Header: `Authorization: Bearer <JWT>`
- Content‑Type: `application/json`
- Версионирование: `schemaVersion` в каждом payload + `apiVersion` в ответах.

---
## Основные сущности

### EventLogEntry (DTO)
```json
{
  "id": "uuid",
  "entityType": "note|highlight|bookmark|reading_position",
  "entityId": "uuid-or-bookId",
  "op": "add|update|delete",
  "payload": { "..." : "minimal fields" },
  "createdAt": "2026-01-11T12:34:56.000Z",
  "schemaVersion": 1
}
```

### Ack
```json
{ "id": "uuid", "status": "accepted|rejected", "reason": "optional" }
```

---
## REST API

### 1) Upload events
`POST /sync/events`

**Request**
```json
{
  "deviceId": "uuid",
  "cursor": "last_seen_cursor_or_null",
  "events": [ /* EventLogEntry[] */ ]
}
```

**Response**
```json
{
  "apiVersion": "v0.1",
  "accepted": [ /* Ack[] */ ],
  "serverCursor": "opaque_cursor"
}
```

### 2) Pull events
`GET /sync/events?cursor=<opaque>&limit=200`

**Response**
```json
{
  "apiVersion": "v0.1",
  "events": [ /* EventLogEntry[] */ ],
  "serverCursor": "opaque_cursor"
}
```

### 3) Upload device state (optional)
`POST /sync/state`

**Request**
```json
{
  "deviceId": "uuid",
  "lastSeenCursor": "opaque_cursor",
  "readingPositions": [ /* ReadingPositionDto[] */ ],
  "schemaVersion": 1
}
```

**Response**
```json
{ "apiVersion": "v0.1", "status": "ok" }
```

---
## WebSocket API

`GET /sync/ws`

**Handshake**
```json
{ "type": "hello", "deviceId": "uuid", "lastSeenCursor": "opaque_cursor" }
```

**Server → Client**
```json
{ "type": "events_available", "serverCursor": "opaque_cursor" }
```

**Client → Server**
```json
{ "type": "pull", "cursor": "opaque_cursor" }
```

**Server → Client (batch)**
```json
{ "type": "events", "events": [ /* EventLogEntry[] */ ], "serverCursor": "opaque_cursor" }
```

---
## Ошибки
- `401` — invalid/expired JWT
- `409` — version conflict (idempotency / duplicates)
- `422` — invalid payload (schemaVersion, fields)

---
## Примечания
- Идемпотентность: `id` события уникален глобально; повторная отправка возвращает `accepted` со статусом `accepted`.
- LWW: конечное состояние определяется по `updatedAt` внутри payload.
- Ограничение размера: `events` батчем ≤ 200, payload ≤ 1MB.
