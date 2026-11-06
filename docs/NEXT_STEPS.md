# NEXT_STEPS — Ежедневник

**Текущий шаг:** проверка релиза 14a на устройствах
**Статус:** сборки готовы; iPhone, Android и Windows ещё не проверены
**Предыдущий шаг:** release-конфигурация 14a — завершена

## Цель

Установить `0.1.0+1` на все личные устройства, пройти smoke-тесты и
зафиксировать результат. Notarization и TestFlight отложены до
платного Apple Developer Program.

## Что готово

- Android release APK с release-подписью;
- macOS release DMG с ad-hoc подписью;
- iOS release-сборка без подписи;
- Windows Inno Setup и PowerShell-скрипт;
- `docs/RELEASE.md` и `docs/RELEASE_CHECKLIST.md`.

## Проверки на устройствах

- [ ] Mac M1: установка DMG, запуск после quarantine, sync, backup.
- [ ] iPhone 11 Pro: установка через Xcode, уведомления, файлы, backup.
- [ ] Samsung A30s: установка APK, уведомления, файлы, sync, backup.
- [ ] Windows-ноутбук: сборка установщика, установка/удаление, sync, backup.

## После проверки

- [ ] Исправить найденные дефекты.
- [ ] Обновить `docs/RELEASE_CHECKLIST.md` фактическими результатами.
- [ ] Зафиксировать известные ограничения.
- [ ] Сделать commit и push.

## 14b — после платного Apple-аккаунта

- [ ] Developer ID Application и hardened runtime.
- [ ] Notarization и staple DMG.
- [ ] TestFlight internal для iPhone.
- [ ] Убрать инструкцию обхода Gatekeeper.
- [ ] Проверить запуск на чистом Mac.

## Не входит

- App Store;
- CI;
- платный Windows-сертификат;
- автоматические обновления;
- телеметрия.
