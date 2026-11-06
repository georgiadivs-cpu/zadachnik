package com.zadachnik.api.sync.application

import com.fasterxml.jackson.databind.ObjectMapper
import com.zadachnik.api.sync.domain.PushResult
import com.zadachnik.api.sync.domain.PushStatus
import com.zadachnik.api.sync.domain.SyncOperationCommand
import com.zadachnik.api.sync.infrastructure.ChangeLogRepository
import com.zadachnik.api.sync.infrastructure.ProcessedOperationRepository
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID
import org.springframework.stereotype.Service

/** Общая часть идемпотентности и записи change log для всех сущностей. */
@Service
class SyncOperationSupport(
    private val changeLog: ChangeLogRepository,
    private val processed: ProcessedOperationRepository,
    private val objectMapper: ObjectMapper,
) {

    fun duplicate(operation: SyncOperationCommand, userId: UUID): PushResult? {
        val requestHash = hash(operation)
        return processed.find(operation.operationId, userId)?.let { stored ->
            if (stored.requestHash != null && stored.requestHash != requestHash) {
                throw OperationRejected("OPERATION_ID_CONFLICT", "operationId уже использован с другим телом")
            }
            PushResult(
                operationId = operation.operationId,
                status = PushStatus.DUPLICATE,
                entityId = operation.entityId,
                revision = stored.revision,
                changeSeq = stored.changeSeq,
            )
        }
    }

    fun applied(
        userId: UUID,
        deviceId: UUID,
        operation: SyncOperationCommand,
        entityType: String,
        entityId: UUID,
        revision: Long,
        payload: Map<String, Any?>,
        now: Instant,
    ): PushResult {
        val seq = changeLog.append(
            userId = userId,
            entityType = entityType,
            entityId = entityId,
            operationId = operation.operationId,
            operationType = operation.operationType,
            revision = revision,
            payload = objectMapper.writeValueAsString(payload),
            deviceId = deviceId,
            now = now,
        )
        processed.insert(
            operationId = operation.operationId,
            userId = userId,
            result = PushStatus.APPLIED.name,
            revision = revision,
            changeSeq = seq,
            requestHash = hash(operation),
            now = now,
        )
        return PushResult(
            operationId = operation.operationId,
            status = PushStatus.APPLIED,
            entityId = entityId,
            revision = revision,
            changeSeq = seq,
        )
    }

    fun hash(operation: SyncOperationCommand): String =
        MessageDigest.getInstance("SHA-256")
            .digest(objectMapper.writeValueAsBytes(operation))
            .joinToString("") { byte -> "%02x".format(byte) }
}
