package com.zadachnik.api.sync.web

import com.zadachnik.api.common.ApiException
import com.zadachnik.api.sync.application.SyncService
import jakarta.servlet.http.HttpServletRequest
import jakarta.validation.Valid
import java.util.UUID
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/v1/sync")
class SyncController(private val sync: SyncService) {

    @PostMapping("/push")
    fun push(
        authentication: Authentication,
        @Valid @RequestBody request: PushRequest,
        servletRequest: HttpServletRequest,
    ): PushResponse {
        if (servletRequest.contentLengthLong > MAX_PUSH_BYTES) {
            throw ApiException.payloadTooLarge()
        }
        val userId = UUID.fromString(authentication.name)
        val deviceId = deviceId(authentication)
        return PushResponse.from(
            sync.push(userId, deviceId, request.operations.map(PushOperationRequest::toCommand)),
        )
    }

    @GetMapping("/pull")
    fun pull(
        authentication: Authentication,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(required = false) limit: Int?,
    ): PullResponse {
        val userId = UUID.fromString(authentication.name)
        val result = sync.pull(userId, cursor, limit)
        return PullResponse.from(result, sync::payload)
    }

    @GetMapping("/state")
    fun state(authentication: Authentication): SyncStateResponse {
        val userId = UUID.fromString(authentication.name)
        return SyncStateResponse.from(sync.state(userId, deviceId(authentication)))
    }

    private fun deviceId(authentication: Authentication): UUID =
        authentication.details?.toString()?.let(UUID::fromString)
            ?: throw ApiException.unauthenticated("Устройство не определено")

    companion object {
        private const val MAX_PUSH_BYTES = 1L * 1024 * 1024
    }
}
