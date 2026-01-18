# File-based Sync — технический план задач

Формат: 1 issue ≈ 1 PR ≈ 1 день.

Статус на 2026‑01‑18:
- ✅ Dropbox / Yandex Disk / WebDAV (NAS) — реализованы и протестированы.
- ⏸ Google Drive / OneDrive — отложены.

---
## 1) Sync adapter interface (client)
**Цель:** единый интерфейс для провайдеров (Drive/Dropbox/OneDrive/Yandex/NAS).

**Checklist**
- [x] Интерфейс `SyncAdapter` (list/get/put/delete).
- [x] Обёртки для OAuth‑токенов и ошибок.
- [x] Моки для тестов.

---
## 2) File format v1
**Цель:** финализировать структуру файлов `event_log.json`, `state.json`, `meta.json`.

**Checklist**
- [x] Версионирование (`schemaVersion`).
- [x] Формат cursors + updatedAt.
- [x] Политика merge (LWW).

---
## 3) Local sync engine
**Цель:** локальная синхронизация через файлы.

**Checklist**
- [x] Upload: сериализовать event log → cloud.
- [x] Download: читать файлы → merge по LWW.
- [x] Conflict handling: idempotent events.

---
## 4) Provider: Google Drive
**Цель:** первый рабочий провайдер.

**Checklist**
- [ ] OAuth flow.
- [ ] CRUD файлов синка.
- [ ] Тест на upload/download.

---
## 5) Provider: Dropbox
**Цель:** второй провайдер.

**Checklist**
- [x] OAuth flow.
- [x] CRUD файлов синка.
- [x] Тест на upload/download.

---
## 6) Provider: OneDrive
**Цель:** третий провайдер.

**Checklist**
- [ ] OAuth flow.
- [ ] CRUD файлов синка.
- [ ] Тест на upload/download.

---
## 7) Provider: Yandex Disk
**Цель:** четвёртый провайдер.

**Checklist**
- [x] OAuth flow.
- [x] CRUD файлов синка.
- [x] Тест на upload/download.

---
## 8) Provider: NAS (WebDAV/SMB)
**Цель:** персональные NAS.

**Checklist**
- [x] WebDAV клиент (минимальный).
- [x] CRUD файлов синка.
- [x] Тест на upload/download.
