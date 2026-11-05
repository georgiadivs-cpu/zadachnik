package com.zadachnik.api.common

import com.fasterxml.jackson.annotation.JsonInclude

data class ApiErrorResponse(val error: ApiError)

@JsonInclude(JsonInclude.Include.NON_NULL)
data class ApiError(
    val code: String,
    val message: String,
    val details: Map<String, Any?>? = null,
    val requestId: String,
)
