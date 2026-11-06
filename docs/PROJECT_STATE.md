# PROJECT_STATE — Ежедневник

**Обновлено:** 2026-11-06
**Текущий шаг:** настройка релиза 14a — завершена
**Следующий шаг:** проверка на устройствах; 14b после платного Apple-аккаунта

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
| Release-конфигурация Android/macOS | ✅ |
| Windows-установщик | ⏳ скрипт готов, сборка ожидает |
| Проверка на iPhone/Android/Windows | ⏳ ожидает |
| macOS notarization и TestFlight | ⏳ нужен платный Apple-аккаунт |
| Связи задач с заметками/чек-листами | ⏳ отложены |
| UI разрешения конфликтов | ⏳ следующий уровень |

## 2. Проверки

- Backend: `./gradlew cleanTest test` — **38 тестов**.
- Client: `flutter test` — **118 тестов**, 1 e2e пропущен без backend.
- Client + реальный backend/PostgreSQL: e2e backup/restore через CLI
  пройден; интеграционный тест проверяет архив, вложения и
  восстановление в отдельную БД.
- macOS: release-сборка и ad-hoc DMG; `codesign --verify` проходит,
  `spctl` отклоняет ad-hoc — ожидаемо.
- Android: release APK, подпись v2, label «Ежедневник», minSdk 24.
- iOS: release-сборка с `--no-codesign`; установка на устройство ожидает.
- Windows: не собирался, скрипт и Inno Setup подготовлены.
- Сборки: macOS release, Android release, iOS release; debug-сборки
  также проходят.

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
- версия приложения: `0.1.0+1`, имя «Ежедневник»;
- bundle/application ID не менялись;
- Android release keystore: `~/.zadachnik/keys/zadachnik-release.jks`;
- API: `/api/v1/auth/*`, `/api/v1/devices`, `/api/v1/sync/*`,
  `/api/v1/attachments/*`, `/api/v1/backups/*`;
- серверные файлы: `ATTACHMENTS_DIR`;
- архивы: `BACKUP_DIR`, отдельный диск, `.zip.age`;
- macOS: ad-hoc подпись, sandbox отключён.

## 4. Артефакты и ключевые файлы

- `dist/macos/zadachnik-0.1.0.dmg` — macOS ad-hoc;
- `dist/android/zadachnik-0.1.0.apk` — Android release;
- `apps/client/build/ios/iphoneos/Runner.app` — iOS без подписи;
- `installer/windows/zadachnik.iss` — Inno Setup;
- `scripts/release/build-macos-dmg.sh`;
- `scripts/release/build-android-release.sh`;
- `scripts/release/build-windows.ps1`;
- `docs/RELEASE.md`, `docs/RELEASE_CHECKLIST.md`;
- `apps/client/android/app/build.gradle.kts` — release signing;
- `apps/client/android/key.properties` — локальный секрет, Git игнорирует.

## 5. Известные проблемы

- macOS notarization и TestFlight требуют платного Apple Developer Program;
- iPhone-сборка живёт 7 дней;
- Android release поверх debug требует удаления debug-приложения;
- Windows-сборка, iPhone 11 Pro и Samsung A30s не проверены;
- один диск backup не заменяет 3-2-1;
- потеря ключа age означает потерю копий;
- потеря Android keystore блокирует обновление;
- вложения не проверены вручную на всех устройствах;
- нет UI разрешения конфликтов;
- внешние календари и повторяющиеся события не реализованы;
- Windows не поддерживает отмену уведомлений без MSIX;
- связи задач с заметками и чек-листами не реализованы.
