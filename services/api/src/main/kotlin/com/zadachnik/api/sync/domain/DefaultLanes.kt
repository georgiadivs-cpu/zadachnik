package com.zadachnik.api.sync.domain

import java.util.UUID

/** Стабильные ID дорожек по умолчанию: клиент и сервер создают одинаковый набор. */
object DefaultLanes {
    val NEW: UUID = UUID.fromString("00000000-0000-4000-8000-000000000101")
    val IN_PROGRESS: UUID = UUID.fromString("00000000-0000-4000-8000-000000000102")
    val REVIEW: UUID = UUID.fromString("00000000-0000-4000-8000-000000000103")
    val DONE: UUID = UUID.fromString("00000000-0000-4000-8000-000000000104")

    val all: List<Pair<UUID, String>> = listOf(
        NEW to "Новые",
        IN_PROGRESS to "В работе",
        REVIEW to "Проверка",
        DONE to "Готово",
    )
}
