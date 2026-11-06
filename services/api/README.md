# API «Ежедневник»

Kotlin + Spring Boot + PostgreSQL.

## Локальный запуск

```bash
cp infrastructure/.env.example infrastructure/.env
docker compose --env-file infrastructure/.env \
  -f infrastructure/docker-compose.yml up -d --wait

cd services/api
DATABASE_URL=jdbc:postgresql://localhost:5433/zadachnik \
DATABASE_USER=zadachnik \
DATABASE_PASSWORD=zadachnik \
JWT_SECRET='local-dev-secret-0123456789-abcdefghij' \
SETUP_TOKEN='local-setup-token' \
./gradlew bootRun
```

Health: `http://localhost:8080/actuator/health`.

## API

- `POST /api/v1/auth/setup` — первый владелец;
- `POST /api/v1/auth/login` — вход устройства;
- `POST /api/v1/auth/refresh`, `POST /api/v1/auth/logout`;
- `GET /api/v1/devices`, `DELETE /api/v1/devices/{id}`;
- `POST /api/v1/sync/push` — операции заметок;
- `GET /api/v1/sync/pull` — изменения после cursor;
- `GET /api/v1/sync/state`;
- `GET /api/v1/backups/status`, `POST /api/v1/backups`,
  `POST /api/v1/backups/{id}/verify`,
  `GET /api/v1/backups/{id}/download`;
- `POST /api/v1/backups/devices` — снимок SQLite устройства.

Синхронизация поддерживает `NOTE`, `TASK`, `LANE`, `REMINDER`.
Резервные копии требуют `age`, `pg_dump` и `pg_restore`; см.
`scripts/backup/README.md`.

## Проверки

```bash
./gradlew test
./gradlew bootJar
```

Интеграционные тесты используют PostgreSQL через Testcontainers.
Тест резервных копий требует установленные `age` и клиент PostgreSQL
совместимой версии.
