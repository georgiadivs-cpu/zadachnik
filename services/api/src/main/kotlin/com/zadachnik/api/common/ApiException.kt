package com.zadachnik.api.common

import org.springframework.http.HttpStatus

class ApiException(
    val status: HttpStatus,
    val code: String,
    override val message: String,
    val details: Map<String, Any?>? = null,
) : RuntimeException(message) {
    companion object {
        fun validation(message: String, details: Map<String, Any?>? = null): ApiException =
            ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", message, details)

        fun unauthenticated(message: String = "Требуется авторизация"): ApiException =
            ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHENTICATED", message)

        fun invalidCredentials(): ApiException =
            ApiException(HttpStatus.UNAUTHORIZED, "INVALID_CREDENTIALS", "Неверный email или пароль")

        fun refreshTokenInvalid(): ApiException =
            ApiException(HttpStatus.UNAUTHORIZED, "REFRESH_TOKEN_INVALID", "Сессия недействительна")

        fun setupTokenInvalid(): ApiException =
            ApiException(HttpStatus.UNAUTHORIZED, "SETUP_TOKEN_INVALID", "Неверный setup token")

        fun setupCompleted(): ApiException =
            ApiException(HttpStatus.CONFLICT, "SETUP_ALREADY_COMPLETED", "Владелец уже создан")

        fun deviceRevoked(): ApiException =
            ApiException(HttpStatus.FORBIDDEN, "DEVICE_REVOKED", "Устройство отозвано")

        fun notFound(message: String = "Объект не найден"): ApiException =
            ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND", message)

        fun payloadTooLarge(): ApiException =
            ApiException(HttpStatus.PAYLOAD_TOO_LARGE, "PAYLOAD_TOO_LARGE", "Слишком большой пакет")
    }
}
