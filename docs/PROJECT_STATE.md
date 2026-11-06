# PROJECT_STATE — Ежедневник

**Обновлено:** 2026-11-06
**Текущий шаг:** вложения — завершён
**Следующий шаг:** AI Approval (этап 12)

## 1. Статус

| Область | Статус |
|---|---|
| Документация продукта и архитектуры | ✅ |
| API и sync-протокол | ✅ описаны |
| Backend auth | ✅ реализован |
| Backend sync `NOTE`/`TASK`/`LANE`/`REMINDER` | ✅ |
| Backend attachments API и change log | ✅ |
| Flutter-каркас (4 платформы) | ✅ |
| Локальная БД и outbox | ✅ схема v5 |
| Клиентский вход и secure storage | ✅ |
| Клиентский sync | ✅ |
| Markdown-редактор | ✅ |
| TODO-доска | ✅ |
| Календарь и напоминания | ✅ |
| Диаграмма Ганта | ✅ |
| Локальный поиск | ✅ |
| Вложения | ✅ |
| AI Approval / backup | ⏳ не начаты |
| Связи задач с заметками/чек-листами | ⏳ отложены |
| UI разрешения конфликтов | ⏳ следующий уровень |

## 2. Проверки

- Backend: `./gradlew cleanTest test` — **31 тест**.
- Client: `flutter test` — **99 тестов**, 1 e2e пропущен без backend.
- Client + реальный backend/PostgreSQL: e2e NOTE + TASK + REMINDER +
  ATTACHMENT с upload/download — пройден.
- macOS: `integration_test/secure_storage_test.dart` — пройден.
- Сборки: macOS debug, Android debug APK, iOS simulator.
- Windows: не проверялся.

## 3. Техническое состояние

- клиент: Flutter 3.47.7, Riverpod, Drift, Dio, flutter_secure_storage;
- Markdown: `flutter_markdown_plus 1.0.12`;
- уведомления: `flutter_local_notifications 22.3.3`, `timezone 0.11.2`,
  `flutter_timezone 5.1.1`;
- файлы: `file_selector`, `path_provider`, `crypto`, `mime`;
- backend: Kotlin 2.2.21, Spring Boot 3.5.16, PostgreSQL 16, Flyway;
- миграции backend: V1–V7;
- локальная схема: v5;
- API: `/api/v1/auth/*`, `/api/v1/devices`, `/api/v1/sync/*`,
  `/api/v1/attachments/*`;
- синхронизация поддерживает `NOTE`, `TASK`, `LANE`, `REMINDER`;
- `ATTACHMENT` metadata попадает в change log через attachment API;
- серверные файлы: `ATTACHMENTS_DIR`;
- macOS app sandbox отключён для локального debug.

## 4. Ключевые файлы вложений

- `apps/client/lib/features/attachments/domain/attachment.dart` — модель и правила;
- `apps/client/lib/features/attachments/data/attachment_file_store.dart` — локальные файлы;
- `apps/client/lib/features/attachments/data/attachment_api.dart` — upload/download/delete;
- `apps/client/lib/features/attachments/data/attachments_repository.dart` — metadata;
- `apps/client/lib/features/attachments/application/attachment_coordinator.dart` — retry и синхронизация;
- `apps/client/lib/features/attachments/presentation/attachment_panel.dart` — UI;
- `services/api/src/main/kotlin/com/zadachnik/api/attachment/**` — backend;
- `apps/client/test/attachments/` и `apps/client/test/features/attachments/` — 9 тестов.

## 5. Известные проблемы

- вложения не проверены вручную на всех устройствах;
- папку `ATTACHMENTS_DIR` нужно включить в backup;
- нет открытия/воспроизведения всех типов файлов;
- нет UI разрешения конфликтов;
- внешние календари и повторяющиеся события не реализованы;
- Windows не поддерживает отмену уведомлений без MSIX;
- связи задач с заметками и чек-листами не реализованы;
- macOS signing/notarization не настроены.
