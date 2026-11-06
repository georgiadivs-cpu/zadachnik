package com.zadachnik.api.sync.application

import com.zadachnik.api.sync.domain.OperationType
import com.zadachnik.api.sync.domain.PushResult
import com.zadachnik.api.sync.domain.ReminderSnapshot
import com.zadachnik.api.sync.domain.SyncOperationCommand
import com.zadachnik.api.sync.infrastructure.ReminderRepository
import java.time.Instant
import java.util.UUID
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
class ReminderSyncProcessor(
    private val reminders: ReminderRepository,
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
        if (reminders.find(userId, operation.entityId) != null) {
            throw OperationRejected("ENTITY_EXISTS", "Напоминание уже существует")
        }
        val payload = readPayload(userId, operation.payload)
        if (reminders.findActiveForTask(userId, payload.taskId) != null) {
            throw OperationRejected("REMINDER_EXISTS", "У задачи уже есть напоминание")
        }

        val reminder = reminders.create(
            userId = userId,
            id = operation.entityId,
            taskId = payload.taskId,
            remindAt = payload.remindAt,
            now = now,
        )
        return applied(userId, deviceId, operation, reminder, now)
    }

    private fun update(
        userId: UUID,
        deviceId: UUID,
        operation: SyncOperationCommand,
        now: Instant,
    ): PushResult {
        val baseRevision = operation.baseRevision
            ?: throw OperationRejected("VALIDATION_ERROR", "baseRevision обязательна для UPDATE")
        val current = reminders.findForUpdate(userId, operation.entityId)
            ?: throw OperationRejected("NOT_FOUND", "Напоминание не найдено")
        if (current.deletedAt != null || current.revision != baseRevision) {
            throw OperationConflict(current)
        }
        val payload = readPayload(userId, operation.payload)
        val active = reminders.findActiveForTask(userId, payload.taskId)
        if (active != null && active.id != current.id) {
            throw OperationRejected("REMINDER_EXISTS", "У задачи уже есть напоминание")
        }

        val updated = reminders.update(
            userId = userId,
            id = operation.entityId,
            taskId = payload.taskId,
            remindAt = payload.remindAt,
            baseRevision = baseRevision,
            now = now,
        ) ?: throw OperationConflict(reminders.find(userId, operation.entityId) ?: current)

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
        val current = reminders.findForUpdate(userId, operation.entityId)
            ?: throw OperationRejected("NOT_FOUND", "Напоминание не найдено")
        if (current.deletedAt != null || current.revision != baseRevision) {
            throw OperationConflict(current)
        }

        val deleted = reminders.softDelete(
            userId = userId,
            id = operation.entityId,
            baseRevision = baseRevision,
            now = now,
        ) ?: throw OperationConflict(reminders.find(userId, operation.entityId) ?: current)

        return applied(userId, deviceId, operation, deleted, now)
    }

    private fun applied(
        userId: UUID,
        deviceId: UUID,
        operation: SyncOperationCommand,
        reminder: ReminderSnapshot,
        now: Instant,
    ): PushResult = support.applied(
        userId = userId,
        deviceId = deviceId,
        operation = operation,
        entityType = "REMINDER",
        entityId = reminder.id,
        revision = reminder.revision,
        payload = reminder.toPayload(),
        now = now,
    )

    private fun readPayload(userId: UUID, payload: Map<String, Any?>?): ReminderPayload {
        if (payload == null) {
            throw OperationRejected("VALIDATION_ERROR", "payload обязателен")
        }
        val taskId = when (val value = payload["taskId"]) {
            is String -> runCatching { UUID.fromString(value) }.getOrNull()
            else -> null
        } ?: throw OperationRejected("VALIDATION_ERROR", "taskId обязателен")
        if (!reminders.taskExists(userId, taskId)) {
            throw OperationRejected("TASK_NOT_FOUND", "Задача не найдена")
        }
        val remindAt = when (val value = payload["remindAt"]) {
            is String -> runCatching { Instant.parse(value) }.getOrElse {
                throw OperationRejected(
                    "VALIDATION_ERROR",
                    "remindAt должен быть ISO-8601 временем",
                )
            }
            else -> throw OperationRejected("VALIDATION_ERROR", "remindAt обязателен")
        }
        return ReminderPayload(taskId, remindAt)
    }

    private data class ReminderPayload(val taskId: UUID, val remindAt: Instant)
}
