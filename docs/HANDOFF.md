# HANDOFF — Ежедневник

**Обновлено:** 2026-11-06
**Текущий этап:** Markdown-редактор заметок — завершён
**Следующий шаг:** TODO-доска (этап 7)
**Репозиторий:** `~/Projects/Zadachnik`, GitHub `georgiadivs-cpu/zadachnik`, ветка `main`

## Что готово

- документация, API и sync-протокол;
- Flutter-клиент для Android, iOS, macOS и Windows;
- backend auth и backend sync `NOTE`;
- клиентский вход, secure storage и logout;
- клиентский sync engine `NOTE`: outbox, push/pull, cursor, tombstone, конфликты;
- полноэкранный Markdown-редактор заметки;
- создание, редактирование и автосохранение заметок;
- предпросмотр Markdown: заголовки, списки, чек-листы, цитаты, код, ссылки;
- индикатор сохранения и защита от выхода с несохранёнными изменениями;
- HTML-прототипы MVP и редактора.

## Проверки этапа 6

- `flutter analyze` — чисто.
- `flutter test` — **35 тестов**, 0 падений; e2e-тест пропущен без backend.
- сборки: macOS debug, Android debug APK, iOS simulator.
- ручная проверка прототипа: `prototypes/markdown-editor.html`.

## Ключевое в редакторе

- `NoteEditorPage` сохраняет через `NotesRepository`, то есть локально и в outbox.
- Автосохранение с задержкой 800 мс, `⌘S` / `Ctrl+S`, кнопка сохранения.
- При выходе с изменениями предлагается сохранить или выйти без сохранения.
- Предпросмотр через `flutter_markdown_plus` (D-026).
- Внешние изображения из Markdown не загружаются автоматически.
- Ссылки показываются уведомлением, без открытия внешнего браузера.
- Чек-листы поддерживаются как Markdown; интерактивная связь с задачами
  появится вместе с TODO-доской.

## Известные ограничения

- синхронизируется только `NOTE`;
- нет UI разрешения конфликтов;
- чек-листы не связаны с задачами: модуль задач ещё не реализован;
- Windows-сборка не проверена: нужна Windows-машина или CI;
- macOS signing/notarization и App Store-подготовка не настроены;
- rate limiting, VPN и файловое хранилище вложений не реализованы;
- e2e-тест требует запущенного backend и `--dart-define`.

## Следующий шаг

Этап 7 — TODO-доска: одна доска, 3–10 настраиваемых дорожек,
перемещение задач, плановые/фактические даты и отмена как системное
состояние. Перед реализацией нужны план и HTML-прототип.

## Документация

- `PRODUCT_SPEC.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`, `SECURITY.md`, `UI_UX.md`;
- `API_CONTRACTS.md`, `SYNC_PROTOCOL.md`;
- `ACCEPTANCE_CRITERIA.md`, `DEVELOPMENT_WORKFLOW.md`, `DECISIONS.md`;
- `PROJECT_STATE.md`, `WORK_LOG.md`, `MVP_ROADMAP.md`, `NEXT_STEPS.md`.
