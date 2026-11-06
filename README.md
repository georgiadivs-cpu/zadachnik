# Ежедневник — документация проекта

Персональное кроссплатформенное приложение для управления
заметками, задачами и временем.

## Быстрый старт для агента

1. Прочитай корневой AGENTS.md полностью.
2. Изучи документы из docs/README.md.
3. Перед изменением требований проверь PRODUCT_SPEC.md и DECISIONS.md.
4. Для специализированной работы прочитай соответствующий skill.
5. Перед изменением кода составь план, перечисли затрагиваемые файлы,
   риски и тесты.
6. Не выполняй опасные или необратимые действия без подтверждения пользователя.

## Структура

- AGENTS.md — обязательные правила работы агента.
- docs/PRODUCT_SPEC.md — требования продукта.
- docs/ARCHITECTURE.md — архитектура.
- docs/API_CONTRACTS.md — контракт API.
- docs/SYNC_PROTOCOL.md — протокол синхронизации.
- docs/DATA_MODEL.md — модель данных.
- docs/SECURITY.md — безопасность и приватность.
- docs/UI_UX.md — интерфейс и пользовательские сценарии.
- docs/ACCEPTANCE_CRITERIA.md — критерии приёмки.
- docs/DECISIONS.md — журнал решений.
- docs/DEVELOPMENT_WORKFLOW.md — процесс разработки.
- docs/HANDOFF.md, PROJECT_STATE.md, WORK_LOG.md, MVP_ROADMAP.md, NEXT_STEPS.md — история проекта.
- .agents/skills/ — специализированные инструкции.
- apps/client/ — Flutter-клиент: Android, iOS, macOS, Windows.
- services/api/ — Kotlin + Spring Boot API.
- packages/contracts/ — OpenAPI и общие контракты.
- infrastructure/ — локальные сервисы и окружение.
- ai/ — правила AI, стандарты кода, Definition of Done и шаблон задачи.
- tests/ — стратегия тестирования.

## Источник истины

- Продуктовые требования: PRODUCT_SPEC.md.
- Архитектурные ограничения: ARCHITECTURE.md.
- API и синхронизация: API_CONTRACTS.md, SYNC_PROTOCOL.md.
- Сущности и связи: DATA_MODEL.md.
- Требования безопасности: SECURITY.md.
- Поведение интерфейса: UI_UX.md.
- Проверяемая готовность: ACCEPTANCE_CRITERIA.md.
- Принятые решения и открытые вопросы: DECISIONS.md.

Если документы противоречат друг другу, агент не должен
самостоятельно выбирать трактовку.

Он обязан описать противоречие и запросить решение пользователя.
До решения действует наиболее безопасное поведение,
не приводящее к потере данных.

## Локальный запуск

```bash
# PostgreSQL
cp infrastructure/.env.example infrastructure/.env
docker compose --env-file infrastructure/.env \
  -f infrastructure/docker-compose.yml up -d --wait

# API
cd services/api && \
  DATABASE_URL=jdbc:postgresql://localhost:5433/zadachnik \
  DATABASE_USER=zadachnik \
  DATABASE_PASSWORD=zadachnik \
  JWT_SECRET='local-dev-secret-0123456789-abcdefghij' \
  SETUP_TOKEN='local-setup-token' \
  ./gradlew bootRun

# Клиент
cd apps/client && flutter pub get && \
  dart run build_runner build && \
  flutter run -d macos
```

Резервные копии и восстановление: `scripts/backup/README.md`.
