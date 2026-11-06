# Data Model — модель данных

Статус: концептуальная модель.
Окончательная схема зависит от выбранного стека и уточнения требований.

## 1. Общие правила

- Все основные сущности имеют стабильный UUID.
- Даты хранятся в однозначном формате времени.
- При необходимости сохраняется временная зона и семантика
  локального времени.
- Время создания и изменения фиксируется.
- Синхронизация использует версию/ревизию и журнал изменений.
- Удаление в распределённой системе представляется tombstone.
- Не использовать отображаемые названия как ключи связей.

## 2. Категории

categories:

- id
- name
- sort_order
- created_at
- updated_at

Начальные категории: Работа, Личное, Семья.

Категория не является статусом.

## 3. Заметки

notes:

- id
- user_id — владелец; для устаревших строк может быть null, новые строки всегда заполнены
- title
- content_markdown
- category_id
- created_at
- updated_at
- is_archived
- revision
- deleted_at

Связанные таблицы:

- note_tags
- tags
- note_links
- note_attachments (в реализации — общая `attachments` с owner_type)
- note_revisions
- note_task_links

note_revisions хранит историю версий с автором/источником
и временем.

Политика хранения истории требует уточнения.

## 4. Доска и дорожки

boards:

- id
- name
- created_at
- updated_at

Для MVP предполагается одна доска.

board_lanes:

- id
- board_id
- name
- sort_order
- is_terminal
- created_at
- updated_at

Количество дорожек: от 3 до 10.

Дорожка — рабочий статус.

Не дублировать её значением в отдельном tasks.status.

Поле is_terminal использовать только после утверждения
модели завершающей дорожки.

В реализации этапа 7 используется одна неявная доска без таблицы
`boards`: дорожки принадлежат пользователю (`board_lanes.user_id`).
Дорожки по умолчанию имеют стабильные UUID, чтобы клиент и сервер
не создавали дубликаты.

## 5. Задачи

tasks:

- id
- title
- description
- lane_id
- system_state
- category_id
- priority
- planned_start_at
- planned_end_at
- actual_start_at
- actual_end_at
- estimated_duration
- created_at
- updated_at
- revision
- deleted_at

system_state предварительно может содержать:

- active;
- cancelled;
- archived.

Значение archived требует утверждения.

Завершение через дорожку требует отдельного решения
о terminal lane.

В реализации этапа 7 используются поля `id`, `title`, `description`,
`lane_id`, `system_state` (`ACTIVE`/`CANCELLED`), `category_id`,
`priority`, `planned_start_at`, `planned_end_at`, `actual_start_at`,
`actual_end_at`, `revision`, `created_at`, `updated_at`, `deleted_at`.
История перемещений хранится на клиенте в `task_status_history`
и восстанавливается из change log по `operationId`.

Связанные таблицы:

- task_tags
- task_status_history
- task_completion_periods
- task_dependencies
- task_note_links
- task_attachments (в реализации — общая `attachments` с owner_type)
- task_time_entries
- task_reminders

В реализации этапа 11 `attachments` содержит `id`, `user_id`,
`owner_type` (`NOTE`/`TASK`), `owner_id`, `file_name`, `mime_type`,
`size_bytes`, `sha256`, `storage_key`, `revision`, timestamps и
`deleted_at`. Файл лежит в `ATTACHMENTS_DIR`, метаданные — в БД.

В реализации этапа 8 `task_reminders` содержит `id`, `task_id`,
`remind_at` (UTC), `revision`, `created_at`, `updated_at`, `deleted_at`.
Одно активное напоминание на задачу; удаление — tombstone.
Остальные дополнительные сущности не входят в MVP.

## 6. Чек-листы и задачи

Для Markdown-чек-листов необходим стабильный
checklist_item_id, не зависящий от текста пункта или его позиции.

note_task_links:

- id
- note_id
- checklist_item_id
- task_id
- link_type
- created_at

Для связанного пункта и задачи состояние должно иметь
единый источник истины — задачу.

Изменение проходит через один application service,
который обновляет локальные представления и создаёт
одну логическую операцию синхронизации.

Необходимо определить поведение, если Markdown импортирован
заново, пункт удалён или изменён его ID.

## 7. История и аудит

task_status_history:

- id
- task_id
- from_lane_id
- to_lane_id
- changed_at
- changed_by
- source

ai_action_log:

