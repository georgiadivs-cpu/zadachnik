# PROJECT_STATE — Ежедневник

**Обновлено:** 2026-11-06
**Текущий шаг:** календарь и напоминания — завершён
**Следующий шаг:** диаграмма Ганта (этап 9)

## 1. Статус

| Область | Статус |
|---|---|
| Документация продукта и архитектуры | ✅ |
| API и sync-протокол | ✅ описаны |
| Backend auth | ✅ реализован |
| Backend sync `NOTE` | ✅ реализован |
| Backend sync `TASK`/`LANE` | ✅ реализован |
| Backend sync `REMINDER` | ✅ реализован |
| Flutter-каркас (4 платформы) | ✅ |
| Локальная БД и outbox | ✅ схема v4 |
| Клиентский вход | ✅ |
| Secure storage | ✅ на macOS проверен |
| Клиентский sync `NOTE`/`TASK`/`LANE`/`REMINDER` | ✅ |
| Markdown-редактор | ✅ |
| TODO-доска | ✅ |
| Календарь | ✅ |
| Локальные уведомления | ✅ |
| Внешние календари | ❌ вне этапа |
| Связи задач с заметками/чек-листами | ⏳ отложены |
| UI разрешения конфликтов | ⏳ следующий уровень |
| Гант | ⏳ каркас экрана |
| Вложения / AI / backup | ⏳ не начаты |

## 2. Проверки

- Backend: `./gradlew cleanTest test` — **27 тестов**.
- Client: `flutter test` — **62 теста**, 1 e2e пропущен без backend.
- Client + реальный backend/PostgreSQL: e2e NOTE + LANE + TASK + REMINDER — пройден.
- macOS: `integration_test/secure_storage_test.dart` — пройден.
- Сборки: macOS debug, Android debug APK, iOS simulator.
- Уведомления проверены сборкой; ручная проверка доставки на устройствах не выполнялась.
- Windows: не проверялся.

## 3. Техническое состояние

- клиент: Flutter 3.47.7, Riverpod, Drift, Dio, flutter_secure_storage;
- Markdown: `flutter_markdown_plus 1.0.12`;
- уведомления: `flutter_local_notifications 22.3.3`, `timezone 0.11.2`,
  `flutter_timezone 5.1.1`;
- backend: Kotlin 2.2.21, Spring Boot 3.5.16, PostgreSQL 16, Flyway;
- миграции backend: V1 notes, V2 identity, V3 note sync, V4 request hash,
  V5 task board, V6 task reminders;
- локальная схема: v4 (`lanes`, `tasks`, `task_status_history`, `task_reminders`);
- API: `/api/v1/auth/*`, `/api/v1/devices`, `/api/v1/sync/*`;
- синхронизация поддерживает `NOTE`, `TASK`, `LANE`, `REMINDER`;
- macOS app sandbox отключён для локального debug;
- Windows-сборка требует отдельной платформы/CI.

## 4. Ключевые файлы календаря

- `apps/client/lib/features/calendar/presentation/calendar_page.dart` — календарь и agenda;
- `apps/client/lib/features/calendar/data/reminders_repository.dart` — напоминания и outbox;
- `apps/client/lib/features/calendar/application/reminder_scheduler.dart` — системные уведомления;
- `apps/client/lib/features/calendar/application/reminder_coordinator.dart` — reconcile и разрешения;
- `apps/client/lib/features/calendar/application/calendar_providers.dart` — Riverpod;
- `apps/client/lib/features/tasks/presentation/task_editor_dialog.dart` — напоминание в задаче;
- `apps/client/test/calendar/` — 5 тестов напоминаний;
- `apps/client/test/features/calendar/` — 3 widget-теста календаря.

## 5. Известные проблемы

- нет UI разрешения конфликтов, конфликты хранятся в БД;
- внешние календари, CalDAV и повторяющиеся события не реализованы;
- фактические даты не отображаются в календаре;
- Windows не поддерживает отмену уведомлений без MSIX;
- iOS хранит не более 64 запланированных уведомлений;
- связи задач с заметками и чек-листами не реализованы;
- `notes.user_id` nullable для старых строк;
- лимит push 1 MiB проверяется по Content-Length;
- нет rate limiting;
- macOS secure storage использует legacy Keychain;
- macOS signing/notarization не настроены.
