# PROJECT_STATE — Ежедневник

**Обновлено:** 2026-11-06
**Текущий шаг:** локальный поиск — завершён
**Следующий шаг:** вложения (этап 11)

## 1. Статус

| Область | Статус |
|---|---|
| Документация продукта и архитектуры | ✅ |
| API и sync-протокол | ✅ описаны |
| Backend auth | ✅ реализован |
| Backend sync `NOTE`/`TASK`/`LANE`/`REMINDER` | ✅ |
| Flutter-каркас (4 платформы) | ✅ |
| Локальная БД и outbox | ✅ схема v4 |
| Клиентский вход и secure storage | ✅ |
| Клиентский sync | ✅ |
| Markdown-редактор | ✅ |
| TODO-доска | ✅ |
| Календарь и напоминания | ✅ |
| Диаграмма Ганта | ✅ |
| Локальный поиск | ✅ |
| Вложения | ⏳ этап 11 |
| AI Approval / backup | ⏳ не начаты |
| Связи задач с заметками/чек-листами | ⏳ отложены |
| UI разрешения конфликтов | ⏳ следующий уровень |

## 2. Проверки

- Backend: `./gradlew cleanTest test` — **27 тестов** (без изменений).
- Client: `flutter test` — **88 тестов**, 1 e2e пропущен без backend.
- Client + реальный backend/PostgreSQL: e2e NOTE + LANE + TASK + REMINDER — пройден.
- macOS: `integration_test/secure_storage_test.dart` — пройден.
- Сборки: macOS debug, Android debug APK, iOS simulator.
- Windows: не проверялся.

## 3. Техническое состояние

- клиент: Flutter 3.47.7, Riverpod, Drift, Dio, flutter_secure_storage;
- Markdown: `flutter_markdown_plus 1.0.12`;
- уведомления: `flutter_local_notifications 22.3.3`, `timezone 0.11.2`,
  `flutter_timezone 5.1.1`;
- backend: Kotlin 2.2.21, Spring Boot 3.5.16, PostgreSQL 16, Flyway;
- миграции backend: V1–V6;
- локальная схема: v4;
- API: `/api/v1/auth/*`, `/api/v1/devices`, `/api/v1/sync/*`;
- синхронизация поддерживает `NOTE`, `TASK`, `LANE`, `REMINDER`;
- поиск локальный, без FTS и backend;
- macOS app sandbox отключён для локального debug.

## 4. Ключевые файлы поиска

- `apps/client/lib/features/search/data/search_repository.dart` — поиск по Drift;
- `apps/client/lib/features/search/domain/search_result.dart` — модель результата;
- `apps/client/lib/features/search/presentation/search_page.dart` — экран поиска;
- `apps/client/lib/features/search/presentation/highlighted_text.dart` — подсветка;
- `apps/client/test/features/search/` — 14 тестов поиска;
- `prototypes/search.html` — принятый прототип.

## 5. Известные проблемы

- поиск сканирует данные в памяти и не использует FTS;
- нет поиска по вложениям и AI-поиска;
- дорожки/напоминания отображаются как метаданные задач;
- нет UI разрешения конфликтов;
- внешние календари и повторяющиеся события не реализованы;
- уведомления не проверены вручную на всех устройствах;
- Windows не поддерживает отмену уведомлений без MSIX;
- связи задач с заметками и чек-листами не реализованы;
- macOS signing/notarization не настроены.
