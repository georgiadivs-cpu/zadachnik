package com.zadachnik.api.attachment.application

import com.zadachnik.api.attachment.domain.AttachmentSnapshot
import com.zadachnik.api.attachment.infrastructure.AttachmentRepository
import com.zadachnik.api.attachment.infrastructure.LocalAttachmentStorage
import com.zadachnik.api.common.ApiException
import com.zadachnik.api.sync.domain.OperationType
import com.zadachnik.api.sync.infrastructure.ChangeLogRepository
import com.fasterxml.jackson.databind.ObjectMapper
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.util.UUID
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.transaction.support.TransactionSynchronization
import org.springframework.transaction.support.TransactionSynchronizationManager

data class AttachmentDownload(
    val snapshot: AttachmentSnapshot,
    val path: Path,
    val fileName: String,
    val mimeType: String,
)

@Service
class AttachmentService(
    private val attachments: AttachmentRepository,
    private val storage: LocalAttachmentStorage,
    private val changeLog: ChangeLogRepository,
    private val objectMapper: ObjectMapper,
) {

    @Transactional
    fun upload(
        userId: UUID,
        deviceId: UUID,
        attachmentId: UUID,
        ownerType: String,
        ownerId: UUID,
        fileName: String,
        declaredMime: String?,
        input: InputStream,
    ): AttachmentSnapshot {
        val normalizedOwner = ownerType.uppercase()
        if (normalizedOwner !in setOf("NOTE", "TASK")) {
            throw ApiException.validation("Некорректный тип владельца")
        }
        if (!attachments.ownerExists(userId, normalizedOwner, ownerId)) {
            throw ApiException.notFound("Заметка или задача не найдена")
        }
        val safeName = AttachmentRules.sanitizeFileName(fileName)
        val existing = attachments.find(userId, attachmentId)

        val stored = storage.saveTemp(userId, input)
        try {
            val mimeType = AttachmentRules.validateAndNormalize(
                safeName,
                declaredMime,
                stored.tempPath,
            )
            if (existing != null) {
                if (existing.deletedAt != null) {
                    throw ApiException(
                        HttpStatus.CONFLICT,
                        "ATTACHMENT_DELETED",
                        "Вложение уже удалено",
                    )
                }
                if (existing.sha256 == stored.sha256 &&
                    existing.sizeBytes == stored.sizeBytes &&
                    existing.ownerType == normalizedOwner &&
                    existing.ownerId == ownerId
                ) {
                    if (Files.isRegularFile(storage.resolve(userId, attachmentId))) {
                        storage.deleteTemp(stored.tempPath)
                    } else {
                        storage.commit(stored.tempPath, userId, attachmentId)
                    }
                    return existing
                }
                throw ApiException(
                    HttpStatus.CONFLICT,
                    "ATTACHMENT_EXISTS",
                    "Вложение с таким ID уже существует",
                )
            }

            storage.commit(stored.tempPath, userId, attachmentId)
            try {
                val now = Instant.now()
                val snapshot = attachments.insert(
                    userId = userId,
                    id = attachmentId,
                    ownerType = normalizedOwner,
                    ownerId = ownerId,
                    fileName = safeName,
                    mimeType = mimeType,
                    sizeBytes = stored.sizeBytes,
                    sha256 = stored.sha256,
                    storageKey = attachmentId.toString(),
                    now = now,
                )
                appendChange(
                    userId = userId,
                    deviceId = deviceId,
                    snapshot = snapshot,
                    operationType = OperationType.CREATE,
                    now = now,
                )
                return snapshot
            } catch (exception: Exception) {
                storage.delete(userId, attachmentId)
                throw exception
            }
        } catch (exception: Exception) {
            storage.deleteTemp(stored.tempPath)
            throw exception
        }
    }

    fun download(userId: UUID, attachmentId: UUID): AttachmentDownload {
        val snapshot = attachments.find(userId, attachmentId)
            ?: throw ApiException.notFound("Вложение не найдено")
        if (snapshot.deletedAt != null) {
            throw ApiException.notFound("Вложение не найдено")
        }
        val path = storage.resolve(userId, attachmentId)
        if (!Files.isRegularFile(path)) {
            throw ApiException.notFound("Файл вложения не найден")
        }
        return AttachmentDownload(
            snapshot = snapshot,
            path = path,
            fileName = snapshot.fileName,
            mimeType = snapshot.mimeType,
        )
    }

    @Transactional
    fun delete(userId: UUID, deviceId: UUID, attachmentId: UUID) {
        val current = attachments.find(userId, attachmentId) ?: return
        if (current.deletedAt != null) {
            return
        }
        val now = Instant.now()
        val deleted = attachments.softDelete(userId, attachmentId, now) ?: return
        appendChange(
            userId = userId,
            deviceId = deviceId,
            snapshot = deleted,
            operationType = OperationType.DELETE,
            now = now,
        )
        TransactionSynchronizationManager.registerSynchronization(
            object : TransactionSynchronization {
                override fun afterCommit() {
                    storage.delete(userId, attachmentId)
                }
            },
        )
    }

    fun maxBytes(): Long = storage.maxBytes()

    private fun appendChange(
        userId: UUID,
        deviceId: UUID,
        snapshot: AttachmentSnapshot,
        operationType: OperationType,
        now: Instant,
    ) {
        val payload = objectMapper.writeValueAsString(snapshot.toPayload())
        changeLog.append(
            userId = userId,
            entityType = "ATTACHMENT",
            entityId = snapshot.id,
            operationId = UUID.randomUUID(),
            operationType = operationType,
            revision = snapshot.revision,
            payload = payload,
            deviceId = deviceId,
            now = now,
        )
    }
}
