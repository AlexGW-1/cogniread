# Окончательный выбор техностека

Этот документ фиксирует утверждённый финальный технологический стек (Target) и текущий фактический стек (Current).

## Current (MVP0–MVP3)

| Компонент | Технология |
| --- | --- |
| Frontend | Flutter |
| Локальная БД | Hive |
| Локальное хранилище файлов | app‑managed storage (path_provider) |
| Рендер книги | нативный Flutter (ScrollablePositionedList + SelectableRegion) |
| Синхронизация | отсутствует (только локальный event log) |
| Backend API | отсутствует |
| AI‑сервисы | отсутствуют |

## Target (финальный стек)

| Компонент | Технология |
| --- | --- |
| Frontend | Flutter |
| Backend API | NestJS |
| AI-сервисы | FastAPI + LangChain |
| Реляционная БД | PostgreSQL |
| Vector DB | Qdrant |
| Graph DB | Neo4j |
| Хранилище файлов | S3-compatible |
| Синхронизация | WebSockets + собственный sync‑gateway |
| DevOps | Docker + GitHub Actions + Grafana + Sentry |

## Архитектурная диаграмма

![final_tech_stack diagram] assets/final_tech_stack_01.png

## Обоснование выбора

Техностек выбран по критериям: производительность, масштабируемость, зрелость экосистемы, стоимость разработки и удобство длительной поддержки.

## Рассмотренные альтернативы

- React Native — недостаточно хорош в рендеринге книг.
- Django Rest — уступает гибкости NestJS.
- Pinecone — дорого для долгосрочного использования.
- Firebase — отличен для MVP, но слаб в масштабе.

## Roadmap (6–12 месяцев)

Target‑roadmap:
Phase 1: MVP читалки + загрузка книг + базовое ИИ‑саммари
Phase 2: Персональная база знаний + граф связей
Phase 3: Расширенные ИИ‑объяснения + улучшенная аналитика
Phase 4: Полноценный knowledge graph + рекомендации
Phase 5: Офлайн‑модель ИИ для устройства
