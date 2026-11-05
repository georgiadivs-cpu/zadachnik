package com.zadachnik.api.sync.infrastructure

import com.zadachnik.api.sync.domain.ChangeEntry
import com.zadachnik.api.sync.domain.OperationType
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository

@Repository
class ChangeLogRepository(private val jdbc: JdbcClient) {

    fun append(
        userId: UUID,
        entityType: String,
        entityId: UUID,
        operationId: UUID,
        operationType: OperationType,
        revision: Long,
        payload: String,
        deviceId: UUID,
        now: Instant,
    ): Long =
        jdbc.sql(
            """
            insert into change_log
                (user_id, entity_type, entity_id, operation_id, operation_type,
                 revision, payload, device_id, changed_at)
            values
                (:userId, :entityType, :entityId, :operationId, :operationType,
                 :revision, cast(:payload as jsonb), :deviceId, :changedAt)
            returning seq
            """,
        )
            .param("userId", userId)
            .param("entityType", entityType)
            .param("entityId", entityId)
            .param("operationId", operationId)
            .param("operationType", operationType.name)
            .param("revision", revision)
            .param("payload", payload)
            .param("deviceId", deviceId)
            .param("changedAt", now.atOffset(ZoneOffset.UTC))
            .query(Long::class.java)
            .single()

    fun listSince(userId: UUID, cursor: Long, limit: Int): List<ChangeEntry> =
        jdbc.sql(
            """
            select seq, entity_type, entity_id, operation_id, operation_type,
                   revision, device_id, changed_at, payload
            from change_log
            where user_id = :userId and seq > :cursor
            order by seq
            limit :limit
            """,
        )
            .param("userId", userId)
            .param("cursor", cursor)
            .param("limit", limit)
            .query { rs, _ ->
                ChangeEntry(
                    seq = rs.getLong("seq"),
                    entityType = rs.getString("entity_type"),
                    entityId = rs.getObject("entity_id", UUID::class.java),
                    operationId = rs.getObject("operation_id", UUID::class.java),
                    operationType = OperationType.valueOf(rs.getString("operation_type")),
                    revision = rs.getLong("revision"),
                    originDeviceId = rs.getObject("device_id", UUID::class.java),
                    changedAt = rs.getObject("changed_at", OffsetDateTime::class.java).toInstant(),
                    payload = rs.getString("payload"),
                )
            }
            .list()

    fun latestSeq(userId: UUID): Long =
        jdbc.sql("select coalesce(max(seq), 0) from change_log where user_id = :userId")
            .param("userId", userId)
            .query(Long::class.java)
            .single()
}
