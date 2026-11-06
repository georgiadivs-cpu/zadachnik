# Резервные копии

Копии создаются вручную, хранятся на отдельном диске и шифруются `age`.
Рабочая БД и `ATTACHMENTS_DIR` не перезаписываются автоматически.

## 1. Подготовка сервера

Нужны:

- `age` и `age-keygen`;
- `pg_dump` и `pg_restore` версии, совместимой с PostgreSQL сервера
  (для PostgreSQL 16 используйте клиент 16);
- отдельный диск, смонтированный, например, в
  `/Volumes/ZadachnikBackup`.

Создайте ключ и каталог:

```bash
./scripts/backup/init-backup.sh \
  /Volumes/ZadachnikBackup/zadachnik \
  /etc/zadachnik/backup.key
```

Сразу сделайте офлайн-копию `backup.key`: менеджер паролей или бумага.
Пароль от офлайн-копии храните отдельно. Если ключ потерян, копии
расшифровать нельзя.

Переменные сервера:

```bash
BACKUP_DIR=/Volumes/ZadachnikBackup/zadachnik
BACKUP_AGE_IDENTITY=/etc/zadachnik/backup.key
BACKUP_AGE_RECIPIENT=age1...
BACKUP_PG_DUMP=/opt/homebrew/opt/postgresql@16/bin/pg_dump
BACKUP_PG_RESTORE=/opt/homebrew/opt/postgresql@16/bin/pg_restore
```

## 2. Запуск из приложения

Откройте «Настройки → Резервные копии» или нажмите полосу статуса
в верхней части экрана. Кнопка «Создать копию» запускает серверный
процесс; приложение опрашивает статус.

## 3. Запуск из CLI

Нужен access token устройства:

```bash
ZADACHNIK_TOKEN='<access token>' \
API_BASE_URL='http://localhost:8080' \
./scripts/backup/run-backup.sh
```

Скрипт запускает копирование и ждёт завершения.

## 4. Проверка восстановления

Скрипт создаёт **новую** БД и **новую** папку вложений. Рабочая БД
не изменяется.

```bash
PGHOST=localhost PGPORT=5433 PGUSER=zadachnik PGPASSWORD=... \
./scripts/backup/restore-verify.sh \
  --archive /Volumes/ZadachnikBackup/zadachnik/<user>/archives/xxx.zip.age \
  --key /etc/zadachnik/backup.key \
  --attachments-target /Volumes/ZadachnikRestore/attachments
```

Скрипт проверяет manifest и SHA-256, восстанавливает дамп в новую БД,
извлекает вложения и печатает количество записей. Переключение
приложения на восстановленную БД выполняется вручную после проверки.

## 5. Политика хранения

- 7 последних копий;
- по одной за последние 4 ISO-недели;
- по одной за последние 6 календарных месяцев;
- последние 3 снимка на устройство;
- последняя проверенная копия не удаляется.

Старые копии удаляются только после успешной проверки новой.

## 6. Ограничения

- один диск не заменяет схему 3-2-1; периодически копируйте самый
  свежий проверенный архив на второй офлайн-носитель;
- расписания нет — запуск только вручную;
- приложение не выполняет восстановление поверх рабочей БД;
- Windows-сценарий backup/restore не проверялся.