- id
- action_type
- target_type
- target_id
- proposal_payload
- approval_required
- approved_at
- execution_status
- execution_log
- created_at

Не сохранять секреты и избыточное содержимое в логах.

## 8. Пользователи, устройства и синхронизация

### 8.1. users

- id — UUID, primary key;
- email — уникальный;
- password_hash;
- status — active / disabled;
- created_at, updated_at.

Сервер персональный: открытая регистрация запрещена, первый владелец
создаётся через setup token (D-020).

### 8.2. devices

- id — UUID, primary key;
- user_id — FK users;
- name;
- platform — ANDROID / IOS / MACOS / WINDOWS;
- created_at;
- last_seen_at;
- revoked_at.

### 8.3. refresh_tokens

- id — UUID, primary key;
- user_id — FK users;
- device_id — FK devices;
- token_hash;
- expires_at;
- revoked_at;
- replaced_by — FK refresh_tokens, nullable.

### 8.4. change_log

- seq — bigserial, монотонный;
- user_id — FK users;
- entity_type;
- entity_id;
- operation_id — UUID операции;
- operation_type — CREATE / UPDATE / DELETE;
- revision — revision сущности после операции;
- payload — JSONB, полный снимок изменяемых полей;
- device_id — FK devices;
- changed_at.

Индекс: `(user_id, seq)`.

### 8.5. processed_operations

- operation_id — UUID, primary key;
- user_id — FK users;
- result — APPLIED;
- revision — revision применённой сущности;
- change_seq — nullable;
- request_hash — SHA-256 канонического тела операции;
- processed_at.

Хэш позволяет отличить повтор той же операции от повторного
использования operationId с другим телом.

Используется для идемпотентности push.

### 8.6. Доменные таблицы

notes, tasks, lanes, categories, note_links, task_note_links
хранят текущее состояние и revision. Изменение сущности и запись
в change_log выполняются в одной транзакции.

### 8.7. Локальный outbox

Клиент хранит `sync_outbox` с operation_id, entity_type, entity_id,
operation_type, base_revision, payload, created_at, attempts, last_error.
Курсор синхронизации хранится отдельно и сдвигается только после
успешного применения страницы.

Конкретные поля и индексы зафиксированы в `docs/SYNC_PROTOCOL.md`.

## 9. Вложения

Метаданные:

- ID;
- владелец/связанная сущность;
- имя;
- MIME type;
- размер;
- checksum;
- storage key;
- статус загрузки;
- время создания.

Файлы не следует хранить как большие бинарные поля
в основной таблице без отдельного обоснования.

## 9.1. Локальный журнал AI

Таблица `ai_actions` существует только в клиентской SQLite
и не синхронизируется:

- id;
- prompt;
- proposal (JSON с изменениями);
- status: `PROPOSED`, `APPLIED`, `REJECTED`, `STALE`, `FAILED`;
- message;
- error;
- created_at;
- decided_at;
- executed_at.

Журнал не содержит файлов и не заменяет историю изменений сущностей.
Предложение хранит ожидаемые `revision`/`updatedAt`, чтобы применение
устаревшего изменения было отклонено.

## 9.2. Резервные копии

Серверные резервные копии не добавляют доменных таблиц. Метаданные
хранятся рядом с архивами:

- `BACKUP_DIR/<userId>/state.json` — последняя попытка, успех,
  проверка, ошибка, признак выполнения;
- `archives/<archiveId>.json` — id, имя файла, время, размер, SHA-256,
  статус, проверка, версия схемы, counts;
- `devices/<deviceId>/<snapshotId>.json` — снимок SQLite: устройство,
  размер, SHA-256, версия схемы, время;
- `backup.lock` — защита от параллельного запуска.

Снимок устройства содержит локальную SQLite и журнал `ai_actions`.
Токены и secure storage не входят.

## 10. Проекты

Проекты не входят в MVP.

Позже можно добавить projects и nullable project_id
или связующие таблицы.

Не добавлять полноценный модуль проектов до утверждения требований.

## 11. Обязательные инварианты

- Нельзя иметь задачу без допустимой дорожки,
  если модель явно не допускает иное.
- Категория не заменяет дорожку.
- У связанного checklist item и task одно согласованное состояние.
- Удаление должно быть синхронизируемым.
- Повтор операции не создаёт вторую сущность.
- Конфликт не должен приводить к молчаливой потере версии.
- Миграции сохраняют данные либо имеют утверждённый план преобразования.
