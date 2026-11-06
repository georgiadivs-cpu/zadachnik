# Инфраструктура

Локальная PostgreSQL для разработки и проверки API.
Проект Compose называется `zadachnik-local`, порт по умолчанию — `5433`.

```bash
cp infrastructure/.env.example infrastructure/.env
docker compose --env-file infrastructure/.env -f infrastructure/docker-compose.yml up -d --wait
```

Остановка:

```bash
docker compose --env-file infrastructure/.env -f infrastructure/docker-compose.yml down
```

Данные хранятся в volume `zadachnik-local_postgres-data`.

Пока в составе только PostgreSQL. Redis, очередь и файловое хранилище
добавляются после утверждения соответствующих решений.

Резервные копии требуют отдельный диск, `age` и клиент PostgreSQL
(`pg_dump`/`pg_restore`). Параметры `BACKUP_*` описаны в
`scripts/backup/README.md`.
