# API Contracts — Ежедневник

**Версия:** 0.1  
**Статус:** accepted (D-019, D-020)  
**Базовый префикс:** `/api/v1`

## 1. Общие правила

- Формат — JSON UTF-8, поля — `camelCase`.
- Время — ISO-8601 UTC (`2026-11-05T20:30:00Z`).
- Идентификаторы — UUID.
- Аутентификация — `Authorization: Bearer <accessToken>`.
- Все пользовательские данные защищены TLS.
- Запросы без валидного access token получают `401`.
- Ответы об ошибках имеют единый формат:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Проверьте заполнение полей",
    "requestId": "uuid",
    "details": { "field": "message" }
  }
}
```

- `details` и `requestId` могут отсутствовать.
- Пользовательские данные не попадают в сообщения об ошибках и логи.

## 2. Ограничения

| Ограничение | Значение |
|---|---|
| Операций в одном push | до 100 |
| Размер push-запроса | до 1 MiB |
| Страница pull | по умолчанию 200, максимум 500 |
| Access token | 15 минут |
| Refresh token | 30 дней |
| Повтор refresh | ротация; повтор старого токена отзывает устройство |
| Снимок устройства | до 256 MiB |

Точные лимиты могут быть уменьшены конфигурацией сервера.

## 3. Аутентификация

### 3.1. Создание первого владельца

```http
POST /api/v1/auth/setup
X-Setup-Token: <server setup token>
Content-Type: application/json
```

```json
{
  "email": "owner@example.com",
  "password": "<secret>",
  "device": {
    "id": "uuid",
    "name": "MacBook Pro",
    "platform": "MACOS"
  }
}
```

Ответ `201 Created` — `AuthResponse`.

Правила:

- доступен только при отсутствии пользователей в БД;
- пароль — от 12 до 128 символов;
- при повторном вызове — `409 SETUP_ALREADY_COMPLETED`;
- неверный setup token — `401 SETUP_TOKEN_INVALID`;
- `device.id` генерируется клиентом и постоянно закрепляется за устройством;
- открытая регистрация после создания владельца запрещена.

### 3.2. Вход

```http
POST /api/v1/auth/login
Content-Type: application/json
```

Тело — `AuthRequest`. Ответ `200 OK` — `AuthResponse`.

Неверная пара email/пароль — `401 INVALID_CREDENTIALS`.
Заблокированный пользователь — `403 FORBIDDEN`.

### 3.3. Обновление сессии

```http
POST /api/v1/auth/refresh
```

```json
{ "refreshToken": "<opaque>" }
```

Ответ `200 OK` — новый `AuthResponse`. Старый refresh token отзывается.
Повторное использование старого токена отзывает устройство и возвращает
`401 REFRESH_TOKEN_INVALID`.

### 3.4. Выход

```http
POST /api/v1/auth/logout
```

```json
{ "refreshToken": "<opaque>" }
```

Ответ `204 No Content`. Повторный logout идемпотентен.

### 3.5. AuthResponse

```json
{
  "userId": "uuid",
  "deviceId": "uuid",
  "accessToken": "<jwt>",
  "accessExpiresAt": "2026-11-05T20:45:00Z",
  "refreshToken": "<opaque>",
  "refreshExpiresAt": "2026-12-05T20:30:00Z"
}
```

## 4. Устройства

### 4.1. Список устройств

```http
GET /api/v1/devices
```

```json
[
  {
    "id": "uuid",
    "name": "MacBook Pro",
    "platform": "MACOS",
    "createdAt": "2026-11-01T10:00:00Z",
    "lastSeenAt": "2026-11-05T20:30:00Z",
    "revokedAt": null
  }
]
```

### 4.2. Отзыв устройства

```http
DELETE /api/v1/devices/{deviceId}
```

Ответ `204 No Content`. После отзыва access и refresh токены устройства
недействительны. Нельзя отозвать последнее активное устройство без
отдельного подтверждения — правило серверной политики.

## 5. Синхронизация

### 5.1. Состояние

```http
GET /api/v1/sync/state
```

```json
{
  "protocolVersion": 1,
  "serverTime": "2026-11-05T20:30:00Z",
  "latestChangeSeq": 128,
  "deviceId": "uuid"
}
```

### 5.2. Push

```http
POST /api/v1/sync/push
Authorization: Bearer <access>
Content-Type: application/json
```

```json
{
  "operations": [
    {
      "operationId": "uuid",
      "deviceId": "uuid",
      "entityType": "NOTE",
      "entityId": "uuid",
      "operationType": "UPDATE",
      "baseRevision": 3,
      "clientTimestamp": "2026-11-05T20:30:00Z",
      "payload": {
        "title": "Заметка",
        "contentMarkdown": "# Текст",
        "categoryId": "work",
        "deletedAt": null
      }
    }
  ]
}
```

Правила:

- `operationId` уникален; повтор с тем же телом — `DUPLICATE`;
- повтор с тем же `operationId` и другим телом — `REJECTED`;
- `CREATE` — `baseRevision` отсутствует или `null`;
- `UPDATE` и `DELETE` — `baseRevision` обязательна;
- `payload` для `CREATE`/`UPDATE` — полный снимок изменяемых полей;
- `payload` для `DELETE` не требуется;
- `clientTimestamp` используется для аудита, но не для порядка;
- каждая операция обрабатывается отдельной транзакцией;
- частичный успех пакета допустим;
- текущая реализация синхронизирует `NOTE`, `TASK`, `LANE` и `REMINDER`;
  остальные типы возвращают `REJECTED UNSUPPORTED_ENTITY`.

Payload `TASK`:

```json
{
  "title": "Подготовить план",
  "description": "Описание",
  "laneId": "uuid",
  "systemState": "ACTIVE",
  "categoryId": "work",
  "priority": "HIGH",
  "plannedStartAt": "2026-11-06T09:00:00Z",
  "plannedEndAt": "2026-11-08T18:00:00Z",
  "actualStartAt": null,
  "actualEndAt": null
}
```

`systemState` — `ACTIVE` или `CANCELLED`; отмена не является дорожкой.
Приоритет — `LOW`, `NORMAL` или `HIGH`.

Payload `LANE`:

```json
{
  "name": "В работе",
  "sortOrder": 1
}
```

Дорожки по умолчанию имеют стабильные ID и создаются на сервере
при setup, а на клиенте — при инициализации локальной БД.
Удаление непустой дорожки возвращает `REJECTED LANE_NOT_EMPTY`.

Payload `REMINDER`:

```json
{
  "taskId": "uuid",
  "remindAt": "2026-11-06T14:00:00Z"
}
```

У задачи может быть одно активное напоминание; повторное создание
возвращает `REJECTED REMINDER_EXISTS`. `remindAt` хранится в UTC.

Ответ `200 OK`:

```json
{
  "results": [
    {
      "operationId": "uuid",
      "status": "APPLIED",
      "entityId": "uuid",
      "revision": 4,
      "changeSeq": 129
    },
    {
      "operationId": "uuid",
      "status": "CONFLICT",
      "entityId": "uuid",
      "revision": 9,
      "serverEntity": { "...": "полный снимок" }
    },
    {
      "operationId": "uuid",
      "status": "REJECTED",
      "code": "VALIDATION_ERROR",
      "message": "Заголовок обязателен"
    }
  ]
}
```

Статусы:

| Статус | Значение |
|---|---|
| `APPLIED` | операция применена, выданы revision и changeSeq |
| `DUPLICATE` | operationId уже обработан |
| `CONFLICT` | baseRevision не совпала; возвращён серверный снимок |
| `REJECTED` | операция отклонена; код и сообщение |

### 5.3. Pull

```http
GET /api/v1/sync/pull?cursor=0&limit=200
Authorization: Bearer <access>
```

```json
{
  "changes": [
    {
      "seq": 129,
      "entityType": "NOTE",
      "entityId": "uuid",
      "operationId": "uuid",
      "operationType": "UPDATE",
      "revision": 4,
      "originDeviceId": "uuid",
      "changedAt": "2026-11-05T20:30:01Z",
      "payload": { "...": "полный снимок" }
    },
    {
      "seq": 130,
      "entityType": "NOTE",
      "entityId": "uuid",
      "operationType": "DELETE",
      "revision": 3,
      "originDeviceId": "uuid",
      "changedAt": "2026-11-05T20:31:00Z",
      "payload": { "deletedAt": "2026-11-05T20:31:00Z" }
    }
  ],
  "nextCursor": "130",
  "hasMore": false
}
```

Правила:

- `cursor` — непрозрачная строка; начальное значение `0`;
- изменения возвращаются по возрастанию `seq`;
- tombstones включаются;
- собственные изменения устройства также возвращаются;
- `nextCursor` сохраняется только после успешного применения страницы;
- при ошибке применения cursor не меняется;
- `hasMore=true` требует повторного pull.

## 6. Ошибки

| HTTP | Код | Когда |
|---|---|---|
| 400 | `VALIDATION_ERROR` | неверная структура запроса или поля |
| 401 | `UNAUTHENTICATED` | нет или истёк access token |
| 401 | `INVALID_CREDENTIALS` | неверный email/пароль |
| 401 | `REFRESH_TOKEN_INVALID` | refresh недействителен или повторно использован |
| 401 | `SETUP_TOKEN_INVALID` | неверный setup token |
| 403 | `FORBIDDEN` | нет доступа к объекту |
| 404 | `NOT_FOUND` | объект или устройство не найдены |
| 409 | `SETUP_ALREADY_COMPLETED` | владелец уже создан |
| 409 | `CONFLICT` | конфликт на уровне запроса |
| 413 | `PAYLOAD_TOO_LARGE` | превышен размер пакета |
| 429 | `RATE_LIMITED` | превышен лимит запросов |
| 500 | `INTERNAL_ERROR` | внутренняя ошибка |

Ошибки отдельных операций передаются в `results[].code` и не меняют
HTTP-статус всего пакета.

## 7. Повторные запросы

- Сетевые ошибки, `429` и `5xx` повторяются с экспоненциальной задержкой.
- `400`, `401`, `403`, `404`, `409`, `413` автоматически не повторяются,
  кроме обновления токена и разрешения конфликта пользователем.
- Повтор push безопасен благодаря `operationId`.
- Повтор pull безопасен: страница применяется идемпотентно.

## 8. Вложения

Файлы хранятся на сервере в `ATTACHMENTS_DIR`, метаданные — в PostgreSQL.
Лимит — 25 МБ; разрешены изображения, PDF, текст/Markdown и MP3/M4A.
Сервер проверяет расширение, MIME, сигнатуру и SHA-256.

### 8.1. Загрузка

```http
POST /api/v1/attachments/{attachmentId}
Authorization: Bearer <access>
Content-Type: multipart/form-data
```

Поля формы: `ownerType` (`NOTE`/`TASK`), `ownerId`, `file`.
Повторная загрузка с тем же ID и хешем идемпотентна. Другой хеш —
`409 ATTACHMENT_EXISTS`.

### 8.2. Скачивание

```http
GET /api/v1/attachments/{attachmentId}
Authorization: Bearer <access>
```

Возвращает содержимое файла с исходным MIME-типом и именем.
Метаданные распространяются через change log при pull.

### 8.3. Удаление

```http
DELETE /api/v1/attachments/{attachmentId}
Authorization: Bearer <access>
```

Создаёт tombstone и удаляет файл. Повторное удаление безопасно.

## 9. Резервные копии

Копии создаются вручную. Сервер хранит архивы и снимки устройств
на отдельном диске `BACKUP_DIR`; архивы шифруются `age`.
Все методы требуют `Authorization: Bearer <access>`.

### 9.1. Статус и история

```http
GET /api/v1/backups/status
GET /api/v1/backups
```

Ответ содержит:

- `configured`, `configError`;
- `state`: `running`, `operation`, `lastAttemptAt`, `lastSuccessAt`,
  `lastVerifiedAt`, `lastError`;
- `archives`: id, fileName, createdAt, finishedAt, sizeBytes, sha256,
  status (`SUCCESS`/`VERIFIED`), verifiedAt, schemaVersion, counts;
- `devices`: deviceId, snapshotCount, latest snapshot;
- `disk`: freeBytes, totalBytes;
- `retention`: recent, weekly, monthly, deviceSnapshots.

### 9.2. Запуск копии

```http
POST /api/v1/backups
```

Возвращает `202 Accepted` и текущий статус. Одновременно выполняется
только одна операция. Если сервер не настроен — `503
BACKUP_NOT_CONFIGURED`; если операция уже идёт — `409 BACKUP_RUNNING`.

Сервер выполняет `pg_dump`, добавляет вложения и последние снимки
устройств в ZIP, шифрует `age`, проверяет SHA-256, manifest и
`pg_restore --list`, затем применяет политику хранения.

### 9.3. Проверка копии

```http
POST /api/v1/backups/{id}/verify
```

Расшифровывает архив, проверяет manifest, SHA-256 файлов и читаемость
дампа. Возвращает обновлённую запись архива. Рабочие данные не меняет.

### 9.4. Скачивание архива

```http
GET /api/v1/backups/{id}/download
```

Возвращает зашифрованный файл `.zip.age` для офлайн-копии или
восстановления через CLI.

### 9.5. Снимок устройства

```http
POST /api/v1/backups/devices
Authorization: Bearer <access>
Content-Type: multipart/form-data
```

Поля формы: `sha256` (hex), `schemaVersion`, `file` (SQLite-снимок).
Сервер проверяет размер до 256 MiB, заголовок SQLite, SHA-256 и
принадлежность устройства текущей сессии. Повтор с тем же SHA-256
идемпотентен. Снимок шифруется `age` сразу при приёме; хранятся
последние 3 снимка на устройство. Токены и secure storage в снимок
не входят.

### 9.6. Ошибки

- `503 BACKUP_NOT_CONFIGURED` — нет ключа, `age`, `pg_dump`/`pg_restore`
  или недостаточно места;
- `409 BACKUP_RUNNING` — уже выполняется backup или проверка;
- `413 PAYLOAD_TOO_LARGE` — снимок больше лимита;
- `400 VALIDATION_ERROR` — неверный SHA-256, схема или не SQLite.

## 10. Безопасность

- TLS обязателен.
- Access token не логируется.
- Refresh token хранится в БД только как хэш.
- Проверка владельца выполняется на сервере для каждой операции.
- Rate limiting применяется к auth и sync.
- Размер тела запроса ограничен.
- Содержимое заметок и вложений не пишется в технические логи.
