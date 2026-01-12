# File-based Sync (Draft v0.1)

Цель: server‑less синхронизация через облачные диски/NAS.

---
## Поддерживаемые каналы
- Google Drive
- Dropbox
- Microsoft OneDrive
- Яндекс.Диск
- NAS: Synology Drive, WebDAV, SMB (опционально)

---
## Принцип
- Event log + state выгружаются в файл(ы) в облаке.
- Клиент периодически сверяет актуальные версии и применяет LWW локально.
- Устройство хранит `deviceId` и `lastSyncAt`.

---
## Формат файлов (черновик)
- `event_log.json` — массив событий (DTO v1).
- `state.json` — materialized state (reading positions).
- `meta.json` — версия схемы, последний `updatedAt`.

### event_log.json (v1)
```json
{
  "schemaVersion": 1,
  "deviceId": "uuid",
  "generatedAt": "2026-01-12T12:00:00.000Z",
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

### Merge rules
- `event_log.json`: merge по `id` (идемпотентность), сортировка по `createdAt`.
- `state.json`: LWW по `updatedAt` для каждой записи.

---
## Конфликты
- LWW по `updatedAt` для каждой сущности.
- При конфликте event‑id → idempotent skip.

---
## Безопасность
- Использовать OAuth токены провайдера.
- Шифрование контента (optional) на стороне клиента.
