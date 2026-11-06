package com.zadachnik.api.attachment.web

import com.zadachnik.api.attachment.domain.AttachmentSnapshot
import java.time.Instant
import java.util.UUID

data class AttachmentResponse(
    val id: UUID,
    val ownerType: String,
    val ownerId: UUID,
    val fileName: String,
    val mimeType: String,
    val sizeBytes: Long,
    val sha256: String,
    val revision: Long,
    val createdAt: Instant,
    val updatedAt: Instant,
) {
    companion object {
        fun from(snapshot: AttachmentSnapshot): AttachmentResponse =
            AttachmentResponse(
                id = snapshot.id,
                ownerType = snapshot.ownerType,
                ownerId = snapshot.ownerId,
                fileName = snapshot.fileName,
                mimeType = snapshot.mimeType,
                sizeBytes = snapshot.sizeBytes,
                sha256 = snapshot.sha256,
                revision = snapshot.revision,
                createdAt = snapshot.createdAt,
                updatedAt = snapshot.updatedAt,
            )
    }
}
