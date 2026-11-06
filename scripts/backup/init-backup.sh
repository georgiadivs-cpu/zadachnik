#!/usr/bin/env bash
set -euo pipefail

# Создаёт ключ age для резервных копий и каталог на отдельном диске.
# Пароль от офлайн-копии ключа задаётся отдельно в менеджере паролей.
# Повторный запуск не перезаписывает существующий ключ.

BACKUP_DIR="${1:-${BACKUP_DIR:-}}"
KEY_PATH="${2:-${BACKUP_AGE_IDENTITY:-}}"

if [[ -z "$BACKUP_DIR" || -z "$KEY_PATH" ]]; then
  echo "Usage: $0 <backup-dir> <age-identity-path>" >&2
  echo "Или задайте BACKUP_DIR и BACKUP_AGE_IDENTITY." >&2
  exit 2
fi

if ! command -v age-keygen >/dev/null 2>&1; then
  echo "age-keygen не найден. Установите age (brew install age / apt install age)." >&2
  exit 1
fi

if [[ -e "$KEY_PATH" ]]; then
  echo "Ключ уже существует: $KEY_PATH. Не перезаписываю." >&2
  exit 1
fi

mkdir -p "$(dirname "$KEY_PATH")"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

umask 077
age-keygen -o "$KEY_PATH"
chmod 600 "$KEY_PATH"

RECIPIENT="$(age-keygen -y "$KEY_PATH" | head -n 1)"
cat <<EOF

Ключ создан: $KEY_PATH (права 0600)
Публичный recipient: $RECIPIENT
Каталог копий: $BACKUP_DIR

Обязательно сделайте офлайн-копию ключа:
  1. Скопируйте $KEY_PATH в менеджер паролей или на бумагу.
  2. Не храните единственную копию только на сервере.
  3. Пароль от офлайн-копии держите отдельно.

Переменные для сервера:
  BACKUP_DIR=$BACKUP_DIR
  BACKUP_AGE_IDENTITY=$KEY_PATH
  BACKUP_AGE_RECIPIENT=$RECIPIENT
  BACKUP_PG_DUMP=$(command -v pg_dump || echo pg_dump)
  BACKUP_PG_RESTORE=$(command -v pg_restore || echo pg_restore)
EOF
