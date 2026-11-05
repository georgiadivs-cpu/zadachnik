package com.zadachnik.api.identity.application

import com.zadachnik.api.identity.infrastructure.DeviceRepository
import com.zadachnik.api.identity.infrastructure.RefreshTokenRepository
import java.time.Instant
import java.util.UUID
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Propagation
import org.springframework.transaction.annotation.Transactional

/**
 * Действия безопасности, которые должны сохраниться, даже если основной
 * сценарий завершается ошибкой. Например, повторное использование refresh
 * токена отзывает устройство, а запрос возвращает 401.
 */
@Service
class SessionSecurityService(
    private val devices: DeviceRepository,
    private val refreshTokens: RefreshTokenRepository,
) {

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun revokeDevice(userId: UUID, deviceId: UUID) {
        val now = Instant.now()
        devices.revoke(deviceId, now)
        refreshTokens.revokeAllForDevice(userId, deviceId, now)
    }
}
