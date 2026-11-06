package com.zadachnik.api.sync.application

import com.zadachnik.api.sync.domain.LaneSnapshot
import com.zadachnik.api.sync.domain.OperationType
import com.zadachnik.api.sync.domain.PushResult
import com.zadachnik.api.sync.domain.SyncOperationCommand
import com.zadachnik.api.sync.infrastructure.LaneRepository
import java.time.Instant
import java.util.UUID
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
class LaneSyncProcessor(
    private val lanes: LaneRepository,
    private val support: SyncOperationSupport,
) {

    @Transactional
    fun process(userId: UUID, deviceId: UUID, operation: SyncOperationCommand): PushResult {
        support.duplicate(operation, userId)?.let { return it }

        val now = Instant.now()
        return when (operation.operationType) {
            OperationType.CREATE -> create(userId, deviceId, operation, now)
            OperationType.UPDATE -> update(userId, deviceId, operation, now)
            OperationType.DELETE -> delete(userId, deviceId, operation, now)
        }
    }

    private fun create(
        userId: UUID,
        deviceId: UUID,
        operation: SyncOperationCommand,
        now: Instant,
    ): PushResult {
        if (operation.baseRevision != null) {
            throw OperationRejected("VALIDATION_ERROR", "CREATE не должен содержать baseRevision")
        }
        if (lanes.find(userId, operation.entityId) != null) {
            throw OperationRejected("ENTITY_EXISTS", "Дорожка уже существует")
        }
        if (lanes.activeCount(userId) >= MAX_LANES) {
            throw OperationRejected("LANE_LIMIT", "Допустимо не более $MAX_LANES дорожек")
        }

        val payload = readPayload(operation.payload)
        val lane = lanes.create(
            userId = userId,
            id = operation.entityId,
            name = payload.name,
            sortOrder = payload.sortOrder,
            now = now,
        )
        return applied(userId, deviceId, operation, lane, now)
    }

    private fun update(
        userId: UUID,
        deviceId: UUID,
        operation: SyncOperationCommand,
        now: Instant,
    ): PushResult {
        val baseRevision = operation.baseRevision
            ?: throw OperationRejected("VALIDATION_ERROR", "baseRevision обязательна для UPDATE")
        val current = lanes.findForUpdate(userId, operation.entityId)
            ?: throw OperationRejected("NOT_FOUND", "Дорожка не найдена")
        if (current.deletedAt != null || current.revision != baseRevision) {
            throw OperationConflict(current)
        }

        val payload = readPayload(operation.payload)
        val updated = lanes.update(
            userId = userId,
            id = operation.entityId,
            name = payload.name,
            sortOrder = payload.sortOrder,
            baseRevision = baseRevision,
            now = now,
        ) ?: throw OperationConflict(lanes.find(userId, operation.entityId) ?: current)

        return applied(userId, deviceId, operation, updated, now)
    }

    private fun delete(
        userId: UUID,
        deviceId: UUID,
        operation: SyncOperationCommand,
        now: Instant,
    ): PushResult {
        val baseRevision = operation.baseRevision
            ?: throw OperationRejected("VALIDATION_ERROR", "baseRevision обязательна для DELETE")
        val current = lanes.findForUpdate(userId, operation.entityId)
            ?: throw OperationRejected("NOT_FOUND", "Дорожка не найдена")
        if (current.deletedAt != null || current.revision != baseRevision) {
            throw OperationConflict(current)
        }
        if (lanes.activeCount(userId) <= MIN_LANES) {
            throw OperationRejected("LANE_LIMIT", "Допустимо не менее $MIN_LANES дорожек")
        }
        if (lanes.taskCount(userId, operation.entityId) > 0) {
            throw OperationRejected("LANE_NOT_EMPTY", "Сначала перенесите задачи из дорожки")
        }

        val deleted = lanes.softDelete(
            userId = userId,
            id = operation.entityId,
            baseRevision = baseRevision,
            now = now,
        ) ?: throw OperationConflict(lanes.find(userId, operation.entityId) ?: current)

        return applied(userId, deviceId, operation, deleted, now)
    }

    private fun applied(
        userId: UUID,
        deviceId: UUID,
        operation: SyncOperationCommand,
        lane: LaneSnapshot,
        now: Instant,
    ): PushResult = support.applied(
        userId = userId,
        deviceId = deviceId,
        operation = operation,
        entityType = "LANE",
        entityId = lane.id,
        revision = lane.revision,
        payload = lane.toPayload(),
        now = now,
    )

    private fun readPayload(payload: Map<String, Any?>?): LanePayload {
        if (payload == null) {
            throw OperationRejected("VALIDATION_ERROR", "payload обязателен")
        }
        val name = (payload["name"] as? String)?.trim().orEmpty()
        if (name.isEmpty() || name.length > 60) {
            throw OperationRejected("VALIDATION_ERROR", "Название дорожки должно быть от 1 до 60 символов")
        }
        val sortOrder = when (val value = payload["sortOrder"]) {
            is Number -> value.toInt()
            else -> throw OperationRejected("VALIDATION_ERROR", "sortOrder обязателен")
        }
        if (sortOrder !in 0..MAX_SORT_ORDER) {
            throw OperationRejected("VALIDATION_ERROR", "Некорректный порядок дорожки")
        }
        return LanePayload(name, sortOrder)
    }

    private data class LanePayload(val name: String, val sortOrder: Int)

    companion object {
        private const val MIN_LANES = 3
        private const val MAX_LANES = 10
        private const val MAX_SORT_ORDER = 1_000
    }
}
