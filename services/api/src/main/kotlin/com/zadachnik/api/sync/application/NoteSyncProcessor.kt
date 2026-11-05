package com.zadachnik.api.sync.application

import com.fasterxml.jackson.databind.ObjectMapper
import com.zadachnik.api.sync.domain.NoteSnapshot
import com.zadachnik.api.sync.domain.OperationType
import com.zadachnik.api.sync.domain.PushResult
import com.zadachnik.api.sync.domain.PushStatus
import com.zadachnik.api.sync.domain.SyncOperationCommand
import com.zadachnik.api.sync.infrastructure.ChangeLogRepository
import com.zadachnik.api.sync.infrastructure.NoteRepository
import com.zadachnik.api.sync.infrastructure.ProcessedOperationRepository
import java.time.Instant
import java.util.UUID
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
class NoteSyncProcessor(
    private val notes: NoteRepository,
    private val changeLog: ChangeLogRepository,
    private val processed: ProcessedOperationRepository,
    private val objectMapper: ObjectMapper,
) {

    @Transactional
    fun process(userId: UUID, deviceId: UUID, operation: SyncOperationCommand): PushResult {
        val requestHash = operationHash(operation)
        processed.find(operation.operationId, userId)?.let { stored ->
            if (stored.requestHash != null && stored.requestHash != requestHash) {
                throw OperationRejected("OPERATION_ID_CONFLICT", "operationId уже использован с другим телом")
            }
            return PushResult(
                operationId = operation.operationId,
                status = PushStatus.DUPLICATE,
                entityId = operation.entityId,
                revision = stored.revision,
                changeSeq = stored.changeSeq,
            )
        }

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
        return appendApplied(userId, deviceId, operation, note, now)
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
        if (current.deletedAt != null) {
            throw OperationConflict(current)
        }
        if (current.revision != baseRevision) {
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

        return appendApplied(userId, deviceId, operation, updated, now)
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

        return appendApplied(userId, deviceId, operation, deleted, now)
    }

    private fun appendApplied(
        userId: UUID,
        deviceId: UUID,
        operation: SyncOperationCommand,
        note: NoteSnapshot,
        now: Instant,
    ): PushResult {
        val payload = objectMapper.writeValueAsString(
            mapOf(
                "id" to note.id.toString(),
                "title" to note.title,
                "contentMarkdown" to note.contentMarkdown,
                "categoryId" to note.categoryId,
                "revision" to note.revision,
                "createdAt" to note.createdAt,
                "updatedAt" to note.updatedAt,
                "deletedAt" to note.deletedAt,
            ),
        )

        val seq = changeLog.append(
            userId = userId,
            entityType = "NOTE",
            entityId = note.id,
            operationId = operation.operationId,
            operationType = operation.operationType,
            revision = note.revision,
            payload = payload,
            deviceId = deviceId,
            now = now,
        )
        processed.insert(
            operationId = operation.operationId,
            userId = userId,
            result = PushStatus.APPLIED.name,
            revision = note.revision,
            changeSeq = seq,
            requestHash = operationHash(operation),
            now = now,
        )

        return PushResult(
            operationId = operation.operationId,
            status = PushStatus.APPLIED,
            entityId = note.id,
            revision = note.revision,
            changeSeq = seq,
        )
    }

    private fun operationHash(operation: SyncOperationCommand): String =
        java.security.MessageDigest.getInstance("SHA-256")
            .digest(objectMapper.writeValueAsBytes(operation))
            .joinToString("") { byte -> "%02x".format(byte) }

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
