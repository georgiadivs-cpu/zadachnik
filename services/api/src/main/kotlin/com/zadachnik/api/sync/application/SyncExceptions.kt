package com.zadachnik.api.sync.application

import com.zadachnik.api.sync.domain.SyncSnapshot

class OperationRejected(
    val code: String,
    override val message: String,
) : RuntimeException(message)

class OperationConflict(val server: SyncSnapshot) : RuntimeException("Conflict")
