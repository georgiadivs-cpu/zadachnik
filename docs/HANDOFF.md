# HANDOFF — Ежедневник

**Обновлено:** 2026-11-06
**Текущий этап:** клиентский sync engine `NOTE` — завершён
**Следующий шаг:** Markdown-редактор заметок (этап 6)
**Репозиторий:** `~/Projects/Zadachnik`, GitHub `georgiadivs-cpu/zadachnik`, ветка `main`

## Что готово

- документация продукта, архитектуры, API и sync-протокола;
- Flutter-клиент для Android, iOS, macOS и Windows;
- локальная SQLite + Drift, outbox заметок, схема v2;
- backend auth и backend sync `NOTE`;
- клиентский вход, setup владельца, secure storage и logout;
- клиентский sync engine `NOTE`: push, pull, cursor, конфликты;
- индикатор синхронизации на экране заметок и в настройках;
- миграция v1 → v2 с постановкой старых заметок в outbox;
- HTML-прототип MVP `prototypes/mvp-complete.html`.

## Проверки этапа 5

- `flutter analyze` — чисто.
- `flutter test` — **24 теста**, 0 падений; e2e-тест по умолчанию пропущен.
- `flutter test test/integration/sync_backend_test.dart` с реальным backend
  и PostgreSQL — create → pull на втором клиенте → update → delete: пройдено.
- backend `./gradlew cleanTest test` — **18 тестов**, 0 падений.
- сборки: macOS debug, Android debug APK, iOS simulator.

## Ключевое в sync

- `SyncService`: push батчами, APPLIED/DUPLICATE/CONFLICT/REJECTED,
  pull страницами, cursor после успешной транзакции.
- Офлайн: операции остаются в outbox, повтор после восстановления сети.
- Правка во время push не теряется: операция становится `UPDATE`
  с новой `baseRevision`.
- Конфликт: outbox-операция снимается, локальная и серверная версии
  сохраняются; UI ручного разрешения ещё нет.
- Tombstone применяется через pull, удалённая заметка исчезает из списка.
- При 401 сессия обновляется один раз и цикл повторяется.

## Известные ограничения

- синхронизируется только `NOTE`;
- нет UI разрешения конфликтов;
- Windows-сборка не проверена: нужна Windows-машина или CI;
- macOS signing/notarization и App Store-подготовка не настроены;
- rate limiting, VPN и файловое хранилище вложений не реализованы;
- Markdown хранится и синхронизируется, но редактора Markdown ещё нет;
- e2e-тест требует запущенного backend и `--dart-define`.

## Следующий шаг

Этап 6 — Markdown-редактор заметок: редактирование, предпросмотр,
сохранение без потери содержимого и связь с задачами/чек-листами.
Перед реализацией нужны план и HTML-прототип, затем подтверждение.

## Документация

- `PRODUCT_SPEC.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`, `SECURITY.md`, `UI_UX.md`;
- `API_CONTRACTS.md`, `SYNC_PROTOCOL.md`;
- `ACCEPTANCE_CRITERIA.md`, `DEVELOPMENT_WORKFLOW.md`, `DECISIONS.md`;
- `PROJECT_STATE.md`, `WORK_LOG.md`, `MVP_ROADMAP.md`, `NEXT_STEPS.md`.
