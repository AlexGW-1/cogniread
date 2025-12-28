# Состояние проекта CogniRead на 2025-12-28

## Ключевое
- Проект **сброшен** до старта разработки.
- В репозитории сохранены **проектные документы** и создан **скелет Flutter-приложения** (без реальной логики импорта/рендера EPUB).
- Среда разработки целевая: **Visual Studio Code**.

## Артефакт
- ZIP со стартовой структурой: `cogniread_project_skeleton.zip` (в этой же выдаче — обновлённый архив со STATE.md).

## Что уже есть
### docs/
- `final_tech_stack.docx`
- `solution_architecture_doc.docx`
- `architecture_diagrams.docx`
- `docs/README.md`

### Flutter (root)
- `pubspec.yaml`, `analysis_options.yaml`, `assets/`
- Минимальная навигация: **LibraryScreen → ReaderScreen**
- Заглушки домена/данных под импорт EPUB:
  - `Book` entity
  - `BookRepository` interface
  - `ImportEpub` usecase
  - `EpubLocalDatasource` (NotImplementedYet)
  - `BookRepositoryImpl` (оборачивает ошибки в Result)
- Простейший smoke-test: `test/smoke_test.dart`

### .vscode/
- `settings.json`, `launch.json` (базовая отладка/форматирование)

### scripts/
- `bootstrap_platforms.sh` — генерирует платформы через `flutter create` если папки `android/ios/macos/web` отсутствуют
- `check_env.sh` — запускает `flutter doctor -v`

## Текущее дерево (усечённо)
```
  .gitignore
  .vscode/
    .vscode/launch.json
    .vscode/settings.json
  README.md
  analysis_options.yaml
  assets/
  lib/
    lib/main.dart
    lib/src/
      lib/src/app.dart
      lib/src/core/
        lib/src/core/error/
        lib/src/core/types/
        lib/src/core/utils/
      lib/src/features/
        lib/src/features/library/
        lib/src/features/reader/
  pubspec.yaml
  test/
    test/smoke_test.dart
  docs/
    docs/README.md
    docs/architecture_diagrams.docx
    docs/final_tech_stack.docx
    docs/solution_architecture_doc.docx
  scripts/
    scripts/bootstrap_platforms.sh
    scripts/check_env.sh
```

## Что намеренно НЕ сделано (следующий шаг)
1) Реальный импорт EPUB:
   - выбор файла (file picker / drag&drop)
   - копирование в app-managed storage (macOS sandbox-safe)
   - разбор метаданных EPUB (title/author, cover)
2) Экран чтения:
   - рендер страниц/глав
   - TOC drawer
   - прогресс, закладки, выделения

## Команды старта
```bash
cd cogniread
# если платформенные папки ещё не созданы, можно выполнить:
# flutter create . --platforms=android,ios,macos,web --org com.cogniread
flutter pub get
flutter run -d macos
```
