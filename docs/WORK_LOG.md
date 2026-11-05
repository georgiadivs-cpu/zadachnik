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
