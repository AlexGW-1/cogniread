# План следующих этапов (Draft)

Формат: **1 issue ≈ 1 PR ≈ 1 день**.  
Статусы: `done` / `planned`. PR указывается, если известен; иначе `—`.

Шаблон Issue (для GitHub):
```
## Context

## Checklist
- [ ]

## Acceptance Criteria
- [ ]

## Test Plan
- [ ]
```

## Milestone M1 — Глобальные разделы и UX
Цель: сделать удобные глобальные разделы и довести поиск/заметки до “пользовательского качества”.

### M1-1 Global Search v2 (FTS-индекс, диагностика, rebuild)
Issue ID: `M1-1`
Статус: `done` • PR: —  
Scope: см. `docs/search_global_v2.md`.

Acceptance Criteria:
- Полнотекст по книгам/заметкам/выделениям.
- Jump-to-location в Reader.
- Диагностика + rebuild индекса.

Test Plan:
- Поиск по 2–3 книгам, переход в Reader.
- Перестроить индекс, убедиться, что ошибки понятны.

### M1-2 Global Notes/Highlights v1
Issue ID: `M1-2`
Статус: `planned` • PR: —  
Scope: см. `docs/notes_screen_v1.md`.

Checklist:
- Глобальный список notes/highlights с поиском и фильтрами.
- Группировка по книгам + лента.
- Free notes (без книги) + синхронизация.
- Массовые действия: экспорт/удаление.

Acceptance Criteria:
- Раздел “Заметки” не placeholder.
- Поиск/фильтры работают; переход в Reader по anchor.

Test Plan:
- Создать 3–5 заметок/выделений в разных книгах.
- Проверить поиск и фильтры, открыть пару элементов в Reader.

### M1-3 Закладки: несколько на книгу + управление
Issue ID: `M1-3`
Статус: `planned` • PR: —

Checklist:
- Хранить список закладок, а не одну.
- UI списка + удаление/переименование.
- Навигация в Reader по anchor.

Acceptance Criteria:
- Можно создать 3+ закладок в одной книге.
- Удаление не ломает текущую позицию чтения.

Test Plan:
- Создать/удалить/переименовать закладки, перейти по ним.

### M1-4 Экспорт заметок/выделений (JSON + Markdown)
Issue ID: `M1-4`
Статус: `planned` • PR: —

Checklist:
- Экспорт выбранных элементов в zip (`notes.json`, `notes.md`).
- Включить метаданные книги и anchor.

Acceptance Criteria:
- Экспорт создается, структура совпадает с PRD.

Test Plan:
- Экспорт 5 элементов, проверить содержимое файлов.

### M1-5 Обновление тест-плана под новые разделы
Issue ID: `M1-5`
Статус: `planned` • PR: —

Checklist:
- Обновить `docs/test_plan_stage1_sync.md` при изменениях синка.
- Добавить тест-план для Notes/Global Search (если нет).

Acceptance Criteria:
- Есть воспроизводимые ручные сценарии.

---
## Milestone M2 — Стабилизация синхронизации
Цель: повысить надежность и прозрачность file-based sync без изменения модели данных.

### M2-1 Статусы синка и понятные ошибки
Issue ID: `M2-1`
Статус: `planned` • PR: —

Checklist:
- Ясные состояния: success/error/paused.
- Тексты ошибок без утечек секретов.

### M2-2 Retry/backoff и лимиты API
Issue ID: `M2-2`
Статус: `planned` • PR: —

Checklist:
- Экспоненциальный backoff на сетевые ошибки.
- Раздельные таймауты request/transfer.

### M2-3 Диагностика и метрики
Issue ID: `M2-3`
Статус: `planned` • PR: —

Checklist:
- Время синка, объемы данных, счетчики ошибок.
- Экспорт отчета для поддержки.

### M2-4 Client-side шифрование (опционально)
Issue ID: `M2-4`
Статус: `planned` • PR: —

Checklist:
- Шифрование sync-файлов по паролю/ключу.
- Безопасное хранение ключа на устройстве.

### M2-5 Google Drive/OneDrive: решение и план
Issue ID: `M2-5`
Статус: `planned` • PR: —

Checklist:
- Решение по OAuth/UX подключения.
- Подготовка acceptance criteria и тест-плана.
Ссылки: `docs/deferred_features.md`.

---
## Milestone M3 — Stage 2: Sync Gateway (backend)
Цель: собственный backend с курсорной синхронизацией и realtime каналом.

### M3-1 API scaffold + auth
Issue ID: `M3-1`
Статус: `planned` • PR: —

Checklist:
- NestJS scaffold, DTO validation, JWT guard.

### M3-2 Storage + DAO + миграции
Issue ID: `M3-2`
Статус: `planned` • PR: —

Checklist:
- Таблицы event_log и reading_position.
- Миграции и репозитории.

### M3-3 Idempotency/Dedup + ACK
Issue ID: `M3-3`
Статус: `planned` • PR: —

Checklist:
- Dedup по id.
- Ответы accepted/rejected/duplicate.

### M3-4 Pull API (cursor-based)
Issue ID: `M3-4`
Статус: `planned` • PR: —

Checklist:
- Cursor paging, лимиты, serverCursor.

### M3-5 WebSocket уведомления
Issue ID: `M3-5`
Статус: `planned` • PR: —

Checklist:
- WS endpoint, reconnect, events_available.

### M3-6 Observability + контрактные тесты
Issue ID: `M3-6`
Статус: `planned` • PR: —

Checklist:
- Метрики/логи/трейсинг.
- Contract tests по `docs/sync_gateway_api.md`.

---
## Milestone M4 — Stage 3: AI и база знаний
Цель: AI-функции поверх локальных/синхронизированных данных.

### M4-1 Summaries + Q&A
Issue ID: `M4-1`
Статус: `planned` • PR: —

### M4-2 Семантический поиск (эмбеддинги)
Issue ID: `M4-2`
Статус: `planned` • PR: —

### M4-3 Knowledge graph (прототип)
Issue ID: `M4-3`
Статус: `planned` • PR: —
