# HANDOFF — Ежедневник

**Обновлено:** 2026-11-06
**Текущий этап:** TODO-доска и sync `TASK`/`LANE` — завершён
**Следующий шаг:** календарь и напоминания (этап 8)
**Репозиторий:** `~/Projects/Zadachnik`, GitHub `georgiadivs-cpu/zadachnik`, ветка `main`

## Что готово

- документация, API и sync-протокол;
- Flutter-клиент для Android, iOS, macOS и Windows;
- backend auth, backend sync `NOTE`, `TASK`, `LANE`;
- клиентский вход, secure storage и logout;
- клиентский sync: outbox, push/pull, cursor, tombstone, конфликты;
- Markdown-редактор заметок с автосохранением и предпросмотром;
- одна TODO-доска с 3–10 настраиваемыми дорожками;
- создание, редактирование и перемещение задач;
- плановые и фактические даты;
- отмена и возврат как системное состояние;
- отдельный блок отменённых задач;
- локальная история перемещений;
- HTML-прототипы MVP, редактора и TODO-доски.

## Проверки этапа 7

- `flutter analyze` — чисто.
- `flutter test` — **50 тестов**, 0 падений; e2e-тест пропущен без backend.
- backend `./gradlew cleanTest test` — **24 теста**, 0 падений.
- e2e с реальным backend/PostgreSQL: NOTE + LANE + TASK
  create → pull → update → delete/cancel — пройден.
- сборки: macOS debug, Android debug APK, iOS simulator.

## Ключевое в TODO

- локальная схема v3: `lanes`, `tasks`, `task_status_history`;
- дорожки по умолчанию имеют стабильные UUID на клиенте и сервере;
- `TASK` и `LANE` синхронизируются через общий outbox;
- `LANE` создаётся/переименовывается/удаляется; непустую дорожку
  удалить нельзя;
- отмена — `systemState = CANCELLED`, не дорожка;
- перемещение через drag-and-drop и через меню карточки;
- история пишется при смене дорожки и дедуплицируется по `operationId`.

## Известные ограничения

- связи задач с заметками и чек-листами отложены;
- нет UI разрешения конфликтов;
- завершающая дорожка/terminal lane не введена;
- Windows-сборка не проверена: нужна Windows-машина или CI;
- macOS signing/notarization не настроены;
- rate limiting, VPN и файловое хранилище вложений не реализованы;
- e2e-тест требует запущенного backend и `--dart-define`.

## Следующий шаг

Этап 8 — календарь и напоминания: плановые даты задач, часовые пояса,
напоминания и переход к задаче. Перед реализацией нужны план
и HTML-прототип.

## Документация

- `PRODUCT_SPEC.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`, `SECURITY.md`, `UI_UX.md`;
- `API_CONTRACTS.md`, `SYNC_PROTOCOL.md`;
- `ACCEPTANCE_CRITERIA.md`, `DEVELOPMENT_WORKFLOW.md`, `DECISIONS.md`;
- `PROJECT_STATE.md`, `WORK_LOG.md`, `MVP_ROADMAP.md`, `NEXT_STEPS.md`.
