# PROJECT_STATE — Ежедневник

**Обновлено:** 2026-11-06
**Текущий шаг:** Backup/restore — завершён
**Следующий шаг:** подготовка релиза (этап 14)

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
| Backup/restore | ✅ |
| Подпись и notarization macOS | ⏳ этап 14 |
| Windows CI и проверка | ⏳ этап 14 |
| Связи задач с заметками/чек-листами | ⏳ отложены |
| UI разрешения конфликтов | ⏳ следующий уровень |

## 2. Проверки

- Backend: `./gradlew cleanTest test` — **38 тестов**.
- Client: `flutter test` — **118 тестов**, 1 e2e пропущен без backend.
- Client + реальный backend/PostgreSQL: e2e backup/restore через CLI
  пройден; интеграционный тест проверяет архив, вложения и
  восстановление в отдельную БД.
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
- резервные копии: `age` 1.3.2, `pg_dump`/`pg_restore` 16;
- backend: Kotlin 2.2.21, Spring Boot 3.5.16, PostgreSQL 16, Flyway;
- миграции backend: V1–V7;
- локальная схема: v6;
- API: `/api/v1/auth/*`, `/api/v1/devices`, `/api/v1/sync/*`,
  `/api/v1/attachments/*`, `/api/v1/backups/*`;
- синхронизация поддерживает `NOTE`, `TASK`, `LANE`, `REMINDER`;
- `ATTACHMENT` metadata попадает в change log через attachment API;
- журнал AI хранится локально в `ai_actions` и не синхронизируется;
- серверные файлы: `ATTACHMENTS_DIR`;
- архивы: `BACKUP_DIR`, отдельный диск, `.zip.age`;
- macOS app sandbox отключён для локального debug.

## 4. Ключевые файлы backup

- `services/api/src/main/kotlin/com/zadachnik/api/backup/application/BackupService.kt` — backup, проверка, снимки, retention;
- `.../BackupJobService.kt` — фоновый запуск и защита от параллельных операций;
- `.../BackupCrypto.kt` — age и проверка ключа;
- `.../BackupZip.kt` — ZIP, manifest, SHA-256 и `pg_restore --list`;
- `.../infrastructure/BackupStateStore.kt` — состояние и история;
- `.../web/BackupController.kt` — API;
- `apps/client/lib/features/backup/` — модели, API, кэш статуса, экран и полоса;
- `apps/client/lib/app/app.dart` — глобальная полоса на всех экранах;
- `scripts/backup/` — init, CLI backup, restore-verify;
- `apps/client/test/features/backup/` — 9 тестов backup-экрана, контроллера и снимка;
- `services/api/src/test/kotlin/com/zadachnik/api/BackupsIntegrationTest.kt` и `RetentionPolicyTest.kt`.

## 5. Известные проблемы

- один диск не заменяет 3-2-1; нужна вторая офлайн-копия;
- потеря ключа age означает потерю копий;
- расписания нет;
- восстановление на чистом сервере вручную не проверялось;
- Windows backup/restore не проверялся;
- вложения не проверены вручную на всех устройствах;
- нет открытия/воспроизведения всех типов файлов;
- нет UI разрешения конфликтов;
- внешние календари и повторяющиеся события не реализованы;
- Windows не поддерживает отмену уведомлений без MSIX;
- связи задач с заметками и чек-листами не реализованы;
- macOS signing/notarization не настроены.
