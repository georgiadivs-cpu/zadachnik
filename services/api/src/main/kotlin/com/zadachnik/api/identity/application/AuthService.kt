package com.zadachnik.api.identity.application

import com.zadachnik.api.common.ApiException
import com.zadachnik.api.identity.domain.DevicePlatform
import com.zadachnik.api.identity.domain.DeviceRecord
import com.zadachnik.api.identity.domain.UserRecord
import com.zadachnik.api.identity.domain.UserStatus
import com.zadachnik.api.identity.infrastructure.DeviceRepository
import com.zadachnik.api.identity.infrastructure.RefreshTokenRepository
import com.zadachnik.api.identity.infrastructure.UserRepository
import com.zadachnik.api.sync.infrastructure.LaneRepository
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID
import org.springframework.beans.factory.annotation.Value
import org.springframework.http.HttpStatus
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

data class DeviceCommand(
    val id: UUID,
    val name: String,
    val platform: DevicePlatform,
)

data class SetupCommand(
    val email: String,
    val password: String,
    val device: DeviceCommand,
)

data class LoginCommand(
    val email: String,
    val password: String,
    val device: DeviceCommand,
)

data class AuthResult(
    val userId: UUID,
    val deviceId: UUID,
    val accessToken: String,
    val accessExpiresAt: Instant,
    val refreshToken: String,
    val refreshExpiresAt: Instant,
)

data class DeviceView(
    val id: UUID,
    val name: String,
    val platform: DevicePlatform,
    val createdAt: Instant,
    val lastSeenAt: Instant?,
    val revokedAt: Instant?,
)

@Service
class AuthService(
    private val users: UserRepository,
    private val devices: DeviceRepository,
    private val refreshTokens: RefreshTokenRepository,
    private val lanes: LaneRepository,
    private val passwordEncoder: PasswordEncoder,
    private val jwt: JwtService,
    private val jwtProperties: JwtProperties,
    private val sessionSecurity: SessionSecurityService,
    @Value("\${app.security.setup-token:}") private val setupToken: String,
) {

    @Transactional
    fun setup(providedSetupToken: String, command: SetupCommand): AuthResult {
        if (users.count() > 0) {
            throw ApiException.setupCompleted()
        }
        if (setupToken.isBlank() ||
            !MessageDigest.isEqual(
                setupToken.toByteArray(Charsets.UTF_8),
                providedSetupToken.toByteArray(Charsets.UTF_8),
            )
        ) {
            throw ApiException.setupTokenInvalid()
        }

        if (command.password.length < 12) {
            throw ApiException.validation("Пароль должен содержать не менее 12 символов")
        }

        val email = normalizeEmail(command.email)
        val now = Instant.now()
        val userId = UUID.randomUUID()
        users.insert(userId, email, passwordEncoder.encode(command.password), now)
        lanes.seedDefaults(userId, now)

        val user = users.findById(userId) ?: error("User was not created")
        val device = resolveDevice(user.id, command.device, now)

        return newSession(user, device, now).result
    }

    @Transactional
    fun login(command: LoginCommand): AuthResult {
        val email = normalizeEmail(command.email)
        val user = users.findByEmail(email)
        if (user == null || !passwordEncoder.matches(command.password, user.passwordHash)) {
            throw ApiException.invalidCredentials()
        }
        if (user.status != UserStatus.ACTIVE) {
            throw ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Пользователь заблокирован")
        }

        val now = Instant.now()
        val device = resolveDevice(user.id, command.device, now)
        return newSession(user, device, now).result
    }

    @Transactional
    fun refresh(rawRefreshToken: String): AuthResult {
        val now = Instant.now()
        val stored = refreshTokens.findByHash(TokenHasher.hash(rawRefreshToken))
            ?: throw ApiException.refreshTokenInvalid()

        if (stored.revokedAt != null) {
            if (stored.replacedBy != null) {
                sessionSecurity.revokeDevice(stored.userId, stored.deviceId)
            }
            throw ApiException.refreshTokenInvalid()
        }
        if (stored.expiresAt.isBefore(now)) {
            throw ApiException.refreshTokenInvalid()
        }

        val user = users.findById(stored.userId) ?: throw ApiException.refreshTokenInvalid()
        if (user.status != UserStatus.ACTIVE) {
            throw ApiException.refreshTokenInvalid()
        }
        val device = devices.findById(stored.deviceId) ?: throw ApiException.refreshTokenInvalid()
        if (device.isRevoked || device.userId != user.id) {
            throw ApiException.refreshTokenInvalid()
        }

        val session = newSession(user, device, now)
        refreshTokens.revoke(stored.id, now, session.refreshId)
        return session.result
    }

    @Transactional
    fun logout(rawRefreshToken: String) {
        val stored = refreshTokens.findByHash(TokenHasher.hash(rawRefreshToken)) ?: return
        if (stored.revokedAt == null) {
            refreshTokens.revoke(stored.id, Instant.now(), null)
        }
    }

    fun listDevices(userId: UUID): List<DeviceView> =
        devices.listForUser(userId).map {
            DeviceView(it.id, it.name, it.platform, it.createdAt, it.lastSeenAt, it.revokedAt)
        }

    @Transactional
    fun revokeDevice(userId: UUID, deviceId: UUID) {
        val device = devices.findById(deviceId)
        if (device == null || device.userId != userId) {
            throw ApiException.notFound("Устройство не найдено")
        }
        if (device.isRevoked) {
            return
        }

        val now = Instant.now()
        devices.revoke(deviceId, now)
        refreshTokens.revokeAllForDevice(userId, deviceId, now)
    }

    private fun resolveDevice(userId: UUID, command: DeviceCommand, now: Instant): DeviceRecord {
        val existing = devices.findById(command.id)
        if (existing == null) {
            devices.insert(
                id = command.id,
                userId = userId,
                name = command.name,
                platform = command.platform,
                now = now,
            )
            return devices.findById(command.id) ?: error("Device was not created")
        }

        if (existing.userId != userId) {
            throw ApiException(HttpStatus.FORBIDDEN, "DEVICE_FORBIDDEN", "Устройство недоступно")
        }
        if (existing.isRevoked) {
            throw ApiException.deviceRevoked()
        }

        devices.touch(existing.id, now)
        return existing.copy(lastSeenAt = now)
    }

    private fun newSession(user: UserRecord, device: DeviceRecord, now: Instant): IssuedSession {
        val access = jwt.issueAccess(user.id, device.id, now)
        val refreshToken = TokenHasher.randomToken()
        val refreshId = UUID.randomUUID()
        val refreshExpiresAt = now.plus(jwtProperties.refreshTtl)

        refreshTokens.insert(
            id = refreshId,
            userId = user.id,
            deviceId = device.id,
            tokenHash = TokenHasher.hash(refreshToken),
            expiresAt = refreshExpiresAt,
            now = now,
        )

        return IssuedSession(
            result = AuthResult(
                userId = user.id,
                deviceId = device.id,
                accessToken = access.token,
                accessExpiresAt = access.expiresAt,
                refreshToken = refreshToken,
                refreshExpiresAt = refreshExpiresAt,
            ),
            refreshId = refreshId,
        )
    }

    private fun normalizeEmail(email: String): String = email.trim().lowercase()

    private data class IssuedSession(val result: AuthResult, val refreshId: UUID)
}
