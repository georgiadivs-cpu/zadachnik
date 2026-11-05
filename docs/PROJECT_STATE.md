# PROJECT_STATE — Ежедневник

**Обновлено:** 2026-11-05  
**Текущий шаг:** клиентский вход и secure session — завершён  
**Следующий шаг:** клиентский sync engine для `NOTE`

## 1. Статус

| Область | Статус |
|---|---|
| Документация продукта и архитектуры | ✅ |
| API и sync-протокол | ✅ описаны |
| Backend auth | ✅ реализован |
| Backend sync `NOTE` | ✅ реализован |
| Flutter-каркас (4 платформы) | ✅ |
| Локальная БД и outbox | ✅ |
| Клиентский вход | ✅ |
| Secure storage | ✅ на macOS проверен |
| Git-репозиторий | ✅ public `georgiadivs-cpu/zadachnik`, `main` |
| Клиентский sync | ⏳ следующий шаг |
| Markdown-редактор | ⏳ не реализован |
| TODO / календарь / Гант | ⏳ каркас экранов |
| Вложения / AI / backup | ⏳ не начаты |

## 2. Проверки

- Backend: `./gradlew test` — **18 тестов**.
- Client: `flutter test` — **11 тестов**.
- macOS: `integration_test/secure_storage_test.dart` — пройден.
- Сборки: macOS debug, Android debug APK, iOS simulator.
- Windows: не проверялся.

## 3. Техническое состояние

- клиент: Flutter 3.47.7, Riverpod, Drift, Dio, flutter_secure_storage;
- backend: Kotlin 2.2.21, Spring Boot 3.5.16, PostgreSQL 16, Flyway;
- миграции: V1 notes, V2 identity, V3 note sync, V4 request hash;
- API: `/api/v1/auth/*`, `/api/v1/devices`, `/api/v1/sync/*`;
- синхронизация поддерживает только `NOTE`;
- macOS app sandbox отключён для локального debug;
- Windows-сборка требует отдельной платформы/CI.

## 4. Известные проблемы

- нет клиентского sync engine и UI конфликтов;
- `notes.user_id` nullable для старых строк;
- лимит push 1 MiB проверяется по Content-Length;
- нет rate limiting;
- macOS secure storage использует legacy Keychain;
- App Store/macOS distribution signing не настроены;
- Markdown отображается как обычный текст.
