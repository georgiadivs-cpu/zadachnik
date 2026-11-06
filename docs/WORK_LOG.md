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

## 2026-11-06 — TODO-доска и sync `TASK`/`LANE`

- **Цель:** одна доска, 3–10 дорожек, задачи, перемещение, отмена, история и синхронизация.
- **Изменённые файлы:** `services/api` (V5, task/lane repositories, processors, sync routing, тесты), `apps/client/lib/features/tasks/*`, `core/database/*`, `features/sync/*`, тесты, `prototypes/todo-board.html`, документация.
- **Результат:** локальная схема v3; `LANE`/`TASK` push/pull; стабильные ID дорожек; drag-and-drop и меню перемещения; плановые/фактические даты; отмена как системное состояние; отдельный блок отменённых; история с дедупликацией по `operationId`.
- **Команды:** `flutter analyze`; `flutter test`; `./gradlew cleanTest test`; e2e с временным PostgreSQL/backend; сборки macOS/Android/iOS.
- **Проверки:** 50 client-тестов, 24 backend-теста, e2e NOTE+LANE+TASK пройден.
- **Ошибки:** конфликт pull не помечал задачу/дорожку как `CONFLICT` — исправлено; история при одинаковой секунде сортировалась нестабильно — добавлен autoincrement `sequence`.
- **Ограничения:** связи задач с заметками/чек-листами отложены; terminal lane не утверждён.
- **Следующий шаг:** календарь и напоминания.

## 2026-11-06 — Календарь и напоминания

- **Цель:** календарь плановых дат, одно напоминание на задачу, системные уведомления и sync `REMINDER`.
- **Изменённые файлы:** `features/calendar/*`, `features/tasks/*`, `core/database/*`, `features/sync/*`, `services/api` (V6, reminder repository/processor, тесты), платформенные настройки Android/iOS, `prototypes/calendar-reminders.html`, документация.
- **Результат:** месячный календарь с agenda и фильтрами; редактор напоминания в задаче; UTC-хранение и локальная IANA-зона; `flutter_local_notifications`; reconcile после sync/старта; sync `REMINDER`; отмена задачи снимает напоминание.
- **Команды:** `flutter analyze`; `flutter test`; `./gradlew cleanTest test`; e2e с временным PostgreSQL/backend; сборки macOS/Android/iOS.
- **Проверки:** 62 client-теста, 27 backend-тестов, e2e NOTE+LANE+TASK+REMINDER пройден.
- **Ошибки:** серверная и локальная история дат использовали локальное время — приведено к UTC; порядок outbox мог отправить REMINDER раньше TASK — добавлен зависимостный порядок LANE → TASK → REMINDER → LANE DELETE.
- **Ограничения:** внешние календари/повторяющиеся события не входят; доставка уведомлений вручную на устройствах не проверена; Windows cancel без MSIX ограничен.
- **Следующий шаг:** диаграмма Ганта.

## 2026-11-06 — Диаграмма Ганта

- **Цель:** простая временная шкала задач с планом, фактом, просрочкой и масштабами.
- **Изменённые файлы:** `features/gantt/*`, тесты Ганта, `prototypes/gantt.html`, документация.
- **Результат:** масштабы день/неделя/месяц; плановые и фактические полосы; фильтры по категориям и приоритету; переключатель факта; просрочка; переход к задаче; изменение дат через редактор.
- **Команды:** `flutter analyze`; `flutter test`; `flutter build macos/apk/ios`.
- **Проверки:** 74 client-теста, 0 падений; сборки macOS/Android/iOS; узкий экран.
- **Ошибки:** `Spacer` внутри `Wrap` вызывал ошибку ParentData — убран; полосы обрезаются и не выходят за диапазон.
- **Ограничения:** нет зависимостей, критического пути, ресурсов и drag-изменения дат.
- **Следующий шаг:** локальный поиск.

## 2026-11-06 — Локальный поиск

