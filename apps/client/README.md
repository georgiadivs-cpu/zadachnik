# Клиент «Ежедневник»

Flutter-клиент для Android, iOS, macOS и Windows.

## Запуск

```bash
cd apps/client
flutter pub get
dart run build_runner build
flutter run -d macos
```

## Проверки

```bash
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator --no-codesign
flutter build macos --debug
```

Windows-сборка выполняется на Windows-машине или в CI с Windows:
на macOS она недоступна.

## Структура

- `lib/app` — оболочка приложения и навигация;
- `lib/core/database` — Drift-схема и подключение;
- `lib/features/notes` — domain/data/application/presentation заметок;
- `lib/features/tasks` — TODO-доска, задачи, дорожки и история;
- `lib/features/calendar` — календарь, напоминания и уведомления;
- `lib/features/gantt` — диаграмма Ганта;
- `lib/features/settings` — настройки.
