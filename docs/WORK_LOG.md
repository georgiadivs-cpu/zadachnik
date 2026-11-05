# WORK_LOG — Ежедневник

Журнал **только дополняется**. Старые записи не переписываются.

## 2026-11-05 20:10 — Каркас проекта

- **Цель:** создать новый проект и перенести документацию/скилы.
- **Изменённые файлы:** `AGENTS.md`, `README.md`, `docs/`, `.agents/skills/`, `ai/`, `apps/client/`, `services/api/`, `infrastructure/`, `tests/`.
- **Команды:** `flutter create`; `./gradlew test`; `flutter analyze`; `flutter test`; `docker compose config`.
- **Результат:** документация из вложения, 9 skills с frontmatter, Flutter-каркас, Spring Boot API, PostgreSQL compose.
- **Ошибки:** проект был перемещён в `~/Desktop`; восстановлен копированием без удаления файлов.
- **Следующий шаг:** API и sync-протокол.

## 2026-11-05 21:05 — API и sync-протокол

- **Цель:** спроектировать REST API, auth, push/pull и конфликты.
- **Изменённые файлы:** `docs/API_CONTRACTS.md`, `docs/SYNC_PROTOCOL.md`, `packages/contracts/openapi.yaml`, `docs/DECISIONS.md`, `docs/DATA_MODEL.md`, `docs/ARCHITECTURE.md`.
- **Команды:** OpenAPI validator; проверка ссылок.
- **Результат:** 9 endpoints, 13 schemas; D-019…D-022; прототип `prototypes/api-sync-protocol.html`.
- **Ошибки:** нет.
- **Следующий шаг:** backend auth.

## 2026-11-05 22:10 — Backend auth

- **Цель:** setup/login/refresh/logout/devices, JWT и защита API.
- **Изменённые файлы:** `V2__create_identity.sql`, `identity/*`, `SecurityConfiguration`, `IdentityIntegrationTest`.
- **Команды:** `./gradlew test`; `bootJar`; локальный curl setup/login/devices.
- **Результат:** 10 тестов; setup 201, devices 200, без токена 401, повтор setup 409.
- **Ошибки:** тестовый JWT-секрет был короче 32 байт; повтор refresh откатывал отзыв устройства — вынесен в `REQUIRES_NEW`.
- **Следующий шаг:** backend sync `NOTE`.

## 2026-11-05 22:45 — Backend sync `NOTE`

- **Цель:** push/pull заметок, cursor, idempotency, tombstone и конфликты.
- **Изменённые файлы:** `V3__create_note_sync.sql`, `V4__add_processed_request_hash.sql`, `sync/*`, `SyncNotesIntegrationTest`, docs/API.
- **Команды:** `./gradlew test`; `bootJar`; локальный curl push/pull/duplicate.
- **Результат:** 18 backend-тестов; push APPLIED revision 1, pull cursor 1, duplicate без второго изменения.
- **Ошибки:** повтор `operationId` с другим телом не различался — добавлен request hash.
- **Следующий шаг:** клиентский вход.

## 2026-11-05 23:24 — Клиентский вход

- **Цель:** login/setup, secure storage, bootstrap, refresh, logout без удаления заметок.
- **Изменённые файлы:** `core/auth/*`, `core/network/api_config.dart`, `features/auth/*`, `auth_gate`, `login_page`, `setup_page`, `settings_page`, `pubspec.yaml`, macOS entitlements, тесты.
- **Команды:** `flutter analyze`; `flutter test`; `flutter test integration_test/secure_storage_test.dart -d macos`; `flutter build macos/apk/ios`.
- **Результат:** 11 client-тестов, secure storage integration на macOS, сборки macOS/Android/iOS.
- **Ошибки:** macOS Keychain требовал entitlement; для локального MVP включён legacy Keychain без sandbox; App Store signing отложен.
- **Следующий шаг:** клиентский sync engine `NOTE`.

## 2026-11-05 23:30 — Публикация репозитория

- **Цель:** создать публичный GitHub-репозиторий и зафиксировать исходное состояние.
- **Изменённые файлы:** `docs/HANDOFF.md`, `docs/PROJECT_STATE.md`, `docs/WORK_LOG.md`.
- **Команды:** `git commit`; `gh repo create zadachnik --public --source=. --remote=origin --push`; `gh repo view`.
- **Результат:** https://github.com/georgiadivs-cpu/zadachnik, `main`, public; коммит `ad020dd`.
- **Ошибки:** нет.
- **Следующий шаг:** клиентский sync engine `NOTE`.

## 2026-11-06 — Клиентский sync engine `NOTE`

- **Цель:** push outbox, pull по cursor, конфликты, tombstone, offline → online.
- **Изменённые файлы:** `core/database/*`, `features/notes/*`, `features/sync/*`, `features/settings/*`, `app/home_shell.dart`, тесты sync и миграции.
- **Результат:** схема v2 и миграция v1 → v2; `SyncApi`, `SyncRepository`, `SyncService`, `SyncController`; APPLIED/DUPLICATE/CONFLICT/REJECTED; pull страницами; защита правки во время push; индикатор sync; e2e create/pull/update/delete.
- **Команды:** `flutter analyze`; `flutter test`; `./gradlew cleanTest test`; e2e с временным PostgreSQL и backend; `flutter build macos/apk/ios`.
- **Проверки:** 24 client-теста, 18 backend-тестов, e2e пройден; сборки macOS/Android/iOS.
- **Ошибки:** при первой версии миграции отсутствовал `onUpgrade`, старые заметки не попадали в outbox — исправлено и покрыто тестом; правка во время push могла потеряться — добавлена переотправка как `UPDATE`.
- **Ограничения:** нет UI разрешения конфликтов; только `NOTE`; Windows не проверен.
- **Следующий шаг:** Markdown-редактор заметок.

## 2026-11-06 — Markdown-редактор заметок

- **Цель:** создание и редактирование заметок, предпросмотр Markdown, сохранение без потери текста.
- **Изменённые файлы:** `features/notes/presentation/*`, `pubspec.yaml`, `pubspec.lock`, тесты редактора и репозитория, `prototypes/markdown-editor.html`, документация.
- **Результат:** полноэкранный редактор, автосохранение, `⌘S`/`Ctrl+S`, индикатор состояния, защита от выхода с несохранёнными изменениями, предпросмотр GFM.
- **Зависимость:** `flutter_markdown_plus 1.0.12` (BSD-3), решение D-026; внешние изображения не загружаются.
- **Команды:** `flutter analyze`; `flutter test`; `flutter build macos/apk/ios`.
- **Проверки:** 35 client-тестов, 0 падений; сборки macOS/Android/iOS; узкий экран 360 px.
- **Ошибки:** тест с Drift-стримом зависал вне `tester.pump`; исправлен на прямой запрос к БД и UI-стрим с явным значением.
- **Ограничения:** чек-листы пока не связаны с задачами; внешние ссылки не открываются автоматически.
- **Следующий шаг:** TODO-доска.