- **Цель:** поиск заметок и задач офлайн с фильтрами, подсветкой и переходом к объекту.
- **Изменённые файлы:** `features/search/*`, иконки поиска в шапках разделов, тесты, `prototypes/search.html`, документация.
- **Результат:** полноэкранный поиск; поиск по заголовку/тексту заметок и названию/описанию/дорожке/категории задач; регистронезависимый поиск с кириллицей; группировка, фильтры, подсветка, переход к заметке/задаче.
- **Команды:** `flutter analyze`; `flutter test`; `flutter build macos/apk/ios`.
- **Проверки:** 88 client-тестов, 0 падений; сборки macOS/Android/iOS; узкий экран.
- **Ошибки:** в тесте поиска не подменялся `lanesProvider`, из-за чего задача не открывалась — исправлено.
- **Ограничения:** без FTS, вложений и AI-поиска.
- **Следующий шаг:** вложения.

## 2026-11-06 — Вложения

- **Цель:** файлы у заметок и задач, проверки, локальное хранение, upload/download и sync metadata.
- **Изменённые файлы:** `features/attachments/*`, `core/database/*`, `features/sync/*`, `features/notes/*`, `features/tasks/*`, `services/api` (V7, attachment API/storage), тесты, `prototypes/attachments.html`, документация.
- **Результат:** серверный диск `ATTACHMENTS_DIR`; лимит 25 МБ; allowlist типов; SHA-256; идемпотентная загрузка; локальная схема v5; статусы; панель вложений; metadata через change log; скачивание на других устройствах.
- **Команды:** `flutter analyze`; `flutter test`; `./gradlew cleanTest test`; e2e с временным PostgreSQL/backend и реальным upload/download; сборки macOS/Android/iOS.
- **Проверки:** 99 client-тестов, 31 backend-тест, e2e с ATTACHMENT пройден.
- **Ошибки:** загрузка ошибочного ответа парсилась как AttachmentResponse — тест переведён на raw response; `file_selector` в тестах требует путь у XFile; панель переполнялась на узком экране — заголовок переведён на Wrap.
- **Ограничения:** папку вложений нужно включить в backup; нет открытия всех типов файлов; Windows не проверен.
- **Следующий шаг:** AI Approval.

## 2026-11-06 — AI Approval

- **Цель:** ассистент анализирует данные и готовит предложения, но применяет изменения только после подтверждения; журнал и запрет прямого доступа к БД/ФС.
- **Решения пользователя:** локальный rule-based провайдер без внешних API; отдельная вкладка AI в нижней навигации (D-032).
- **Изменённые файлы:** `features/ai/*`, `core/database/*` (схема v6, `ai_actions`), `features/notes/data/notes_repository.dart`, `features/tasks/data/lanes_repository.dart`, `app/home_shell.dart`, тесты AI и миграции, `prototypes/ai-approval.html`, документация.
- **Результат:** шестая вкладка AI; чат и аналитика; предложения перемещения задачи, переноса даты, напоминания, создания и дополнения заметки; diff «было / станет»; подтверждение, отказ и устаревание по `revision`/`updatedAt`; журнал `ai_actions`; экран приватности; инструкции внутри заметок не исполняются.
- **Команды:** `flutter analyze`; `flutter test`; `flutter build macos/apk/ios`.
- **Проверки:** 109 client-тестов, 0 падений; сборки macOS/Android/iOS. Backend не изменялся, 31 тест остаётся с этапа 11.
- **Ошибки:** regex с кириллическими кавычками внутри raw-строки не парсился — заменён на тройные кавычки; сигнатура `_notFoundMessage` и её вызовы рассинхронизировались — приведены к двум аргументам; миграционный тест ожидал v5 — обновлён до v6 с проверкой `ai_actions`.
- **Ограничения:** rule-based ассистент понимает ограниченный набор команд; журнал AI локален и не синхронизируется; нет AI-поиска по вложениям и фоновых действий.
- **Следующий шаг:** backup/restore.

## 2026-11-06 — Backup/restore

