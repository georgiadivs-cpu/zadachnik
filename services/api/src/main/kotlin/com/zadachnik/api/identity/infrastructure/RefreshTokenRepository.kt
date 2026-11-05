package com.zadachnik.api.identity.infrastructure

import com.zadachnik.api.identity.domain.RefreshTokenRecord
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository

@Repository
class RefreshTokenRepository(private val jdbc: JdbcClient) {

    fun findByHash(tokenHash: String): RefreshTokenRecord? =
        jdbc.sql(
            """
            select id, user_id, device_id, token_hash, expires_at, revoked_at, replaced_by
            from refresh_tokens where token_hash = :hash
            """,
        )
            .param("hash", tokenHash)
            .query { rs, _ ->
                RefreshTokenRecord(
                    id = rs.getObject("id", UUID::class.java),
                    userId = rs.getObject("user_id", UUID::class.java),
                    deviceId = rs.getObject("device_id", UUID::class.java),
                    tokenHash = rs.getString("token_hash"),
                    expiresAt = rs.getObject("expires_at", OffsetDateTime::class.java).toInstant(),
                    revokedAt = rs.getObject("revoked_at", OffsetDateTime::class.java)?.toInstant(),
                    replacedBy = rs.getObject("replaced_by", UUID::class.java),
                )
            }
            .optional()
            .orElse(null)

    fun insert(
        id: UUID,
        userId: UUID,
        deviceId: UUID,
        tokenHash: String,
        expiresAt: Instant,
        now: Instant,
    ) {
        jdbc.sql(
            """
            insert into refresh_tokens
                (id, user_id, device_id, token_hash, expires_at, created_at)
            values (:id, :userId, :deviceId, :tokenHash, :expiresAt, :now)
            """,
        )
            .param("id", id)
            .param("userId", userId)
            .param("deviceId", deviceId)
            .param("tokenHash", tokenHash)
            .param("expiresAt", expiresAt.atOffset(ZoneOffset.UTC))
            .param("now", now.atOffset(ZoneOffset.UTC))
            .update()
    }

    fun revoke(id: UUID, now: Instant, replacedBy: UUID?) {
        jdbc.sql(
            """
            update refresh_tokens
            set revoked_at = coalesce(revoked_at, :now), replaced_by = :replacedBy
            where id = :id
            """,
        )
            .param("now", now.atOffset(ZoneOffset.UTC))
            .param("replacedBy", replacedBy)
            .param("id", id)
            .update()
    }

    fun revokeAllForDevice(userId: UUID, deviceId: UUID, now: Instant) {
        jdbc.sql(
            """
            update refresh_tokens set revoked_at = coalesce(revoked_at, :now)
            where user_id = :userId and device_id = :deviceId
            """,
        )
            .param("now", now.atOffset(ZoneOffset.UTC))
            .param("userId", userId)
            .param("deviceId", deviceId)
            .update()
    }
}
