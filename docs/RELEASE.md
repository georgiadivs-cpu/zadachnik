# RELEASE — Ежедневник

**Версия:** 0.1.0+1
**Дата:** 2026-11-06
**Статус:** настройка релиза 14a; проверка на физических устройствах ожидает

## 1. Принятая модель распространения

- macOS — вне App Store, ad-hoc подпись и DMG;
- iPhone — прямая установка через Xcode с бесплатным personal team;
- Android — подписанный release APK;
- Windows — Inno Setup, установщик без подписи;
- CI отсутствует, все сборки и проверки ручные.

Платный Apple Developer Program не используется. Поэтому недоступны:

- notarization macOS;
- TestFlight;
- годичные provisioning profiles (бесплатный профиль — 7 дней).

## 2. Секреты и их хранение

### Apple

Нужны только для прямой установки на iPhone:

- Apple ID и personal team;
- iOS Development certificate (`.p12`) — если Xcode создаёт его автоматически, отдельно экспортировать только для резервной копии;
- provisioning profile (`.mobileprovision`).

Рекомендации:

- хранить `.p12` и профиль в менеджере паролей;
- сделать офлайн-копию на зашифрованном USB;
- не хранить в iCloud Drive и репозитории;
- профиль продлевать/пересобирать каждые 7 дней.

После перехода на платный аккаунт появятся Developer ID, App Store Connect API key и TestFlight. Их нельзя переиспользовать от бесплатного team.

### Android

- Keystore: `~/.zadachnik/keys/zadachnik-release.jks`.
- Пароль и alias: `~/.zadachnik/keys/android.properties` и `apps/client/android/key.properties`.
- Оба файла имеют права `600` и исключены из Git.
- Обязательно скопировать keystore и пароль в менеджер паролей и на офлайн-носитель.
- Потеря keystore не позволяет обновить установленное приложение без удаления.

### Windows

Сертификат не используется. Установщик не подписан, SmartScreen может показать предупреждение. Пользователь проверяет SHA-256 рядом с установщиком.

### Общие правила

- Не коммитить `*.p12`, `*.p8`, `*.jks`, `*.keystore`, `key.properties`, `*.mobileprovision`.
- Не печатать пароли в логи и терминал.
- Резервная копия секретов: менеджер паролей + офлайн-копия + проверка восстановления.
- При компрометации — отзыв сертификата/смена пароля keystore.

## 3. macOS

### Сборка

```bash
cd apps/client
flutter build macos --release
```

### DMG

```bash
./scripts/release/build-macos-dmg.sh
```

Результат: `dist/macos/zadachnik-0.1.0.dmg`.

Скрипт:

- подписывает приложение ad-hoc (`codesign --sign -`);
- проверяет подпись;
- собирает DMG с томом «Ежедневник».

### Установка

1. Открыть DMG.
2. Перетащить `zadachnik_client.app` в `/Applications`.
3. Снять quarantine:

```bash
xattr -dr com.apple.quarantine '/Applications/zadachnik_client.app'
```

Или открыть через правый клик → «Открыть».

`spctl` намеренно отклоняет ad-hoc сборку. Это ожидаемо без notarization.

### Ограничение

Для запуска без предупреждений на чужих Mac нужен платный Apple Developer Program и notarization.

## 4. iPhone 11 Pro

Бесплатный personal team:

1. Подключить iPhone к Mac, доверять компьютеру.
2. Открыть `apps/client/ios/Runner.xcworkspace`.
3. Выбрать Runner → Signing & Capabilities → personal team.
4. Убедиться, что bundle ID `com.zadachnik.zadachnikClient` свободен; при конфликте Xcode предложит изменить.
5. Запустить:

```bash
cd apps/client
flutter run --release -d <device-id>
```

6. На iPhone: Настройки → Основные → VPN и управление устройством → доверять разработчику.

Ограничения:

- профиль действует 7 дней;
- после истечения приложение не запускается, нужно снова собрать/установить;
- TestFlight недоступен;
- данные приложения при переустановке обычно сохраняются, но это не гарантируется — сделайте backup.

## 5. Android

### Ключ

Ключ создан локально, не входит в репозиторий. Проверить:

```bash
ls -l ~/.zadachnik/keys/zadachnik-release.jks
ls -l apps/client/android/key.properties
```

Если ключа нет на другом Mac, восстановите его из менеджера паролей. Не создавайте новый ключ для уже выпущенного приложения.

### Сборка

```bash
./scripts/release/build-android-release.sh
```

Результат: `dist/android/zadachnik-0.1.0.apk` и `.sha256`.
Исходная сборка: `apps/client/build/app/outputs/flutter-apk/app-release.apk`.

Проверка:

```bash
"$HOME/Library/Android/sdk/build-tools/37.0.0/apksigner" verify --verbose \
  build/app/outputs/flutter-apk/app-release.apk
```

### Установка на Samsung A30s

Debug и release подписаны разными ключами. Если установлена debug-сборка:

1. Сделайте снимок устройства в «Резервные копии».
2. Удалите debug-приложение.
3. Установите release APK:

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

Минимальная версия Android — API 24. Samsung A30s подходит, но уведомления и точные будильники нужно проверить вручную.

## 6. Windows

Сборка выполняется на Windows-ноутбуке.

Требования:

- Flutter SDK;
- Visual Studio 2022 с C++ Desktop workload;
- Inno Setup 6.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\release\build-windows.ps1
```

Результат: `dist\windows\zadachnik-0.1.0-setup.exe` и `.sha256`.

Установщик:

- per-user, без администратора;
- ярлык в меню «Пуск»;
- опционально ярлык на рабочем столе;
- не удаляет пользовательские данные при удалении приложения;
- не подписан, SmartScreen может предупредить.

## 7. Проверки перед выдачей

См. `docs/RELEASE_CHECKLIST.md`.

Минимум:

- `flutter analyze`;
- `flutter test`;
- backend `./gradlew cleanTest test`;
- release-сборки;
- проверка подписи Android;
- установка и smoke-тест на каждом устройстве;
- backup и восстановление на Mac/Windows;
- проверка, что секреты не попали в Git:

```bash
git status --short
git log --all -- '*.jks' '*.p12' '*.p8' 'key.properties'
```

## 8. Откат

- macOS: предыдущий DMG сохранить в `dist/macos`; данные приложения не удаляются.
- Android: обновление возможно только тем же keystore; при проблеме — восстановить backup и переустановить предыдущую версию.
- iPhone: пересобрать предыдущий commit и установить заново.
- Windows: удалить приложение и установить предыдущий установщик; данные не удаляются.
