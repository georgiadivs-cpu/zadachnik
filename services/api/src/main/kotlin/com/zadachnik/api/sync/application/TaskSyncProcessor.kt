package com.zadachnik.api.sync.application

import com.zadachnik.api.sync.domain.OperationType
import com.zadachnik.api.sync.domain.PushResult
import com.zadachnik.api.sync.domain.SyncOperationCommand
import com.zadachnik.api.sync.domain.TaskSnapshot
import com.zadachnik.api.sync.infrastructure.TaskRepository
import java.time.Instant
import java.util.UUID
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
class TaskSyncProcessor(
    private val tasks: TaskRepository,
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
        if (tasks.find(userId, operation.entityId) != null) {
            throw OperationRejected("ENTITY_EXISTS", "Задача уже существует")
        }

        val payload = readPayload(userId, operation.payload)
        val task = tasks.create(
            userId = userId,
            id = operation.entityId,
            title = payload.title,
            description = payload.description,
            laneId = payload.laneId,
            systemState = payload.systemState,
            categoryId = payload.categoryId,
            priority = payload.priority,
            plannedStartAt = payload.plannedStartAt,
            plannedEndAt = payload.plannedEndAt,
            actualStartAt = payload.actualStartAt,
            actualEndAt = payload.actualEndAt,
            now = now,
        )
        return applied(userId, deviceId, operation, task, now)
    }

    private fun update(
        userId: UUID,
        deviceId: UUID,
        operation: SyncOperationCommand,
        now: Instant,
    ): PushResult {
        val baseRevision = operation.baseRevision
            ?: throw OperationRejected("VALIDATION_ERROR", "baseRevision обязательна для UPDATE")
        val current = tasks.findForUpdate(userId, operation.entityId)
            ?: throw OperationRejected("NOT_FOUND", "Задача не найдена")
        if (current.deletedAt != null || current.revision != baseRevision) {
            throw OperationConflict(current)
        }

        val payload = readPayload(userId, operation.payload)
        val updated = tasks.update(
            userId = userId,
            id = operation.entityId,
            title = payload.title,
            description = payload.description,
            laneId = payload.laneId,
            systemState = payload.systemState,
            categoryId = payload.categoryId,
            priority = payload.priority,
            plannedStartAt = payload.plannedStartAt,
            plannedEndAt = payload.plannedEndAt,
            actualStartAt = payload.actualStartAt,
            actualEndAt = payload.actualEndAt,
            baseRevision = baseRevision,
            now = now,
        ) ?: throw OperationConflict(tasks.find(userId, operation.entityId) ?: current)

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
        val current = tasks.findForUpdate(userId, operation.entityId)
            ?: throw OperationRejected("NOT_FOUND", "Задача не найдена")
        if (current.deletedAt != null || current.revision != baseRevision) {
            throw OperationConflict(current)
        }

        val deleted = tasks.softDelete(
            userId = userId,
            id = operation.entityId,
            baseRevision = baseRevision,
            now = now,
        ) ?: throw OperationConflict(tasks.find(userId, operation.entityId) ?: current)

        return applied(userId, deviceId, operation, deleted, now)
    }

    private fun applied(
        userId: UUID,
        deviceId: UUID,
        operation: SyncOperationCommand,
        task: TaskSnapshot,
        now: Instant,
    ): PushResult = support.applied(
        userId = userId,
        deviceId = deviceId,
        operation = operation,
        entityType = "TASK",
        entityId = task.id,
        revision = task.revision,
        payload = task.toPayload(),
        now = now,
    )

    private fun readPayload(userId: UUID, payload: Map<String, Any?>?): TaskPayload {
        if (payload == null) {
            throw OperationRejected("VALIDATION_ERROR", "payload обязателен")
        }

        val title = (payload["title"] as? String)?.trim().orEmpty()
        if (title.isEmpty() || title.length > 200) {
            throw OperationRejected("VALIDATION_ERROR", "Название задачи должно быть от 1 до 200 символов")
        }

        val description = when (val value = payload["description"]) {
            null -> ""
            is String -> value
            else -> throw OperationRejected("VALIDATION_ERROR", "description должен быть строкой")
        }
        if (description.length > MAX_DESCRIPTION_LENGTH) {
            throw OperationRejected("VALIDATION_ERROR", "Слишком большое описание задачи")
        }

        val laneId = when (val value = payload["laneId"]) {
            is String -> runCatching { UUID.fromString(value) }.getOrNull()
            else -> null
        } ?: throw OperationRejected("VALIDATION_ERROR", "laneId обязателен")
        if (!tasks.activeLaneExists(userId, laneId)) {
            throw OperationRejected("LANE_NOT_FOUND", "Дорожка не найдена")
        }

        val systemState = when ((payload["systemState"] as? String)?.uppercase()) {
            "ACTIVE" -> "ACTIVE"
            "CANCELLED" -> "CANCELLED"
            else -> throw OperationRejected("VALIDATION_ERROR", "Некорректное состояние задачи")
        }

        val categoryId = when (val value = payload["categoryId"]) {
            null -> null
            is String -> value.trim().ifEmpty { null }
            else -> throw OperationRejected("VALIDATION_ERROR", "categoryId должен быть строкой")
        }
        if (categoryId != null && !tasks.categoryExists(categoryId)) {
            throw OperationRejected("VALIDATION_ERROR", "Категория не найдена")
        }

        val priority = when ((payload["priority"] as? String)?.uppercase()) {
            "LOW" -> "LOW"
            "NORMAL" -> "NORMAL"
            "HIGH" -> "HIGH"
            else -> throw OperationRejected("VALIDATION_ERROR", "Некорректный приоритет")
        }

        val plannedStartAt = readInstant(payload["plannedStartAt"], "plannedStartAt")
        val plannedEndAt = readInstant(payload["plannedEndAt"], "plannedEndAt")
        val actualStartAt = readInstant(payload["actualStartAt"], "actualStartAt")
        val actualEndAt = readInstant(payload["actualEndAt"], "actualEndAt")
        if (plannedStartAt != null && plannedEndAt != null && plannedEndAt.isBefore(plannedStartAt)) {
            throw OperationRejected("VALIDATION_ERROR", "Плановое завершение раньше начала")
        }
        if (actualStartAt != null && actualEndAt != null && actualEndAt.isBefore(actualStartAt)) {
            throw OperationRejected("VALIDATION_ERROR", "Фактическое завершение раньше начала")
        }

        return TaskPayload(
            title = title,
            description = description,
            laneId = laneId,
            systemState = systemState,
            categoryId = categoryId,
            priority = priority,
            plannedStartAt = plannedStartAt,
            plannedEndAt = plannedEndAt,
            actualStartAt = actualStartAt,
            actualEndAt = actualEndAt,
        )
    }

    private fun readInstant(value: Any?, field: String): Instant? = when (value) {
        null -> null
        is String -> runCatching { Instant.parse(value) }.getOrElse {
            throw OperationRejected("VALIDATION_ERROR", "$field должен быть ISO-8601 временем")
        }
        else -> throw OperationRejected("VALIDATION_ERROR", "$field должен быть строкой")
    }

    private data class TaskPayload(
        val title: String,
        val description: String,
        val laneId: UUID,
        val systemState: String,
        val categoryId: String?,
        val priority: String,
        val plannedStartAt: Instant?,
        val plannedEndAt: Instant?,
        val actualStartAt: Instant?,
        val actualEndAt: Instant?,
    )

    companion object {
        private const val MAX_DESCRIPTION_LENGTH = 10_000
    }
}
