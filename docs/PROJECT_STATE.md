# PROJECT_STATE — Ежедневник

**Обновлено:** 2026-11-06
**Текущий шаг:** клиентский sync engine `NOTE` — завершён
**Следующий шаг:** Markdown-редактор заметок (этап 6)

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
| Индикатор sync в UI | ✅ заметки и настройки |
| UI разрешения конфликтов | ⏳ следующий уровень |
| Markdown-редактор | ⏳ этап 6 |
| TODO / календарь / Гант | ⏳ каркас экранов |
| Вложения / AI / backup | ⏳ не начаты |

## 2. Проверки

- Backend: `./gradlew cleanTest test` — **18 тестов**.
- Client: `flutter test` — **24 теста**, 1 e2e пропущен без backend.
- Client + реальный backend/PostgreSQL: e2e create/pull/update/delete — пройден.
- macOS: `integration_test/secure_storage_test.dart` — пройден.
- Сборки: macOS debug, Android debug APK, iOS simulator.
- Windows: не проверялся.

## 3. Техническое состояние

- клиент: Flutter 3.47.7, Riverpod, Drift, Dio, flutter_secure_storage;
- backend: Kotlin 2.2.21, Spring Boot 3.5.16, PostgreSQL 16, Flyway;
- миграции backend: V1 notes, V2 identity, V3 note sync, V4 request hash;
- локальная схема: v2 (`syncStatus`, `baseRevision`, `syncStates`, `conflicts`);
- API: `/api/v1/auth/*`, `/api/v1/devices`, `/api/v1/sync/*`;
- синхронизация поддерживает только `NOTE`;
- macOS app sandbox отключён для локального debug;
- Windows-сборка требует отдельной платформы/CI.

## 4. Ключевые файлы sync

- `apps/client/lib/core/database/app_database.dart` — схема v2 и миграция;
- `apps/client/lib/features/notes/data/notes_repository.dart` — outbox и применение;
- `apps/client/lib/features/sync/data/sync_api.dart` — HTTP push/pull;
- `apps/client/lib/features/sync/data/sync_repository.dart` — cursor и конфликты;
- `apps/client/lib/features/sync/application/sync_service.dart` — цикл sync;
- `apps/client/lib/features/sync/application/sync_controller.dart` — состояние UI;
- `apps/client/test/sync/sync_service_test.dart` — 12 тестов sync;
- `apps/client/test/integration/sync_backend_test.dart` — e2e-сценарий.

## 5. Известные проблемы

- нет UI разрешения конфликтов, конфликты хранятся в БД;
- `notes.user_id` nullable для старых строк;
- лимит push 1 MiB проверяется по Content-Length;
- нет rate limiting;
- macOS secure storage использует legacy Keychain;
- macOS signing/notarization не настроены;
- Markdown отображается как обычный текст;
- e2e-тест не входит в обычный `flutter test` без backend.
