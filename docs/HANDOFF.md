# HANDOFF — Ежедневник

**Обновлено:** 2026-11-06
**Текущий этап:** вложения — завершён
**Следующий шаг:** AI Approval (этап 12)
**Репозиторий:** `~/Projects/Zadachnik`, GitHub `georgiadivs-cpu/zadachnik`, ветка `main`

## Что готово

- документация, API и sync-протокол;
- Flutter-клиент для Android, iOS, macOS и Windows;
- backend auth и sync `NOTE`, `TASK`, `LANE`, `REMINDER`;
- клиентский вход, secure storage и logout;
- клиентский sync: outbox, push/pull, cursor, tombstone, конфликты;
- Markdown-редактор заметок;
- TODO-доска;
- календарь и напоминания;
- диаграмма Ганта;
- локальный поиск;
- вложения к заметкам и задачам;
- HTML-прототипы MVP и всех завершённых шагов.

## Проверки этапа 11

- `flutter analyze` — чисто.
- `flutter test` — **99 тестов**, 0 падений; e2e-тест пропущен без backend.
- backend `./gradlew cleanTest test` — **31 тест**, 0 падений.
- e2e с реальным backend/PostgreSQL: NOTE + TASK + REMINDER + ATTACHMENT,
  включая upload/download файла — пройден.
- сборки: macOS debug, Android debug APK, iOS simulator.

## Ключевое во вложениях

- серверное хранилище — локальная папка `ATTACHMENTS_DIR`;
- метаданные в PostgreSQL, файлы вне БД;
- лимит 25 МБ на файл;
- разрешены изображения, PDF, текст/Markdown, MP3/M4A;
- проверка расширения, MIME и сигнатуры файла на сервере;
- SHA-256 и идемпотентная повторная загрузка;
- локальная схема v5: `attachments`;
- серверная миграция V7;
- API загрузки/скачивания/удаления;
- metadata попадает в change log и pull;
- клиент хранит файл локально, догружает при sync и скачивает на других устройствах;
- статусы «ожидает загрузки / готово / ошибка / удаляется»;
- панель вложений в заметке и меню задачи.

## Известные ограничения

- вложения не проверены вручную на всех устройствах;
- папку `ATTACHMENTS_DIR` необходимо включать в резервные копии;
- нет превью/воспроизведения всех типов, только изображения;
- Windows-сборка не проверена;
- macOS signing/notarization не настроены;
- связи задач с заметками и чек-листами отложены;
- AI Approval и backup не начаты.

## Следующий шаг

Этап 12 — AI Approval: предложения изменений, diff «было / станет»,
подтверждение пользователем, журнал действий и запрет прямого доступа
AI к БД и файловой системе. Перед реализацией нужны план,
HTML-прототип и решение по AI-провайдеру.

## Документация

- `PRODUCT_SPEC.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`, `SECURITY.md`, `UI_UX.md`;
- `API_CONTRACTS.md`, `SYNC_PROTOCOL.md`;
- `ACCEPTANCE_CRITERIA.md`, `DEVELOPMENT_WORKFLOW.md`, `DECISIONS.md`;
- `PROJECT_STATE.md`, `WORK_LOG.md`, `MVP_ROADMAP.md`, `NEXT_STEPS.md`.
