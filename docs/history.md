# История разработки (кратко)

## MVP0 — локальный клиент (завершено)
- Библиотека, импорт EPUB, хранение в app-managed storage.
- Reader с нативным рендером, оглавлением и восстановлением позиции.
- Базовая архитектура, тесты, DoD.

## MVP1 — реальный импорт и метаданные (завершено)
- File picker, валидация, дедупликация по хэшу.
- Парсинг title/author/cover, сохранение в LibraryStore.

## MVP2 — активное чтение (завершено)
- Notes/Highlights/Bookmarks, поиск по книге.
- Глобальный поиск по библиотеке через локальный индекс.
- Перф‑оптимизации рендера и стабилизация UI.

## Stage 1 — server-less file-based sync (завершено)
- File-based sync engine: `event_log.json`, `state.json`, `meta.json`, `books_index.json`.
- Провайдеры: Dropbox, Яндекс.Диск, WebDAV/SMB.
- UI статуса синхронизации и диагностика.

## Что дальше
- План следующих этапов: `docs/plan_next_stages.md`.
- Спеки: `docs/search_global_v2.md`, `docs/notes_screen_v1.md`.
- Stage 2 (sync‑gateway): `docs/sync_gateway_issues.md` и связанные спецификации.
- Отложенный функционал: `docs/deferred_features.md`.
