package com.zadachnik.api.identity.web

import com.zadachnik.api.identity.application.AuthResult
import com.zadachnik.api.identity.application.DeviceView
import com.zadachnik.api.identity.domain.DevicePlatform
import jakarta.validation.Valid
import jakarta.validation.constraints.Email
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Size
import java.time.Instant
import java.util.UUID

data class DeviceRequest(
    @field:NotNull
    val id: UUID,
    @field:NotBlank
    @field:Size(max = 100)
    val name: String,
    @field:NotNull
    val platform: DevicePlatform,
)

data class SetupRequest(
    @field:NotBlank
    @field:Email
    val email: String,
    @field:NotBlank
    @field:Size(min = 12, max = 128)
    val password: String,
    @field:Valid
    @field:NotNull
    val device: DeviceRequest,
)

data class LoginRequest(
    @field:NotBlank
    @field:Email
    val email: String,
    @field:NotBlank
    val password: String,
    @field:Valid
    @field:NotNull
    val device: DeviceRequest,
)

data class RefreshRequest(@field:NotBlank val refreshToken: String)

data class AuthResponse(
    val userId: UUID,
    val deviceId: UUID,
    val accessToken: String,
    val accessExpiresAt: Instant,
    val refreshToken: String,
    val refreshExpiresAt: Instant,
) {
    companion object {
        fun from(result: AuthResult): AuthResponse = AuthResponse(
            userId = result.userId,
            deviceId = result.deviceId,
            accessToken = result.accessToken,
            accessExpiresAt = result.accessExpiresAt,
            refreshToken = result.refreshToken,
            refreshExpiresAt = result.refreshExpiresAt,
        )
    }
}

data class DeviceResponse(
    val id: UUID,
    val name: String,
    val platform: DevicePlatform,
    val createdAt: Instant,
    val lastSeenAt: Instant?,
    val revokedAt: Instant?,
) {
    companion object {
        fun from(view: DeviceView): DeviceResponse = DeviceResponse(
            id = view.id,
            name = view.name,
            platform = view.platform,
            createdAt = view.createdAt,
            lastSeenAt = view.lastSeenAt,
            revokedAt = view.revokedAt,
        )
    }
}
