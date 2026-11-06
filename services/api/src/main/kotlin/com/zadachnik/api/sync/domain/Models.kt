package com.zadachnik.api.sync.domain

import java.time.Instant
import java.util.UUID

enum class OperationType { CREATE, UPDATE, DELETE }

interface SyncSnapshot {
    val id: UUID
    val revision: Long
    fun toPayload(): Map<String, Any?>
}

data class NoteSnapshot(
    override val id: UUID,
    val userId: UUID?,
    val title: String,
    val contentMarkdown: String,
    val categoryId: String?,
    override val revision: Long,
    val createdAt: Instant,
    val updatedAt: Instant,
    val deletedAt: Instant?,
) : SyncSnapshot {
    override fun toPayload(): Map<String, Any?> = mapOf(
        "id" to id,
        "title" to title,
        "contentMarkdown" to contentMarkdown,
        "categoryId" to categoryId,
        "revision" to revision,
        "createdAt" to createdAt,
        "updatedAt" to updatedAt,
        "deletedAt" to deletedAt,
    )
}

data class LaneSnapshot(
    override val id: UUID,
    val userId: UUID,
    val name: String,
    val sortOrder: Int,
    override val revision: Long,
    val createdAt: Instant,
    val updatedAt: Instant,
    val deletedAt: Instant?,
) : SyncSnapshot {
    override fun toPayload(): Map<String, Any?> = mapOf(
        "id" to id,
        "name" to name,
        "sortOrder" to sortOrder,
        "revision" to revision,
        "createdAt" to createdAt,
        "updatedAt" to updatedAt,
        "deletedAt" to deletedAt,
    )
}

data class TaskSnapshot(
    override val id: UUID,
    val userId: UUID,
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
    override val revision: Long,
    val createdAt: Instant,
    val updatedAt: Instant,
    val deletedAt: Instant?,
) : SyncSnapshot {
    override fun toPayload(): Map<String, Any?> = mapOf(
        "id" to id,
        "title" to title,
        "description" to description,
        "laneId" to laneId,
        "systemState" to systemState,
        "categoryId" to categoryId,
        "priority" to priority,
        "plannedStartAt" to plannedStartAt,
        "plannedEndAt" to plannedEndAt,
        "actualStartAt" to actualStartAt,
        "actualEndAt" to actualEndAt,
        "revision" to revision,
        "createdAt" to createdAt,
        "updatedAt" to updatedAt,
        "deletedAt" to deletedAt,
    )
}

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
