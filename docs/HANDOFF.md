# HANDOFF — Ежедневник

**Обновлено:** 2026-11-06
**Текущий этап:** настройка релиза 14a — завершена
**Следующий шаг:** проверка на устройствах; 14b после платного Apple-аккаунта
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
- AI Approval с локальным rule-based ассистентом;
- резервное копирование и безопасная проверка восстановления;
- release-конфигурация Android и macOS;
- Windows Inno Setup и iOS-инструкция;
- HTML-прототипы MVP и завершённых шагов.

## Проверки этапа 14a

- `flutter analyze` — чисто.
- `flutter test` — **118 тестов**, 0 падений.
- backend `./gradlew cleanTest test` — **38 тестов**, 0 падений.
- Android release APK собран, подпись v2 проверена, label «Ежедневник».
- macOS release собран, ad-hoc подпись проверена, DMG создан.
- iOS release собран с `--no-codesign`; установка на устройство ожидает.
- Windows-сборка на macOS не выполнялась; скрипт и Inno Setup готовы.
- Устройства iPhone 11 Pro, Samsung A30s и Windows-ноутбук ещё не проверены.

## Артефакты

- `dist/macos/zadachnik-0.1.0.dmg` — ad-hoc macOS;
- `dist/android/zadachnik-0.1.0.apk` и `.sha256` — подписанный Android;
- `apps/client/build/ios/iphoneos/Runner.app` — iOS без подписи;
- Windows-установщик собирается на Windows:
  `powershell -ExecutionPolicy Bypass -File .\scripts\release\build-windows.ps1`.

## Ключевое в релизе

- версия `0.1.0+1`, имя «Ежедневник»;
- bundle/application ID не менялись;
- macOS без notarization: Gatekeeper предупреждает, нужен обход;
- iPhone — бесплатный профиль на 7 дней, без TestFlight;
- Android release keystore: `~/.zadachnik/keys/zadachnik-release.jks`;
- пароль и alias: `~/.zadachnik/keys/android.properties` и
  `apps/client/android/key.properties`, права `600`, Git игнорирует;
- Windows-установщик без подписи, SmartScreen может предупредить;
- CI отсутствует, проверки ручные.

## Известные ограничения

- macOS notarization и TestFlight недоступны без платного Apple Developer Program;
- iPhone-сборка требует переустановки каждые 7 дней;
- при установке Android release поверх debug нужно удалить debug-приложение; локальные данные пропадут без backup;
- Windows-сборка и установка ещё не проверены;
- iPhone 11 Pro и Samsung A30s ещё не проверены;
- один диск backup не заменяет 3-2-1;
- потеря ключа age означает потерю копий;
- macOS signing/notarization не настроены.

## Следующий шаг

1. Установить и проверить macOS DMG на Mac M1.
2. Установить iOS-сборку через Xcode на iPhone 11 Pro.
3. Установить Android APK на Samsung A30s (сначала backup).
4. Собрать Windows-установщик на ноутбуке и проверить.
5. Пройти `docs/RELEASE_CHECKLIST.md`.
6. При необходимости оформить Apple Developer Program и выполнить 14b:
   Developer ID, notarization, TestFlight.

## Документация

- `PRODUCT_SPEC.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`, `SECURITY.md`, `UI_UX.md`;
- `API_CONTRACTS.md`, `SYNC_PROTOCOL.md`;
- `ACCEPTANCE_CRITERIA.md`, `DEVELOPMENT_WORKFLOW.md`, `DECISIONS.md`;
- `PROJECT_STATE.md`, `WORK_LOG.md`, `MVP_ROADMAP.md`, `NEXT_STEPS.md`;
- `RELEASE.md`, `RELEASE_CHECKLIST.md`, `scripts/backup/README.md`.
