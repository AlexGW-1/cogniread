# Технологические решения

## Клиент
- Flutter — единая кодовая база для mobile/desktop, стабильный рендеринг, быстрая разработка.

## File picker (desktop)
- file_picker — кроссплатформенный выбор файлов, поддержка macOS/Windows/Linux без кастомного native кода.

## Пути хранения (app-managed)
- path_provider — доступ к sandbox/app-managed директориям для копирования EPUB и служебных файлов.

## EPUB parsing
- epubx — парсинг EPUB с извлечением базовых метаданных (title/author) без тяжелого рендеринга.

## EPUB rendering (MVP0/1)
- epubx + WebView — рендер на основе HTML в WebView с контролем якорей и позиций.

## Формат позиции/заметок (epubx + WebView)
- `readingPosition`: `chapterId`/`chapterHref`, `anchorId`/`cfi`, `offset` (int), `updatedAt`.
- `progress`: `percent` (0..1), `chapterIndex`, `totalChapters`, `updatedAt`.
- `lastOpenedAt`: timestamp для сортировки/“продолжить чтение”.
- `notes[]`: `id`, `bookId`, `anchorId`/`cfi`, `excerpt`, `noteText`, `createdAt`, `updatedAt`.
- `highlights[]`: `id`, `bookId`, `anchorId`/`cfi`, `excerpt`, `color`, `createdAt`, `updatedAt`.
- `bookmarks[]`: `id`, `bookId`, `anchorId`/`cfi`, `label`, `createdAt`.

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
- WebSockets + Supabase — реалтайм‑канал синхронизации между устройствами.

## DevOps и наблюдаемость
- Docker + GitHub Actions — воспроизводимые окружения и CI/CD.
- Grafana + Sentry — метрики и ошибки для эксплуатации.

## Ключевые альтернативы и причины отказа
- React Native — хуже рендеринг больших текстов/книг.
- Django REST — менее гибок, чем NestJS в крупной модульной системе.
- Pinecone — высокая стоимость при долгосрочном использовании.
- Firebase — хорош для MVP, но слабее при масштабе и сложной архитектуре.
