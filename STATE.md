# Состояние проекта CogniRead на 2026-01-18

## Ключевое
- Локальный Flutter-клиент с импортом EPUB, библиотекой и поиском по библиотеке.
- Экран чтения с разбором EPUB (рендер нативным текстом), оглавлением и восстановлением позиции.
- Заметки/выделения/закладки и поиск по книге реализованы.
- Server-less синхронизация через облака/NAS реализована (file-based sync: Dropbox, Yandex Disk, WebDAV/SMB).
- AI и backend (sync-gateway/knowledge graph) отсутствуют (следующие этапы).

## Что уже есть
### Flutter (root)
- Реальный импорт EPUB (file_picker) с копированием в app-managed storage.
- Дедупликация по хэшу и сохранение в локальной библиотеке (Hive).
- Экран чтения: парсинг EPUB, оглавление, навигация по главам, обработка ошибок.
- Сохранение позиции чтения (глава + смещение) и восстановление при открытии.
- Заметки/выделения/закладки (сейчас одна закладка на книгу) и переход к месту.
- Поиск по книге с временной подсветкой результата.
- Desktop и mobile UI (адаптивная библиотека, встраиваемый Reader, поиск по библиотеке).
- UI-keys на критических элементах (для стабильных widget-тестов).
- Извлечение обложек EPUB, хранение и отображение в библиотеке.
- File-based sync engine: `event_log.json`, `state.json`, `meta.json`, `books_index.json` + загрузка/слияние (LWW) через `SyncAdapter`.
- Провайдеры синхронизации: Dropbox, Yandex Disk, WebDAV (NAS), SMB fallback.

### docs/
- `docs/spec_mvp.md` — scope по MVP.
- `docs/plan_mvp0.md`, `docs/plan_mvp1.md` — планы итераций.
- `docs/decisions.md` — технологические решения.
- `docs/sync_file_based.md` — описание file-based sync (Этап 1).
- `docs/sync_gateway_*.md` — черновики будущего sync-gateway (Этап 2).

### scripts/
- `scripts/bootstrap_platforms.sh`
- `scripts/check_env.sh`

## Что намеренно НЕ сделано (следующий шаг)
1) AI (summary/explain/knowledge graph).
2) Провайдеры синхронизации Google Drive и OneDrive (отложены).
3) Шифрование содержимого file-based sync (опционально).
4) Sync-gateway backend (NestJS + PostgreSQL) и realtime sync (WS).

## Команды старта
```bash
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```
