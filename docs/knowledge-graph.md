# Knowledge Graph (M4-3) — прототип

**Issue:** M4-3  
**Статус:** planned  
**Цель:** прототип слоя Knowledge Graph для объединения книг, выделений, заметок и результатов работы ИИ, а также Obsidian-подобных сценариев навигации (backlinks, graph view) с фокусом на чтение.

---

## 1. Зачем нужен Knowledge Graph

Knowledge Graph — это слой “смысловой навигации” над библиотекой и заметками, который:

- связывает **источники** (Book/Chapter/Location) с **артефактами чтения** (Highlight/Note) и **ИИ-результатами** (Summary/Insight/Suggested links);
- обеспечивает Obsidian-подобные сценарии: **outgoing links**, **backlinks**, **graph view**, “страницы сущностей” (concept page / book page);
- формирует основу для рекомендаций и “маршрутов” по знаниям на следующих фазах.

Ключевой принцип: **PostgreSQL — источник истины** для редактируемых пользователем данных, **Neo4j — производная проекция** для графовых запросов и визуализации, **Qdrant — семантический слой** для эмбеддингов/поиска/подсказок.

---

## 2. Obsidian-подобные функции (ограниченный набор под чтение)

### 2.1 Links & Backlinks
- Любая **Note** может ссылаться на **Concept**, другую **Note**, **Highlight**, **Book/Chapter**.
- Для каждой сущности доступны:
  - **Outgoing links** (куда ссылается),
  - **Backlinks** (кто ссылается на неё).

### 2.2 Graph view
- Визуальный граф с фильтрами:
  - текущая книга,
  - текущий binder/project,
  - типы узлов (concepts/notes/highlights/ai),
  - период времени.

### 2.3 “Страницы” сущностей
- **Concept page**: описание/синонимы, связанные highlights/notes/books, AI-insights.
- **Book page**: оглавление, ключевые концепты, summaries по главам, карта заметок.
- **Highlight page**: контекст (глава/позиция), связанные заметки, авто-концепты/подсказки.

### 2.4 Теги
- Теги — пользовательский слой классификации для Notes/Concepts/Highlights/Books/Chapters.

---

## 3. Binder и Project (рекомендуется добавить)

### 3.1 Binder (сборник / коллекция)
**Binder** — курируемая коллекция сущностей: “Стоицизм”, “Онбординг в домен”, “Лучшие цитаты 2026”.

- Содержит ссылки на: Book/Chapter/Note/Highlight/Concept/AIArtifact
- Нужен для:
  - тематических подборок,
  - быстрых ограничений графа,
  - “рабочих папок без папок”.

### 3.2 Project (рабочая область с целью)
**Project** — binder с дополнительными свойствами: goal/status/due_at, вопросы, ожидаемый результат.

**Рекомендуемая реализация v0:** `Project` как подтип `Binder` (одна сущность с расширенными полями), чтобы не раздувать модель и UI.

---

## 4. Модель данных графа (v0)

### 4.1 Узлы (labels)
Обязательные:
- `Book`, `Chapter`
- `Highlight`
- `Note`
- `Concept`
- `Tag`
- `AIArtifact` + подтипы: `Summary`, `AIInsight` (в прототипе достаточно этих двух)

Опционально (но рекомендуется в M4-3 минимально):
- `Binder` (+ `Project` как подтип)

Все узлы и связи должны быть мульти-тенантными: иметь `user_id` (и при необходимости `tenant_id`) и стабильные идентификаторы из PostgreSQL.

### 4.2 Связи (relationship types)
Источник / структура:
- `(Book)-[:CONTAINS]->(Chapter)`
- `(Chapter)-[:HAS_HIGHLIGHT]->(Highlight)`

Аннотации / ссылки:
- `(Note)-[:ABOUT]->(Highlight|Chapter|Book|Concept|Note)`
- `(Note)-[:MENTIONS {source, confidence}]->(Concept)`  
  - `source`: `user|ai|import`  
  - `confidence`: `0..1` (для ai)

Семантика:
- `(Chapter)-[:MENTIONS {source, confidence}]->(Concept)`
- `(Concept)-[:RELATED_TO {weight, reason, source, confidence}]->(Concept)`

ИИ-артефакты:
- `(Summary)-[:SUMMARIZES]->(Chapter|Book)`
- `(AIInsight)-[:DERIVED_FROM]->(Highlight|Note|Chapter|Book|Summary)`
- `(AIInsight)-[:SUGGESTS_LINK {confidence}]->(Concept|Note|Highlight)` (как механизм подсказок)

Коллекции:
- `(Binder)-[:INCLUDES]->(Book|Chapter|Note|Highlight|Concept|AIArtifact)`

Теги:
- `(Tag)-[:TAGS]->(Note|Concept|Highlight|Book|Chapter)`  
  (направление не принципиально, важно единообразие)

---

## 5. Где что хранить (Persistence)

