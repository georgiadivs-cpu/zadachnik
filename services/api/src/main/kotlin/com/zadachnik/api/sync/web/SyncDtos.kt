package com.zadachnik.api.sync.web

import com.zadachnik.api.sync.application.PullResult
import com.zadachnik.api.sync.application.SyncState
import com.zadachnik.api.sync.domain.OperationType
import com.zadachnik.api.sync.domain.PushResult
import com.zadachnik.api.sync.domain.PushStatus
import com.zadachnik.api.sync.domain.SyncOperationCommand
import jakarta.validation.Valid
import jakarta.validation.constraints.NotEmpty
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Size
import java.time.Instant
import java.util.UUID

data class PushOperationRequest(
    @field:NotNull val operationId: UUID,
    @field:NotNull val deviceId: UUID,
    @field:NotNull val entityType: String,
    @field:NotNull val entityId: UUID,
    @field:NotNull val operationType: OperationType,
    val baseRevision: Long? = null,
    @field:NotNull val clientTimestamp: Instant,
    val payload: Map<String, Any?>? = null,
) {
    fun toCommand(): SyncOperationCommand = SyncOperationCommand(
        operationId = operationId,
        deviceId = deviceId,
        entityType = entityType,
        entityId = entityId,
        operationType = operationType,
        baseRevision = baseRevision,
        clientTimestamp = clientTimestamp,
        payload = payload,
    )
}

data class PushRequest(
    @field:NotEmpty
    @field:Size(max = 100)
    @field:Valid
    val operations: List<PushOperationRequest>,
)

data class PushResultResponse(
    val operationId: UUID,
    val status: PushStatus,
    val entityId: UUID? = null,
    val revision: Long? = null,
    val changeSeq: Long? = null,
    val serverEntity: Map<String, Any?>? = null,
    val code: String? = null,
    val message: String? = null,
) {
    companion object {
        fun from(result: PushResult): PushResultResponse = PushResultResponse(
            operationId = result.operationId,
            status = result.status,
            entityId = result.entityId,
            revision = result.revision,
            changeSeq = result.changeSeq,
            serverEntity = result.serverEntity,
            code = result.code,
            message = result.message,
        )
    }
}

data class PushResponse(val results: List<PushResultResponse>) {
    companion object {
        fun from(results: List<PushResult>): PushResponse =
            PushResponse(results.map(PushResultResponse::from))
    }
}

data class ChangeResponse(
    val seq: Long,
    val entityType: String,
    val entityId: UUID,
    val operationId: UUID?,
    val operationType: OperationType,
    val revision: Long,
    val originDeviceId: UUID?,
    val changedAt: Instant,
    val payload: Map<String, Any?>,
)

data class PullResponse(
    val changes: List<ChangeResponse>,
    val nextCursor: String,
    val hasMore: Boolean,
) {
    companion object {
        fun from(
            result: PullResult,
            payload: (com.zadachnik.api.sync.domain.ChangeEntry) -> Map<String, Any?>,
        ): PullResponse = PullResponse(
            changes = result.changes.map {
                ChangeResponse(
                    seq = it.seq,
                    entityType = it.entityType,
                    entityId = it.entityId,
                    operationId = it.operationId,
                    operationType = it.operationType,
                    revision = it.revision,
                    originDeviceId = it.originDeviceId,
                    changedAt = it.changedAt,
                    payload = payload(it),
                )
            },
            nextCursor = result.nextCursor,
            hasMore = result.hasMore,
        )
    }
}

data class SyncStateResponse(
    val protocolVersion: Int,
    val serverTime: Instant,
    val latestChangeSeq: Long,
    val deviceId: UUID,
) {
    companion object {
        fun from(state: SyncState): SyncStateResponse = SyncStateResponse(
            protocolVersion = state.protocolVersion,
            serverTime = state.serverTime,
            latestChangeSeq = state.latestChangeSeq,
            deviceId = state.deviceId,
        )
    }
}
