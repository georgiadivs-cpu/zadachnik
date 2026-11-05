package com.zadachnik.api.identity.infrastructure

import com.zadachnik.api.identity.domain.DevicePlatform
import com.zadachnik.api.identity.domain.DeviceRecord
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository

@Repository
class DeviceRepository(private val jdbc: JdbcClient) {

    fun findById(id: UUID): DeviceRecord? =
        jdbc.sql(
            """
            select id, user_id, name, platform, created_at, last_seen_at, revoked_at
            from devices where id = :id
            """,
        )
            .param("id", id)
            .query { rs, _ -> map(rs) }
            .optional()
            .orElse(null)

    fun insert(
        id: UUID,
        userId: UUID,
        name: String,
        platform: DevicePlatform,
        now: Instant,
    ) {
        jdbc.sql(
            """
            insert into devices (id, user_id, name, platform, created_at, last_seen_at)
            values (:id, :userId, :name, :platform, :now, :now)
            """,
        )
            .param("id", id)
            .param("userId", userId)
            .param("name", name)
            .param("platform", platform.name)
            .param("now", now.atOffset(ZoneOffset.UTC))
            .update()
    }

    fun touch(id: UUID, now: Instant) {
        jdbc.sql("update devices set last_seen_at = :now where id = :id")
            .param("now", now.atOffset(ZoneOffset.UTC))
            .param("id", id)
            .update()
    }

    fun listForUser(userId: UUID): List<DeviceRecord> =
        jdbc.sql(
            """
            select id, user_id, name, platform, created_at, last_seen_at, revoked_at
            from devices where user_id = :userId order by created_at
            """,
        )
            .param("userId", userId)
            .query { rs, _ -> map(rs) }
            .list()

    fun revoke(id: UUID, now: Instant) {
        jdbc.sql("update devices set revoked_at = coalesce(revoked_at, :now) where id = :id")
            .param("now", now.atOffset(ZoneOffset.UTC))
            .param("id", id)
            .update()
    }

    private fun map(rs: java.sql.ResultSet): DeviceRecord = DeviceRecord(
        id = rs.getObject("id", UUID::class.java),
        userId = rs.getObject("user_id", UUID::class.java),
        name = rs.getString("name"),
        platform = DevicePlatform.valueOf(rs.getString("platform")),
        createdAt = rs.getObject("created_at", OffsetDateTime::class.java).toInstant(),
        lastSeenAt = rs.getObject("last_seen_at", OffsetDateTime::class.java)?.toInstant(),
        revokedAt = rs.getObject("revoked_at", OffsetDateTime::class.java)?.toInstant(),
    )
}
