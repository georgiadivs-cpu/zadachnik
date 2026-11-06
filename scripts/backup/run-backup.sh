#!/usr/bin/env bash
set -euo pipefail

# Запускает резервное копирование на сервере через API и ждёт результата.
# Требуется access token: ZADACHNIK_TOKEN (получить через /api/v1/auth/login).
# Пример:
#   ZADACHNIK_TOKEN=... ./scripts/backup/run-backup.sh

API_BASE_URL="${API_BASE_URL:-http://localhost:8080}"
TOKEN="${ZADACHNIK_TOKEN:-}"

if [[ -z "$TOKEN" ]]; then
  echo "Задайте ZADACHNIK_TOKEN (access token устройства)." >&2
  exit 2
fi
if ! command -v curl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  echo "Нужны curl и python3." >&2
  exit 1
fi

auth=(-H "Authorization: Bearer $TOKEN")

status_json="$(curl -fsS "${auth[@]}" "$API_BASE_URL/api/v1/backups/status")"
read -r before_count running < <(printf '%s' "$status_json" | python3 -c '
import json,sys
d=json.load(sys.stdin)
print(len(d.get("archives", [])), str(d.get("state", {}).get("running", False)).lower())
')
if [[ "$running" == "true" ]]; then
  echo "Копирование уже выполняется." >&2
  exit 1
fi

echo "Запускаю резервное копирование…"
curl -fsS -X POST "${auth[@]}" "$API_BASE_URL/api/v1/backups" >/dev/null

while true; do
  status_json="$(curl -fsS "${auth[@]}" "$API_BASE_URL/api/v1/backups/status")"
  read -r running error < <(printf '%s' "$status_json" | python3 -c '
import json,sys
d=json.load(sys.stdin)
state=d.get("state", {})
print(str(state.get("running", False)).lower(), state.get("lastError") or "")
')
  if [[ "$running" == "false" ]]; then
    break
  fi
  sleep 2
done

printf '%s' "$status_json" | python3 -c '
import json,sys
d=json.load(sys.stdin)
state=d.get("state", {})
archives=d.get("archives", [])
error=state.get("lastError")
if error:
    print("Ошибка backup: " + error, file=sys.stderr)
    raise SystemExit(1)
if not archives:
    print("Сервер не вернул ни одной копии.", file=sys.stderr)
    raise SystemExit(1)
a=archives[0]
print("Готово: %s · %.2f МБ · проверено: %s" % (
    a.get("fileName"),
    (a.get("sizeBytes") or 0) / 1024 / 1024,
    "да" if a.get("verifiedAt") else "нет",
))
'

after_count="$(printf '%s' "$status_json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("archives", [])))')"
if [[ "$after_count" -le "$before_count" ]]; then
  echo "Предупреждение: число копий не увеличилось (возможна ротация)." >&2
fi
