#!/usr/bin/env bash
set -euo pipefail

# Безопасная проверка и восстановление архива в НОВУЮ базу и НОВУЮ папку.
# Рабочая БД и рабочие вложения не перезаписываются.
#
# Требования: age, unzip, pg_restore, psql, python3.
# Подключение к PostgreSQL задаётся через PGHOST/PGPORT/PGUSER/PGPASSWORD.
#
# Пример:
#   ./scripts/backup/restore-verify.sh \
#     --archive /Volumes/ZadachnikBackup/zadachnik/<user>/archives/xxx.zip.age \
#     --key ~/backup.key \
#     --attachments-target /Volumes/ZadachnikRestore/attachments

ARCHIVE=""
KEY="${BACKUP_AGE_IDENTITY:-}"
TARGET_DB=""
ATTACHMENTS_TARGET=""
ASSUME_YES="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive) ARCHIVE="${2:-}"; shift 2 ;;
    --key) KEY="${2:-}"; shift 2 ;;
    --target-db) TARGET_DB="${2:-}"; shift 2 ;;
    --attachments-target) ATTACHMENTS_TARGET="${2:-}"; shift 2 ;;
    --yes) ASSUME_YES="true"; shift ;;
    -h|--help)
      sed -n '1,25p' "$0"
      exit 0
      ;;
    *)
      echo "Неизвестный аргумент: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$ARCHIVE" || -z "$KEY" ]]; then
  echo "Укажите --archive и --key (или BACKUP_AGE_IDENTITY)." >&2
  exit 2
fi
if [[ ! -f "$ARCHIVE" ]]; then
  echo "Архив не найден: $ARCHIVE" >&2
  exit 1
fi
if [[ ! -f "$KEY" ]]; then
  echo "Ключ не найден: $KEY" >&2
  exit 1
fi

TARGET_DB="${TARGET_DB:-zadachnik_restore_$(date -u +%Y%m%d%H%M%S)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/zadachnik-restore.XXXXXX")"
cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "Расшифровываю архив…"
age --decrypt --identity "$KEY" --output "$WORK/archive.zip" "$ARCHIVE"

echo "Проверяю manifest и SHA-256…"
python3 - "$WORK/archive.zip" <<'PY'
import hashlib, json, sys, zipfile
archive = zipfile.ZipFile(sys.argv[1])
manifest = json.loads(archive.read("manifest.json"))
if manifest.get("formatVersion") != 1:
    raise SystemExit("Неподдерживаемая версия формата")
def verify(entry):
    info = archive.getinfo(entry["path"])
    digest = hashlib.sha256()
    total = 0
    with archive.open(entry["path"]) as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            total += len(chunk)
            digest.update(chunk)
    if total != entry["sizeBytes"] or digest.hexdigest() != entry["sha256"]:
        raise SystemExit("Проверка не пройдена: " + entry["path"])
for item in manifest.get("attachments", []) + manifest.get("deviceSnapshots", []):
    verify(item)
dump = manifest["databaseDump"]
data = archive.read(dump)
if hashlib.sha256(data).hexdigest() != manifest["databaseSha256"]:
    raise SystemExit("SHA-256 дампа БД не совпадает")
print("Manifest OK: заметок=%s, задач=%s, вложений=%s" % (
    manifest.get("counts", {}).get("notes", 0),
    manifest.get("counts", {}).get("tasks", 0),
    manifest.get("counts", {}).get("attachments", 0),
))
PY

unzip -q "$WORK/archive.zip" -d "$WORK/archive"
DUMP="$WORK/archive/database.dump"

if [[ "$ASSUME_YES" != "true" ]]; then
  echo
  echo "Будет создана НОВАЯ база: $TARGET_DB"
  if [[ -n "$ATTACHMENTS_TARGET" ]]; then
    echo "Вложения будут извлечены в: $ATTACHMENTS_TARGET"
  fi
  read -r -p "Продолжить? [y/N] " answer
  if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "Отменено. Рабочие данные не изменены."
    exit 1
  fi
fi

if psql -d postgres -tAc "select 1 from pg_database where datname='$TARGET_DB'" | grep -q 1; then
  echo "База уже существует: ${TARGET_DB}. Выберите другое имя." >&2
  exit 1
fi
psql -d postgres -v ON_ERROR_STOP=1 -c "create database \"$TARGET_DB\"" >/dev/null
echo "Восстанавливаю БД в ${TARGET_DB}…"
pg_restore --no-owner --no-privileges --dbname "$TARGET_DB" "$DUMP"

COUNTS="$(psql -d "$TARGET_DB" -tAc "
  select
    (select count(*) from notes where deleted_at is null),
    (select count(*) from tasks where deleted_at is null),
    (select count(*) from attachments where deleted_at is null)
")"
echo "Восстановлено (notes|tasks|attachments): $COUNTS"

if [[ -n "$ATTACHMENTS_TARGET" ]]; then
  if [[ -e "$ATTACHMENTS_TARGET" && -n "$(ls -A "$ATTACHMENTS_TARGET" 2>/dev/null || true)" ]]; then
    echo "Папка вложений не пуста: $ATTACHMENTS_TARGET. Не перезаписываю." >&2
    exit 1
  fi
  mkdir -p "$ATTACHMENTS_TARGET"
  if [[ -d "$WORK/archive/attachments" ]]; then
    cp -R "$WORK/archive/attachments/." "$ATTACHMENTS_TARGET/"
  fi
  echo "Вложения извлечены в $ATTACHMENTS_TARGET"
fi

cat <<EOF

Проверка завершена. Рабочая БД не изменялась.
Новая БД: $TARGET_DB
Для переключения приложения вручную:
  DATABASE_URL=jdbc:postgresql://<host>:<port>/$TARGET_DB
Перед переключением сделайте свежую резервную копию рабочей БД.
EOF