### 5.1 PostgreSQL (Source of Truth)
Храним редактируемые сущности:
- библиотека (books), главы/позиции, прогресс чтения;
- highlights (text + ranges + location/cfi/offset);
- notes (markdown), ссылки (явные), теги;
- binders/projects;
- AI-jobs и AI-results (в виде записей/документов, чтобы можно было воспроизвести/переиндексировать).

### 5.2 Neo4j (Graph projection)
Храним производную графовую проекцию для:
- backlinks/outgoing links,
- graph view и обход графа,
- быстрых “карта книги / карта проекта”.

**Важно:** Neo4j не редактируется напрямую из UI. Он обновляется событиями/хендлерами, идемпотентно.

### 5.3 Qdrant (Semantic)
Эмбеддинги для:
- chunk’ов глав,
- notes,
- highlights,
- concepts (каноническая формулировка + синонимы),
- (опционально) summaries/insights.

---

## 6. Пайплайн обновления графа (идемпотентно)

### 6.1 Логические события
- `BookImported`
- `HighlightsExtracted`
- `NoteCreated/Updated/Deleted`
- `AIArtifactCreated` (summary/insight)
- `ConceptsExtracted`
- `LinksSuggested`
- `BinderUpdated`

### 6.2 Идемпотентные upsert-операции
Каждое событие должно применяться повторно без побочных эффектов:
- `MERGE` по `(user_id, <entity_id>)` для узлов
- `MERGE` для рёбер с установкой метаданных (`source`, `confidence`, `updated_at`)

### 6.3 Разделение “ручного” и “авто”
- Все AI-связи помечаются `source='ai'` и имеют `confidence`.
- UI показывает “подтвержденные” (user) и “рекомендованные” (ai) отдельными слоями.

---

## 7. Scope M4-3 (прототип)

### 7.1 Что делаем
1) Граф сущностей для **одной книги**:
   - Book, Chapters, Highlights, Notes
2) Backlinks для **Note** и **Concept**
3) Извлечение концептов (AI):
   - из chapter chunks,
   - из note text (AI + простая эвристика `[[...]]` как явные ссылки)
4) Graph view (минимальный):
   - фильтр “текущая книга”
5) Binder (минимальный):
   - создать binder,
   - добавить book/note в binder,
   - фильтровать граф по binder

### 7.2 Критерии готовности (Acceptance Criteria)
- Создали highlight и note → в графе есть узлы и связи `Chapter -> Highlight`, `Note -> ABOUT -> Highlight`
- В карточке Note отображаются:
  - outgoing links (concepts),
  - backlinks (кто ссылается на note / concepts)
- AI summary для главы создаёт `Summary` и связь `SUMMARIZES`
- AI extraction создаёт `Concept` и связь `MENTIONS (source=ai, confidence=...)`
- Binder ограничивает граф и списки сущностей (scope “только внутри binder”)

---

## 8. Примеры запросов Neo4j (ориентиры)

### 8.1 Backlinks к Concept (notes → concept)
```cypher
MATCH (n:Note {user_id:$userId})-[r:MENTIONS]->(c:Concept {concept_id:$conceptId, user_id:$userId})
RETURN n, r
ORDER BY coalesce(r.confidence, 1.0) DESC;
```

### 8.2 “Карта книги”: топ-концепты книги
```cypher
MATCH (b:Book {book_id:$bookId, user_id:$userId})-[:CONTAINS]->(ch:Chapter)-[m:MENTIONS]->(c:Concept {user_id:$userId})
RETURN c, count(*) AS freq, avg(coalesce(m.confidence, 1.0)) AS avg_conf
ORDER BY freq DESC
LIMIT 50;
```

### 8.3 Ограничение по Binder
```cypher
MATCH (bd:Binder {binder_id:$binderId, user_id:$userId})-[:INCLUDES]->(x)
RETURN x;
```

---

## 9. UX-заметки (для прототипа)

- По умолчанию показывать **только подтверждённые** связи.
- “AI-рекомендации” — отдельный переключатель/слой.
- Graph view — второй экран после привычных списков/поиска.
- Для Concept page: показывать “best evidence” (highlights/notes) + summary.

---

## 10. Риски и меры

1) **Дубли концептов** (Stoicism vs stoicism)  
   → `concept_key = normalize(title)` и `MERGE` по `(user_id, concept_key)`.

2) **Шум от AI-связей**  
   → порог `confidence`, отдельный слой “AI links”, возможность “принять/отклонить”.

3) **Рассинхронизация Postgres ↔ Neo4j ↔ Qdrant**  
   → событийная модель + идемпотентные хендлеры + возможность rebuild projection для книги/binder.

4) **Binder/Project усложняет UX**  
   → “Без проекта” по умолчанию; binder/project — опционально как рабочие области.

---

## 11. Будущие расширения (после M4-3)

- “Пути знаний”: traversal от книги к концептам и обратно к доказательствам (highlights/notes)
- Автогенерация “Concept page” (definition + linked evidence)
- Рекомендации по связям (ai) + полуавтоматическое подтверждение
- Экспорт в Obsidian-compatible markdown (links, frontmatter, backlinks)
