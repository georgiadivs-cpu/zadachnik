# PROJECT_STATE — Ежедневник

**Обновлено:** 2026-11-06
**Текущий шаг:** диаграмма Ганта — завершён
**Следующий шаг:** локальный поиск (этап 10)

## 1. Статус

| Область | Статус |
|---|---|
| Документация продукта и архитектуры | ✅ |
| API и sync-протокол | ✅ описаны |
| Backend auth | ✅ реализован |
| Backend sync `NOTE`/`TASK`/`LANE`/`REMINDER` | ✅ |
| Flutter-каркас (4 платформы) | ✅ |
| Локальная БД и outbox | ✅ схема v4 |
| Клиентский вход и secure storage | ✅ |
| Клиентский sync | ✅ |
| Markdown-редактор | ✅ |
| TODO-доска | ✅ |
| Календарь и напоминания | ✅ |
| Диаграмма Ганта | ✅ |
| Локальный поиск | ⏳ этап 10 |
| Вложения / AI / backup | ⏳ не начаты |
| Связи задач с заметками/чек-листами | ⏳ отложены |
| UI разрешения конфликтов | ⏳ следующий уровень |

## 2. Проверки

- Backend: `./gradlew cleanTest test` — **27 тестов** (без изменений).
- Client: `flutter test` — **74 теста**, 1 e2e пропущен без backend.
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
- миграции backend: V1–V6;
- локальная схема: v4;
- API: `/api/v1/auth/*`, `/api/v1/devices`, `/api/v1/sync/*`;
- синхронизация поддерживает `NOTE`, `TASK`, `LANE`, `REMINDER`;
- macOS app sandbox отключён для локального debug;
- Windows-сборка требует отдельной платформы/CI.

## 4. Ключевые файлы Ганта

- `apps/client/lib/features/gantt/domain/gantt_timeline.dart` — диапазоны, позиции полос, просрочка;
- `apps/client/lib/features/gantt/presentation/gantt_page.dart` — экран Ганта;
- `apps/client/test/features/gantt/gantt_timeline_test.dart` — unit-тесты;
- `apps/client/test/features/gantt/gantt_page_test.dart` — widget-тесты;
- `prototypes/gantt.html` — принятый прототип.

## 5. Известные проблемы

- нет зависимостей задач, критического пути и ресурсов;
- даты меняются через редактор задачи, не drag;
- задачи без дат и отменённые задачи не показываются;
- нет UI разрешения конфликтов;
- внешние календари и повторяющиеся события не реализованы;
- уведомления не проверены вручную на всех устройствах;
- Windows не поддерживает отмену уведомлений без MSIX;
- связи задач с заметками и чек-листами не реализованы;
- macOS signing/notarization не настроены.
