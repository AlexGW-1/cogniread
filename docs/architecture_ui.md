# Экранная карта и UI‑архитектура

Этот документ фиксирует экранную карту, пользовательские потоки и сопоставление UI‑компонентов с контроллерами/юзкейсами.

---

## 1) Экранная карта (Screen Map)

### Root
- AppShell (AdaptiveScaffold)
  - BottomNav (mobile) / NavigationRail (tablet/desktop)

### Вкладка 1 — Библиотека
- LibraryScreen
  - ImportScreen (modal/sheet)
  - BookDetailsScreen
    - вкладки: TOC / Notes / Insights
    - CTA → ReaderScreen(bookId)

### Вкладка 2 — Поиск
- GlobalSearchScreen
  - tabs: Books / Notes / Quotes / (позже Concepts)
  - переходы:
    - Book → ReaderScreen
    - Note/Quote → ReaderScreen с jump-to-location
    - Concept → ConceptDetailScreen (позже)

### Вкладка 3 — Читалка
- ReaderScreen(lastOpened | deep link bookId)
  - overlays:
    - TocDrawer / TocSheet
    - SearchInBookSheet
    - ReaderSettingsSheet (Aa)
    - AiPanelSheet / SidePanel
    - CreateNoteSheet (из выделения)
  - ExportNotesScreen (опционально из меню)

### Вкладка 4 — Заметки
- NotesScreen
  - фильтры: book / tag / type / date
  - NoteDetailSheet (быстрый просмотр/редакт)
  - jump-to-location → ReaderScreen

### Вкладка 5 — Профиль/Настройки
- SettingsScreen
  - Reading / AI / Storage / Sync / About / Diagnostics
  - SyncStatusScreen → ConflictResolverScreen (Phase 2)

---

## 2) Ключевые пользовательские потоки

- Первое чтение: Library → Import → BookDetails → Reader → (TOC / Aa / выделение → Note)
- Заметка из чтения: Reader → выделение → CreateNoteSheet → NotesScreen → jump back
- AI summary: Reader/BookDetails → AiPanel → Summary → кеш → повтор без ожидания
- Поиск: GlobalSearch → результаты → Reader jump-to-location
- Синк: Settings → SyncStatus → retry (Phase 2: конфликты)

---

## 3) Таблица экранов: UI-компоненты + контроллеры + use cases

Нотация: Screen → Controller (Riverpod) → UseCases → RepoIface → DataSources.

| Экран | Основные UI-компоненты | Controller/ViewModel (Riverpod) | Ключевые UseCases (Domain) |
| --- | --- | --- | --- |
| AppShell | AdaptiveScaffold, AppNav (BottomBar/Rail), OfflineBadge | AppShellController | GetLastOpenedBook, ObserveSyncStatus |
| LibraryScreen | LibrarySearchBar, LibraryGrid/List, BookCard, SortFilterSheet, EmptyStateImportCTA | LibraryController | GetLibrary, ImportBook, DeleteBook, UpdateBookMeta |
| ImportScreen | FilePickerRow, ImportProgressList, ErrorBanner | ImportController | PickFile, UploadBookToStorage, RegisterBookMeta |
| BookDetailsScreen | BookHero, TabBar, ChapterList, NotesPreviewList, InsightsPreview | BookDetailsController | GetBookDetails, GetToc, GetBookNotes, GetChapterSummaries |
| GlobalSearchScreen | SearchField, TabResults, ResultCard, RecentSearchChips | GlobalSearchController | SearchBooks, SearchNotes, SearchQuotes (позже SemanticSearch/Qdrant) |
| ReaderScreen | ReaderToolbar, ReaderTextView, ReaderProgress, SelectionMenu, TocDrawer/Sheet, ReaderSettingsSheet, AiPanel | ReaderController | OpenBook, GetChapter, SaveReadingPosition, CreateHighlight, RemoveHighlight, JumpToLocation |
| SearchInBook | SearchField, MatchList, HighlightPreview | ReaderSearchController | SearchInBookText, JumpToMatch |
| CreateNoteSheet | QuotePreview, NoteEditor, TagChips, SaveBar | NoteEditorController | CreateNote, UpdateNote, AttachNoteToQuote/Highlight |
| NotesScreen | NotesFilterBar, NoteCard, GroupByToggle | NotesController | GetNotes, FilterNotes, DeleteNote |
| SettingsScreen | SettingsSectionList, ToggleRow, SliderRow, ThemePicker | SettingsController | GetSettings, UpdateSettings, ClearCache |
| SyncStatusScreen | SyncStateHeader, OperationLogList, RetryButton | SyncController | ObserveSyncQueue, RetryFailedOps |
| ConflictResolver (Phase 2) | DiffViewLite, ChoiceButtons | SyncConflictController | ResolveConflict |

---

## 4) Каталог UI‑компонентов (минимальный набор)

### Scaffold / Layout
- AdaptiveScaffold
- AppNavBar / AppNavRail
- StatusBanner (offline / syncing / error)

### Library / Book
- BookCard
- LibraryToolbar (поиск/сортировка/импорт)
- ChapterListItem (с прогрессом)

### Reader
- ReaderToolbar (TOC, Search, Aa, AI, Bookmark)
- ReaderTextView (обертка над epub/pdf)
- ReaderSelectionMenu (Highlight / Note / Explain / Add-to-KG)
- TocDrawer / TocSheet
- ReaderSettingsSheet (шрифт/размер/тема/режим прокрутки)
- SearchInBookSheet

### Notes
- NoteCard (quote + note + tags + jump)
- NoteEditor (multiline + autosave debounce)
- TagChipsRow

### AI
- AiPanel (tabs: Summary / Explain / Q&A / Links*)
- AiResultCard (кеш/дата/источник: глава/фрагмент)

---

## 5) Провайдеры Riverpod (скелет)

- libraryControllerProvider
- bookDetailsControllerProvider(bookId)
- readerControllerProvider(bookId)
- readerUiStateProvider (overlay/selection)
- notesControllerProvider(filter)
- noteEditorControllerProvider(context)
- globalSearchControllerProvider
- syncControllerProvider
- settingsControllerProvider
- aiControllerProvider(scope: chapter|selection|note)

---

## 6) Порядок реализации (MVP)

1. AppShell + Library + Import
2. Reader (открытие, TOC, сохранение позиции)
3. Highlight + CreateNoteSheet + NotesScreen
4. SearchInBook + GlobalSearch (локально)
5. AI Panel: summary главы/выделения + кеширование
6. SyncStatus (индикаторы/очередь), конфликты — Phase 2

---

## Связанные документы

- `docs/design_app.md` — дизайн‑концепция и UX‑правила
- `docs/ui_states_and_entities.md` — макеты состояний и минимальные Entities/DTO
