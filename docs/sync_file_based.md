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

---
## Конфликты
- LWW по `updatedAt` для каждой сущности.
- При конфликте event‑id → idempotent skip.

---
## Безопасность
- Использовать OAuth токены провайдера.
- Шифрование контента (optional) на стороне клиента.
