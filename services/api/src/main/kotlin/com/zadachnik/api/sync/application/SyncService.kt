package com.zadachnik.api.sync.application

import com.fasterxml.jackson.core.type.TypeReference
import com.fasterxml.jackson.databind.ObjectMapper
import com.zadachnik.api.common.ApiException
import com.zadachnik.api.sync.domain.ChangeEntry
import com.zadachnik.api.sync.domain.OperationType
import com.zadachnik.api.sync.domain.PushResult
import com.zadachnik.api.sync.domain.PushStatus
import com.zadachnik.api.sync.domain.SyncOperationCommand
import com.zadachnik.api.sync.infrastructure.ChangeLogRepository
import java.time.Instant
import java.util.UUID
import org.springframework.stereotype.Service

data class PullResult(
    val changes: List<ChangeEntry>,
    val nextCursor: String,
    val hasMore: Boolean,
)

data class SyncState(
    val protocolVersion: Int,
    val serverTime: Instant,
    val latestChangeSeq: Long,
    val deviceId: UUID,
)

@Service
class SyncService(
    private val processor: NoteSyncProcessor,
    private val changeLog: ChangeLogRepository,
    private val objectMapper: ObjectMapper,
) {

    fun push(userId: UUID, deviceId: UUID, operations: List<SyncOperationCommand>): List<PushResult> =
        operations.map { operation ->
            when {
                operation.entityType != "NOTE" -> rejected(
                    operation,
                    "UNSUPPORTED_ENTITY",
                    "В этом шаге поддерживаются только NOTE",
                )
                operation.deviceId != deviceId -> rejected(
                    operation,
                    "DEVICE_MISMATCH",
                    "Операция принадлежит другому устройству",
                )
                else -> try {
                    processor.process(userId, deviceId, operation)
                } catch (conflict: OperationConflict) {
                    PushResult(
                        operationId = operation.operationId,
                        status = PushStatus.CONFLICT,
                        entityId = conflict.server.id,
                        revision = conflict.server.revision,
                        serverEntity = conflict.server,
                    )
                } catch (rejected: OperationRejected) {
                    rejected(operation, rejected.code, rejected.message)
                }
            }
        }

    fun pull(userId: UUID, cursorRaw: String?, limitRaw: Int?): PullResult {
        val cursor = cursorRaw?.toLongOrNull()
            ?: if (cursorRaw == null || cursorRaw == "0") 0 else throw ApiException.validation("Некорректный cursor")
        if (cursor < 0) {
            throw ApiException.validation("Некорректный cursor")
        }

        val limit = limitRaw ?: DEFAULT_LIMIT
        if (limit !in 1..MAX_LIMIT) {
            throw ApiException.validation("limit должен быть от 1 до $MAX_LIMIT")
        }

        val loaded = changeLog.listSince(userId, cursor, limit + 1)
        val page = loaded.take(limit)
        val nextCursor = page.lastOrNull()?.seq ?: cursor

        return PullResult(
            changes = page,
            nextCursor = nextCursor.toString(),
            hasMore = loaded.size > limit,
        )
    }

    fun state(userId: UUID, deviceId: UUID): SyncState = SyncState(
        protocolVersion = PROTOCOL_VERSION,
        serverTime = Instant.now(),
        latestChangeSeq = changeLog.latestSeq(userId),
        deviceId = deviceId,
    )

    fun payload(entry: ChangeEntry): Map<String, Any?> =
        objectMapper.readValue(entry.payload, object : TypeReference<Map<String, Any?>>() {})

    private fun rejected(operation: SyncOperationCommand, code: String, message: String): PushResult =
        PushResult(
            operationId = operation.operationId,
            status = PushStatus.REJECTED,
            entityId = operation.entityId,
            code = code,
            message = message,
        )

    companion object {
        const val PROTOCOL_VERSION = 1
        const val DEFAULT_LIMIT = 200
        const val MAX_LIMIT = 500
    }
}
