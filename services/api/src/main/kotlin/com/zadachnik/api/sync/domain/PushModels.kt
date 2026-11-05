package com.zadachnik.api.sync.domain

import java.util.UUID

enum class PushStatus { APPLIED, DUPLICATE, CONFLICT, REJECTED }

data class PushResult(
    val operationId: UUID,
    val status: PushStatus,
    val entityId: UUID? = null,
    val revision: Long? = null,
    val changeSeq: Long? = null,
    val serverEntity: NoteSnapshot? = null,
    val code: String? = null,
    val message: String? = null,
)
