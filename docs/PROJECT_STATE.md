# PROJECT_STATE — Ежедневник

**Обновлено:** 2026-11-06
**Текущий шаг:** TODO-доска и sync `TASK`/`LANE` — завершён
**Следующий шаг:** календарь и напоминания (этап 8)

## 1. Статус

| Область | Статус |
|---|---|
| Документация продукта и архитектуры | ✅ |
| API и sync-протокол | ✅ описаны |
| Backend auth | ✅ реализован |
| Backend sync `NOTE` | ✅ реализован |
| Backend sync `TASK`/`LANE` | ✅ реализован |
| Flutter-каркас (4 платформы) | ✅ |
| Локальная БД и outbox | ✅ схема v3 |
| Клиентский вход | ✅ |
| Secure storage | ✅ на macOS проверен |
| Клиентский sync `NOTE` | ✅ |
| Клиентский sync `TASK`/`LANE` | ✅ |
| Markdown-редактор | ✅ |
| TODO-доска | ✅ |
| Связи задач с заметками/чек-листами | ⏳ отложены |
| UI разрешения конфликтов | ⏳ следующий уровень |
| Календарь / Гант | ⏳ каркас экранов |
| Вложения / AI / backup | ⏳ не начаты |

## 2. Проверки

- Backend: `./gradlew cleanTest test` — **24 теста**.
- Client: `flutter test` — **50 тестов**, 1 e2e пропущен без backend.
- Client + реальный backend/PostgreSQL: e2e NOTE + LANE + TASK — пройден.
- macOS: `integration_test/secure_storage_test.dart` — пройден.
- Сборки: macOS debug, Android debug APK, iOS simulator.
- Windows: не проверялся.

## 3. Техническое состояние

- клиент: Flutter 3.47.7, Riverpod, Drift, Dio, flutter_secure_storage;
- Markdown: `flutter_markdown_plus 1.0.12`;
- backend: Kotlin 2.2.21, Spring Boot 3.5.16, PostgreSQL 16, Flyway;
- миграции backend: V1 notes, V2 identity, V3 note sync, V4 request hash,
  V5 task board;
- локальная схема: v3 (`lanes`, `tasks`, `task_status_history`);
- API: `/api/v1/auth/*`, `/api/v1/devices`, `/api/v1/sync/*`;
- синхронизация поддерживает `NOTE`, `TASK`, `LANE`;
- macOS app sandbox отключён для локального debug;
- Windows-сборка требует отдельной платформы/CI.

## 4. Ключевые файлы TODO

- `apps/client/lib/core/database/tables.dart` — lanes, tasks, history;
- `apps/client/lib/core/database/default_lanes.dart` — стабильные UUID;
- `apps/client/lib/features/tasks/data/lanes_repository.dart` — дорожки и outbox;
- `apps/client/lib/features/tasks/data/tasks_repository.dart` — задачи и история;
- `apps/client/lib/features/tasks/presentation/tasks_page.dart` — доска;
- `apps/client/lib/features/tasks/presentation/task_editor_dialog.dart` — редактор;
- `apps/client/lib/features/tasks/presentation/lane_settings_dialog.dart` — настройка;
- `apps/client/test/features/tasks/` — 13 тестов доски и репозиториев.

## 5. Известные проблемы

- нет UI разрешения конфликтов, конфликты хранятся в БД;
- связи задач с заметками и чек-листами не реализованы;
- terminal lane и правила завершения не утверждены;
- `notes.user_id` nullable для старых строк;
- лимит push 1 MiB проверяется по Content-Length;
- нет rate limiting;
- macOS secure storage использует legacy Keychain;
- macOS signing/notarization не настроены;
- e2e-тест не входит в обычный `flutter test` без backend.
