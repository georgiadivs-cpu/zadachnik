package com.zadachnik.api.identity.domain

import java.time.Instant
import java.util.UUID

enum class UserStatus { ACTIVE, DISABLED }

enum class DevicePlatform { ANDROID, IOS, MACOS, WINDOWS }

data class UserRecord(
    val id: UUID,
    val email: String,
    val passwordHash: String,
    val status: UserStatus,
)

data class DeviceRecord(
    val id: UUID,
    val userId: UUID,
    val name: String,
    val platform: DevicePlatform,
    val createdAt: Instant,
    val lastSeenAt: Instant?,
    val revokedAt: Instant?,
) {
    val isRevoked: Boolean get() = revokedAt != null
}

data class RefreshTokenRecord(
    val id: UUID,
    val userId: UUID,
    val deviceId: UUID,
    val tokenHash: String,
    val expiresAt: Instant,
    val revokedAt: Instant?,
    val replacedBy: UUID?,
)
