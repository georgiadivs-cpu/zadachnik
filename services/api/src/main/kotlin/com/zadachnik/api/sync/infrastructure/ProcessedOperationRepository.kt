package com.zadachnik.api.sync.infrastructure

import com.zadachnik.api.sync.domain.ProcessedOperation
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository

@Repository
class ProcessedOperationRepository(private val jdbc: JdbcClient) {

    fun find(operationId: UUID, userId: UUID): ProcessedOperation? =
        jdbc.sql(
            """
            select operation_id, result, revision, change_seq, request_hash
            from processed_operations where operation_id = :operationId and user_id = :userId
            """,
        )
            .param("operationId", operationId)
            .param("userId", userId)
            .query { rs, _ ->
                ProcessedOperation(
                    operationId = rs.getObject("operation_id", UUID::class.java),
                    result = rs.getString("result"),
                    revision = rs.getLong("revision"),
                    changeSeq = rs.getObject("change_seq", java.lang.Long::class.java)?.toLong(),
                    requestHash = rs.getString("request_hash"),
                )
            }
            .optional()
            .orElse(null)

    fun insert(
        operationId: UUID,
        userId: UUID,
        result: String,
        revision: Long,
        changeSeq: Long,
        requestHash: String,
        now: Instant,
    ) {
        jdbc.sql(
            """
            insert into processed_operations
                (operation_id, user_id, result, revision, change_seq, request_hash, processed_at)
            values (:operationId, :userId, :result, :revision, :changeSeq, :requestHash, :now)
            """,
        )
            .param("operationId", operationId)
            .param("userId", userId)
            .param("result", result)
            .param("revision", revision)
            .param("changeSeq", changeSeq)
            .param("requestHash", requestHash)
            .param("now", now.atOffset(ZoneOffset.UTC))
            .update()
    }
}
