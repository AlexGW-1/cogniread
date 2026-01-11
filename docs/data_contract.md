# Data Contract

Документ фиксирует текущие структуры данных, сохраняемые в локальном хранилище.

## Общие правила
- Все даты хранятся как строка ISO-8601 (`DateTime.toIso8601String()`).
- `id` — стабильный уникальный идентификатор записи.
- `bookId` ссылается на `LibraryEntry.id`.
- `anchor` может быть `null`, формат: `chapterHref|offset` (+ optional `|fragment`).
- Разделитель `|` и обратный слэш `\` экранируются обратным слэшем.
- `updatedAt` не меньше `createdAt`.

## LibraryEntry

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| id | String | yes | Уникальный ID книги. Сейчас совпадает с fingerprint. |
| title | String | yes | Заголовок книги. |
| author | String | no | Автор (если найден). |
| localPath | String | yes | Путь к локальной копии EPUB. |
| coverPath | String | no | Путь к сохраненной обложке. |
| addedAt | String (ISO-8601) | yes | Дата добавления. |
| fingerprint | String | yes | SHA-256 хэш файла. |
| sourcePath | String | yes | Исходный путь файла. |
| readingPosition | ReadingPosition | yes | Последняя позиция чтения. |
| progress | ReadingProgress | yes | Прогресс чтения. |
| lastOpenedAt | String (ISO-8601) | no | Последнее открытие. |
| notes | List<Note> | yes | Заметки. |
| highlights | List<Highlight> | yes | Выделения. |
| bookmarks | List<Bookmark> | yes | Закладки. |
| tocOfficial | List<TocNode> | yes | Оглавление из EPUB. |
| tocGenerated | List<TocNode> | yes | Сгенерированное оглавление. |
| tocMode | String | yes | `official` или `generated`. |

## ReadingPosition

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| chapterHref | String | no | Ссылка на главу (или `index:N`). |
| anchor | String | no | Якорь внутри главы. |
| offset | int | no | Смещение в пикселях внутри главы. |
| updatedAt | String (ISO-8601) | no | Дата обновления позиции. |

## ReadingProgress

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| percent | double | no | Процент прочитанного (0..100). |
| chapterIndex | int | no | Текущая глава (индекс). |
| totalChapters | int | no | Всего глав. |
| updatedAt | String (ISO-8601) | no | Дата обновления прогресса. |

## Note

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| id | String | yes | Уникальный ID заметки. |
| bookId | String | yes | ID книги. |
| anchor | String | no | Якорь позиции. |
| endOffset | int | no | Конечный offset заметки. |
| excerpt | String | yes | Выдержка из текста. |
| noteText | String | yes | Текст заметки. |
| color | String | yes | Цвет заметки (строка). |
| createdAt | String (ISO-8601) | yes | Дата создания. |
| updatedAt | String (ISO-8601) | yes | Дата обновления. |

## Highlight

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| id | String | yes | Уникальный ID выделения. |
| bookId | String | yes | ID книги. |
| anchor | String | no | Якорь позиции. |
| excerpt | String | yes | Выдержка из текста. |
| color | String | yes | Цвет выделения (строка). |
| createdAt | String (ISO-8601) | yes | Дата создания. |
| updatedAt | String (ISO-8601) | yes | Дата обновления. |

## Bookmark

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| id | String | yes | Уникальный ID закладки. |
| bookId | String | yes | ID книги. |
| anchor | String | no | Якорь позиции. |
| label | String | yes | Название/ярлык. |
| createdAt | String (ISO-8601) | yes | Дата создания. |

## Ссылки
- Структура `TocNode`: `lib/src/core/types/toc.dart`.
