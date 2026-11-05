# PROJECT_STATE — Ежедневник

**Обновлено:** 2026-11-06
**Текущий шаг:** Markdown-редактор заметок — завершён
**Следующий шаг:** TODO-доска (этап 7)

## 1. Статус

| Область | Статус |
|---|---|
| Документация продукта и архитектуры | ✅ |
| API и sync-протокол | ✅ описаны |
| Backend auth | ✅ реализован |
| Backend sync `NOTE` | ✅ реализован |
| Flutter-каркас (4 платформы) | ✅ |
| Локальная БД и outbox | ✅ схема v2 и миграция |
| Клиентский вход | ✅ |
| Secure storage | ✅ на macOS проверен |
| Клиентский sync `NOTE` | ✅ push/pull/cursor/tombstone/конфликты |
| Markdown-редактор заметок | ✅ создание, редактирование, автосохранение |
| Предпросмотр Markdown | ✅ заголовки, списки, чек-листы, код, ссылки |
| UI разрешения конфликтов | ⏳ следующий уровень |
| Связь заметок с задачами | ⏳ после TODO-доски |
| TODO / календарь / Гант | ⏳ каркас экранов |
| Вложения / AI / backup | ⏳ не начаты |

## 2. Проверки

- Backend: `./gradlew cleanTest test` — **18 тестов**.
- Client: `flutter test` — **35 тестов**, 1 e2e пропущен без backend.
- Client + реальный backend/PostgreSQL: e2e create/pull/update/delete — пройден.
- macOS: `integration_test/secure_storage_test.dart` — пройден.
- Сборки: macOS debug, Android debug APK, iOS simulator.
- Windows: не проверялся.

## 3. Техническое состояние

- клиент: Flutter 3.47.7, Riverpod, Drift, Dio, flutter_secure_storage;
- Markdown: `flutter_markdown_plus 1.0.12`;
- backend: Kotlin 2.2.21, Spring Boot 3.5.16, PostgreSQL 16, Flyway;
- миграции backend: V1 notes, V2 identity, V3 note sync, V4 request hash;
- локальная схема: v2 (`syncStatus`, `baseRevision`, `syncStates`, `conflicts`);
- API: `/api/v1/auth/*`, `/api/v1/devices`, `/api/v1/sync/*`;
- синхронизация поддерживает только `NOTE`;
- macOS app sandbox отключён для локального debug;
- Windows-сборка требует отдельной платформы/CI.

## 4. Ключевые файлы заметок

- `apps/client/lib/features/notes/presentation/notes_page.dart` — список и переход в редактор;
- `apps/client/lib/features/notes/presentation/note_editor_page.dart` — редактор и предпросмотр;
- `apps/client/lib/features/notes/data/notes_repository.dart` — outbox и локальные операции;
- `apps/client/lib/features/notes/application/notes_providers.dart` — Riverpod-провайдеры;
- `apps/client/test/features/notes/note_editor_test.dart` — 8 тестов редактора;
- `apps/client/test/core/database/notes_repository_test.dart` — 5 тестов репозитория.

## 5. Известные проблемы

- нет UI разрешения конфликтов, конфликты хранятся в БД;
- чек-листы в предпросмотре не интерактивны;
- связь заметки с задачей появится после реализации TODO-доски;
- внешние изображения в Markdown намеренно не загружаются;
- `notes.user_id` nullable для старых строк;
- лимит push 1 MiB проверяется по Content-Length;
- нет rate limiting;
- macOS secure storage использует legacy Keychain;
- macOS signing/notarization не настроены;
- e2e-тест не входит в обычный `flutter test` без backend.
