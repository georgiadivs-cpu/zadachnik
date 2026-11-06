package com.zadachnik.api.attachment.domain

import java.time.Instant
import java.util.UUID

data class AttachmentSnapshot(
    val id: UUID,
    val userId: UUID,
    val ownerType: String,
    val ownerId: UUID,
    val fileName: String,
    val mimeType: String,
    val sizeBytes: Long,
    val sha256: String,
    val storageKey: String,
    val revision: Long,
    val createdAt: Instant,
    val updatedAt: Instant,
    val deletedAt: Instant?,
) {
    fun toPayload(): Map<String, Any?> = mapOf(
        "id" to id,
        "ownerType" to ownerType,
        "ownerId" to ownerId,
        "fileName" to fileName,
        "mimeType" to mimeType,
        "sizeBytes" to sizeBytes,
        "sha256" to sha256,
        "revision" to revision,
        "createdAt" to createdAt,
        "updatedAt" to updatedAt,
        "deletedAt" to deletedAt,
    )
}
