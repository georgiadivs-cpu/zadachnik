package com.zadachnik.api.sync.application

import com.zadachnik.api.sync.domain.NoteSnapshot
import com.zadachnik.api.sync.domain.OperationType
import com.zadachnik.api.sync.domain.PushResult
import com.zadachnik.api.sync.domain.SyncOperationCommand
import com.zadachnik.api.sync.infrastructure.NoteRepository
import java.time.Instant
import java.util.UUID
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
class NoteSyncProcessor(
    private val notes: NoteRepository,
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
        if (notes.find(userId, operation.entityId) != null) {
            throw OperationRejected("ENTITY_EXISTS", "Заметка уже существует")
        }

        val payload = readPayload(operation.payload)
        val note = notes.create(
            userId = userId,
            id = operation.entityId,
            title = payload.title,
            contentMarkdown = payload.contentMarkdown,
            categoryId = payload.categoryId,
            now = now,
        )
        return applied(userId, deviceId, operation, note, now)
    }

    private fun update(
        userId: UUID,
        deviceId: UUID,
        operation: SyncOperationCommand,
        now: Instant,
    ): PushResult {
        val baseRevision = operation.baseRevision
            ?: throw OperationRejected("VALIDATION_ERROR", "baseRevision обязательна для UPDATE")
        val current = notes.findForUpdate(userId, operation.entityId)
            ?: throw OperationRejected("NOT_FOUND", "Заметка не найдена")
        if (current.deletedAt != null || current.revision != baseRevision) {
            throw OperationConflict(current)
        }

        val payload = readPayload(operation.payload)
        val updated = notes.update(
            userId = userId,
            id = operation.entityId,
            title = payload.title,
            contentMarkdown = payload.contentMarkdown,
            categoryId = payload.categoryId,
            baseRevision = baseRevision,
            now = now,
        ) ?: throw OperationConflict(notes.find(userId, operation.entityId) ?: current)

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
        val current = notes.findForUpdate(userId, operation.entityId)
            ?: throw OperationRejected("NOT_FOUND", "Заметка не найдена")
        if (current.deletedAt != null || current.revision != baseRevision) {
            throw OperationConflict(current)
        }

        val deleted = notes.softDelete(
            userId = userId,
            id = operation.entityId,
            baseRevision = baseRevision,
            now = now,
        ) ?: throw OperationConflict(notes.find(userId, operation.entityId) ?: current)

        return applied(userId, deviceId, operation, deleted, now)
    }

    private fun applied(
        userId: UUID,
        deviceId: UUID,
        operation: SyncOperationCommand,
        note: NoteSnapshot,
        now: Instant,
    ): PushResult = support.applied(
        userId = userId,
        deviceId = deviceId,
        operation = operation,
        entityType = "NOTE",
        entityId = note.id,
        revision = note.revision,
        payload = note.toPayload(),
        now = now,
    )

    private fun readPayload(payload: Map<String, Any?>?): NotePayload {
        if (payload == null) {
            throw OperationRejected("VALIDATION_ERROR", "payload обязателен")
        }

        val title = (payload["title"] as? String)?.trim().orEmpty()
        if (title.isEmpty() || title.length > 200) {
            throw OperationRejected("VALIDATION_ERROR", "Заголовок должен быть от 1 до 200 символов")
        }

        val content = payload["contentMarkdown"] as? String
            ?: throw OperationRejected("VALIDATION_ERROR", "contentMarkdown обязателен")
        if (content.length > MAX_CONTENT_LENGTH) {
            throw OperationRejected("VALIDATION_ERROR", "Слишком большой текст заметки")
        }

        val categoryId = when (val value = payload["categoryId"]) {
            null -> null
            is String -> value.trim().ifEmpty { null }
            else -> throw OperationRejected("VALIDATION_ERROR", "categoryId должен быть строкой")
        }
        if (categoryId != null && !notes.categoryExists(categoryId)) {
            throw OperationRejected("VALIDATION_ERROR", "Категория не найдена")
        }

        return NotePayload(title, content, categoryId)
    }

    private data class NotePayload(
        val title: String,
        val contentMarkdown: String,
        val categoryId: String?,
    )

    companion object {
        private const val MAX_CONTENT_LENGTH = 1_000_000
    }
}