- **Цель:** резервное копирование PostgreSQL, вложений и локальных данных, шифрование, проверка и безопасное восстановление.
- **Решения пользователя:** отдельный диск; age с ключевым файлом и офлайн-копией; вручную из приложения и CLI; 7 + 4 недельных + 6 месячных; снимки локальных БД на сервер; статус в верхней левой полосе на всех экранах (D-033).
- **Изменённые файлы:** `services/api/.../backup/*`, `application.yml`, `apps/client/lib/features/backup/*`, `app/app.dart`, настройки, тесты, `scripts/backup/*`, `prototypes/backup-restore.html`, документация и OpenAPI.
- **Результат:** серверный backup с `pg_dump` + вложения + снимки устройств → ZIP → age; проверка SHA-256/manifest/`pg_restore --list`; политика хранения; снимки SQLite и журнала AI по 3 на устройство; API статуса/запуска/проверки/скачивания; глобальная полоса статуса; экран backup; CLI init/run/restore; восстановление только в новую БД.
- **Команды:** `flutter analyze`; `flutter test`; `./gradlew cleanTest test`; e2e Docker PostgreSQL + реальный `age` + CLI; сборки macOS/Android/iOS.
- **Проверки:** 118 client-тестов, 38 backend-тестов, e2e backup и restore в новую БД; сборки macOS debug, Android debug APK, iOS simulator.
- **Ошибки:** `@Value("spring.datasource.url")` не видел URL Testcontainers — заменено на `JdbcConnectionDetails`; `pg_dump` 18 создавал дамп, несовместимый с `pg_restore` 16 (`transaction_timeout`) — используется клиент PostgreSQL 16; тест удалял `attachments/tmp` — каталог пересоздаётся; `return` внутри `withUserLock` заменён на возврат значения; в скрипте восстановления `$TARGET_DB` перед многоточием ломал разбор — добавлены фигурные скобки.
- **Ограничения:** один диск не заменяет 3-2-1; потеря ключа age = потеря копий; расписания нет; восстановление на чистом сервере вручную не проверялось; Windows не проверен.
- **Следующий шаг:** подготовка релиза (macOS signing/notarization, Windows CI, физические устройства).

## 2026-11-06 — Настройка релиза 14a

- **Цель:** подготовить release-сборки и установку на личные устройства без CI и платных сервисов.
- **Решения пользователя:** macOS вне App Store; iPhone 11 Pro; Samsung Galaxy A30s; Windows-ноутбук; установщик Windows; CI нет; бесплатный Apple personal team; Windows без сертификата; версия 0.1.0+1; имя «Ежедневник» (D-034).
- **Изменённые файлы:** `AndroidManifest.xml`, `strings.xml`, Android `build.gradle.kts`, iOS/macOS Info.plist, Windows `main.cpp`/`Runner.rc`, `.gitignore`, `scripts/release/*`, `installer/windows/*`, `docs/RELEASE.md`, `docs/RELEASE_CHECKLIST.md`, документация.
- **Результат:** имя «Ежедневник»; Android release подписан release keystore и проверен `apksigner`; macOS release ad-hoc + DMG; iOS release с `--no-codesign`; Windows Inno Setup и PowerShell-скрипт; инструкции по секретам и установке.
- **Команды:** `flutter analyze`; `flutter test`; `./gradlew cleanTest test`; `flutter build apk --release`; `flutter build macos --release`; `scripts/release/build-macos-dmg.sh`; `flutter build ios --release --no-codesign`.
- **Проверки:** 118 client-тестов, 38 backend-тестов; Android APK подпись v2 и label; macOS ad-hoc подпись и монтирование DMG; iOS bundle/display name; Windows не собран.
- **Ошибки:** `key.properties` не создался из-за относительного пути — скопирован в `apps/client/android`; keystore получил 644 из-за `set -e` до `chmod` — права исправлены на 600; ad-hoc macOS ожидаемо отклоняется `spctl`, добавлена инструкция снятия quarantine.
- **Ограничения:** notarization и TestFlight недоступны без платного Apple-аккаунта; iPhone-профиль 7 дней; Windows, iPhone и Samsung не проверены; Android release требует удаления debug-приложения.
- **Следующий шаг:** проверка на устройствах по `docs/RELEASE_CHECKLIST.md`; при необходимости 14b с платным Apple-аккаунтом.
