package com.zadachnik.api.sync.domain

import java.time.Instant
import java.util.UUID

enum class OperationType { CREATE, UPDATE, DELETE }

data class NoteSnapshot(
    val id: UUID,
    val userId: UUID?,
    val title: String,
    val contentMarkdown: String,
    val categoryId: String?,
    val revision: Long,
    val createdAt: Instant,
    val updatedAt: Instant,
    val deletedAt: Instant?,
)

data class SyncOperationCommand(
    val operationId: UUID,
    val deviceId: UUID,
    val entityType: String,
    val entityId: UUID,
    val operationType: OperationType,
    val baseRevision: Long?,
    val clientTimestamp: Instant,
    val payload: Map<String, Any?>?,
)

data class ChangeEntry(
    val seq: Long,
    val entityType: String,
    val entityId: UUID,
    val operationId: UUID?,
    val operationType: OperationType,
    val revision: Long,
    val originDeviceId: UUID?,
    val changedAt: Instant,
    val payload: String,
)

data class ProcessedOperation(
    val operationId: UUID,
    val result: String,
    val revision: Long,
    val changeSeq: Long?,
    val requestHash: String?,
)
