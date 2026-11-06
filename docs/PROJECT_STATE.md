# PROJECT_STATE — Ежедневник

**Обновлено:** 2026-11-06
**Текущий шаг:** AI Approval — завершён
**Следующий шаг:** Backup/restore (этап 13)

## 1. Статус

| Область | Статус |
|---|---|
| Документация продукта и архитектуры | ✅ |
| API и sync-протокол | ✅ описаны |
| Backend auth | ✅ реализован |
| Backend sync `NOTE`/`TASK`/`LANE`/`REMINDER` | ✅ |
| Backend attachments API и change log | ✅ |
| Flutter-каркас (4 платформы) | ✅ |
| Локальная БД и outbox | ✅ схема v6 |
| Клиентский вход и secure storage | ✅ |
| Клиентский sync | ✅ |
| Markdown-редактор | ✅ |
| TODO-доска | ✅ |
| Календарь и напоминания | ✅ |
| Диаграмма Ганта | ✅ |
| Локальный поиск | ✅ |
| Вложения | ✅ |
| AI Approval | ✅ |
| Backup/restore | ⏳ следующий шаг |
| Связи задач с заметками/чек-листами | ⏳ отложены |
| UI разрешения конфликтов | ⏳ следующий уровень |

## 2. Проверки

- Backend: `./gradlew cleanTest test` — **31 тест**
  (в этапе 12 backend не изменялся).
- Client: `flutter test` — **109 тестов**, 1 e2e пропущен без backend.
- Client + реальный backend/PostgreSQL: последний e2e NOTE + TASK +
  REMINDER + ATTACHMENT пройден на этапе 11; в этапе 12 не перезапускался.
- macOS: `integration_test/secure_storage_test.dart` — пройден ранее.
- Сборки: macOS debug, Android debug APK, iOS simulator.
- Windows: не проверялся.

## 3. Техническое состояние

- клиент: Flutter 3.47.7, Riverpod, Drift, Dio, flutter_secure_storage;
- Markdown: `flutter_markdown_plus 1.0.12`;
- уведомления: `flutter_local_notifications 22.3.3`, `timezone 0.11.2`,
  `flutter_timezone 5.1.1`;
- файлы: `file_selector`, `path_provider`, `crypto`, `mime`;
- AI: локальный rule-based ассистент, без внешних запросов;
- backend: Kotlin 2.2.21, Spring Boot 3.5.16, PostgreSQL 16, Flyway;
- миграции backend: V1–V7;
- локальная схема: v6;
- API: `/api/v1/auth/*`, `/api/v1/devices`, `/api/v1/sync/*`,
  `/api/v1/attachments/*`;
- синхронизация поддерживает `NOTE`, `TASK`, `LANE`, `REMINDER`;
- `ATTACHMENT` metadata попадает в change log через attachment API;
- журнал AI хранится локально в `ai_actions` и не синхронизируется;
- серверные файлы: `ATTACHMENTS_DIR`;
- macOS app sandbox отключён для локального debug.

## 4. Ключевые файлы AI

- `apps/client/lib/features/ai/domain/ai_models.dart` — предложение,
  изменение, результат, журнал;
- `apps/client/lib/features/ai/application/ai_assistant.dart` — разбор
  команд, анализ и создание предложений;
- `apps/client/lib/features/ai/application/ai_approval_service.dart` —
  approval, отказ, проверка актуальности, применение;
- `apps/client/lib/features/ai/data/ai_repository.dart` — журнал `ai_actions`;
- `apps/client/lib/features/ai/presentation/ai_page.dart` — чат, diff, журнал;
- `apps/client/lib/core/database/tables.dart` — `AiActions`;
- `apps/client/test/features/ai/` — 10 тестов ассистента, approval и экрана.

## 5. Известные проблемы

- rule-based ассистент ограничен командами и формулировками;
- журнал AI не синхронизируется;
- вложения не проверены вручную на всех устройствах;
- папку `ATTACHMENTS_DIR` нужно включить в backup;
- нет открытия/воспроизведения всех типов файлов;
- нет UI разрешения конфликтов;
- внешние календари и повторяющиеся события не реализованы;
- Windows не поддерживает отмену уведомлений без MSIX;
- связи задач с заметками и чек-листами не реализованы;
- macOS signing/notarization не настроены.
