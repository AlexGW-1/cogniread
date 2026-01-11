# Технологические решения

## Клиент
- Flutter — единая кодовая база для mobile/desktop, стабильный рендеринг, быстрая разработка.

## File picker (desktop)
- file_picker — кроссплатформенный выбор файлов, поддержка macOS/Windows/Linux без кастомного native кода.

## Пути хранения (app-managed)
- path_provider — доступ к sandbox/app-managed директориям для копирования EPUB и служебных файлов.

## EPUB parsing
- epubx — парсинг EPUB с извлечением метаданных и контента без WebView.

## EPUB rendering (MVP0/1)
- Нативный рендер текста во Flutter: извлекаем главы, строим список параграфов и отображаем через `ScrollablePositionedList` + `SelectableRegion`.

## Архитектура (текущий этап)
- До Sync MVP используем Controller + Store. Черновые слои Clean Architecture удалены, чтобы не держать дублирующий код.

## Формат позиции/заметок (native reader)
- `readingPosition`: `chapterHref`, `anchor` (string), `offset` (int), `updatedAt`.
- `progress`: `percent` (0..1), `chapterIndex`, `totalChapters`, `updatedAt`.
- `lastOpenedAt`: timestamp для сортировки/“продолжить чтение”.
- `notes[]`: `id`, `bookId`, `anchor` (string), `endOffset`, `excerpt`, `noteText`, `color`, `createdAt`, `updatedAt`.
- `highlights[]`: `id`, `bookId`, `anchor` (string), `endOffset`, `excerpt`, `color`, `createdAt`, `updatedAt`.
- `bookmarks[]`: `id`, `bookId`, `anchor` (string), `label`, `createdAt`, `updatedAt` (сейчас одна закладка на книгу).

## Позиция чтения (устойчивый формат)
- `{bookId, chapterHref | chapterIndex, fragmentId?, offsetPx?, progressPct?, updatedAt}`
  - `chapterHref` (или `chapterIndex` как fallback).
  - `fragmentId` = якорь в TOC/HTML при наличии.
  - `offsetPx` = смещение от начала главы в пикселях (fallback).
  - `progressPct` = общий прогресс по книге (fallback при больших визуальных изменениях).

## Локальное хранилище (DB/KV)
- Hive — легковесное key-value хранилище без нативных зависимостей, подходит для локальной библиотеки.

## Backend API
- NestJS — модульная архитектура, TypeScript, удобная масштабируемость и поддержка.

## AI‑сервисы
- FastAPI + LangChain — высокая скорость Python‑стека для ML, удобная оркестрация пайплайнов LLM.

## Реляционная БД
- PostgreSQL — надежная транзакционная БД для пользователей, библиотеки, заметок и метаданных.

## Vector DB
- Qdrant — self‑hosted, контролируемая стоимость, подходит для retrieval и семантического поиска.

## Graph DB
- Neo4j — зрелая графовая БД для связей знаний и рекомендаций.

## Хранилище файлов
- S3‑compatible — стандартный интерфейс для книг/обложек/экспортов, удобная интеграция.

## Синхронизация
- WebSockets + собственный sync‑gateway — реалтайм‑канал синхронизации между устройствами без изменения доменной модели.

## DevOps и наблюдаемость
- Docker + GitHub Actions — воспроизводимые окружения и CI/CD.
- Grafana + Sentry — метрики и ошибки для эксплуатации.

## Ключевые альтернативы и причины отказа
- React Native — хуже рендеринг больших текстов/книг.
- Django REST — менее гибок, чем NestJS в крупной модульной системе.
- Pinecone — высокая стоимость при долгосрочном использовании.
- Firebase — хорош для MVP, но слабее при масштабе и сложной архитектуре.
