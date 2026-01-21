# File-based Sync (v1, implemented)

Цель: server‑less синхронизация через облачные диски/NAS.

Статус: **реализовано** (Stage 1).

---
## Поддерживаемые каналы
- Dropbox
- Яндекс.Диск
- NAS: Synology Drive, WebDAV, SMB (опционально)

Отложено: Google Drive, OneDrive (см. `docs/deferred_features.md`).

---
## Принцип
- Event log + state выгружаются в файл(ы) в облаке.
- Клиент периодически сверяет актуальные версии и применяет LWW локально.
- Устройство хранит `deviceId` и `lastSyncAt`.

---
## Формат файлов (v1)
- `event_log.json` — массив событий (DTO v1).
- `state.json` — materialized state (reading positions).
- `meta.json` — версия схемы, последний `updatedAt`.
- `books_index.json` — индекс книг для сверки и загрузки.

### event_log.json (v1)
```json
{
  "schemaVersion": 1,
  "deviceId": "uuid",
  "generatedAt": "2026-01-12T12:00:00.000Z",
  "cursor": "opaque_cursor",
  "events": [
    {
      "id": "uuid",
      "entityType": "note|highlight|bookmark|reading_position",
      "entityId": "uuid-or-bookId",
      "op": "add|update|delete",
      "payload": {
        "updatedAt": "2026-01-12T11:59:00.000Z"
      },
      "createdAt": "2026-01-12T11:59:00.000Z"
    }
  ]
}
```

### state.json (v1)
```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-01-12T12:00:00.000Z",
  "cursor": "opaque_cursor",
  "readingPositions": [
    {
      "bookId": "book-1",
      "chapterHref": "chapter-3.xhtml",
      "anchor": "chapter-3.xhtml|1200",
      "offset": 1200,
      "updatedAt": "2026-01-12T11:58:00.000Z"
    }
  ]
}
```

### meta.json (v1)
```json
{
  "schemaVersion": 1,
  "deviceId": "uuid",
  "lastUploadAt": "2026-01-12T12:00:00.000Z",
  "lastDownloadAt": "2026-01-12T12:00:00.000Z",
  "eventCount": 120
}
```

### books_index.json (v1)
```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-01-12T12:00:00.000Z",
  "books": [
    {
      "id": "book-1",
      "title": "Book title",
      "author": "Author",
      "fingerprint": "sha256",
      "size": 123456,
      "updatedAt": "2026-01-12T11:58:00.000Z",
      "extension": ".epub",
      "path": "remote/path/book-1.epub",
      "deleted": false
    }
  ]
}
```

### Merge rules
- `event_log.json`: merge по `id` (идемпотентность), сортировка по `createdAt`.
- `state.json`: LWW по `updatedAt` для каждой записи.
- `cursor`: opaque идентификатор последнего события, из которого собран `state.json`.

---
## Конфликты
- LWW по `updatedAt` для каждой сущности.
- При конфликте event‑id → idempotent skip.

---
## Безопасность
- Использовать OAuth токены провайдера.
- Шифрование контента (optional) на стороне клиента.
