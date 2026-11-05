# HANDOFF — Ежедневник

**Обновлено:** 2026-11-05  
**Текущий этап:** фундамент клиента и синхронизации  
**Текущий шаг:** клиентский вход и secure session — завершён  
**Следующий шаг:** клиентский sync engine для `NOTE`  
**Репозиторий:** `~/Projects/Zadachnik`, public GitHub `georgiadivs-cpu/zadachnik`, ветка `main`

## Что готово

- документация продукта, архитектуры, API и sync-протокола;
- Flutter-клиент для Android, iOS, macOS и Windows;
- локальная SQLite + Drift, outbox заметок;
- backend auth: setup/login/refresh/logout/devices;
- backend sync: `push`/`pull`/`state` для `NOTE`;
- клиентский вход, setup владельца, secure storage и logout;
- HTML-прототипы API/sync, auth и клиентского входа.

## Проверки

- backend: **18 тестов**, 0 падений;
- client: **11 unit/widget тестов**, 0 падений;
- macOS integration: secure storage запись/чтение/удаление — пройдено;
- сборки: macOS debug, Android debug APK, iOS simulator;
- локальный auth/sync через PostgreSQL и curl — пройдено.

## Ключевые решения

- D-015…D-018 — Flutter/Drift и Kotlin/Spring/PostgreSQL.
- D-019…D-022 — REST + sync-only, auth, cursor, конфликты без LWW.
- D-023 — клиентская сессия в secure storage, logout не удаляет локальные данные.
- D-024 — macOS MVP использует legacy Keychain без sandbox; для App Store нужен отдельный signing/sandbox шаг.
- D-025 — setup token вводится вручную только при первичной настройке.

## Известные ограничения

- синхронизируется только `NOTE`;
- клиентский sync engine и UI разрешения конфликтов не реализованы;
- Windows-сборка не проверена: нужна Windows-машина или CI;
- macOS sandbox отключён для локального debug; App Store-подпись не настроена;
- rate limiting, VPN и файловое хранилище вложений не реализованы;
- Markdown-редактор пока не реализован: заметка хранит Markdown, но UI —
  простое текстовое поле.

## Документация

- `PRODUCT_SPEC.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`, `SECURITY.md`, `UI_UX.md`;
- `API_CONTRACTS.md`, `SYNC_PROTOCOL.md`;
- `ACCEPTANCE_CRITERIA.md`, `DEVELOPMENT_WORKFLOW.md`, `DECISIONS.md`;
- `PROJECT_STATE.md`, `WORK_LOG.md`, `MVP_ROADMAP.md`, `NEXT_STEPS.md`.
