package com.zadachnik.api.common

import java.util.UUID
import org.slf4j.LoggerFactory
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.http.converter.HttpMessageNotReadableException
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.multipart.MaxUploadSizeExceededException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice

@RestControllerAdvice
class GlobalExceptionHandler {

    private val log = LoggerFactory.getLogger(GlobalExceptionHandler::class.java)

    @ExceptionHandler(ApiException::class)
    fun handleApiException(exception: ApiException): ResponseEntity<ApiErrorResponse> =
        response(exception.status, exception.code, exception.message, exception.details)

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(exception: MethodArgumentNotValidException): ResponseEntity<ApiErrorResponse> {
        val details = exception.bindingResult.fieldErrors.associate {
            it.field to (it.defaultMessage ?: "Некорректное значение")
        }
        return response(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "Проверьте заполнение полей", details)
    }

    @ExceptionHandler(MaxUploadSizeExceededException::class)
    fun handleUploadTooLarge(exception: MaxUploadSizeExceededException): ResponseEntity<ApiErrorResponse> =
        response(
            HttpStatus.PAYLOAD_TOO_LARGE,
            "PAYLOAD_TOO_LARGE",
            "Файл больше допустимого размера",
        )

    @ExceptionHandler(HttpMessageNotReadableException::class)
    fun handleUnreadable(exception: HttpMessageNotReadableException): ResponseEntity<ApiErrorResponse> =
        response(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "Некорректный формат запроса")

    @ExceptionHandler(Exception::class)
    fun handleUnexpected(exception: Exception): ResponseEntity<ApiErrorResponse> {
        val requestId = UUID.randomUUID().toString()
        log.error("Unexpected error, requestId={}", requestId, exception)
        return response(
            HttpStatus.INTERNAL_SERVER_ERROR,
            "INTERNAL_ERROR",
            "Внутренняя ошибка. Повторите попытку позже.",
            requestId = requestId,
        )
    }

    private fun response(
        status: HttpStatus,
        code: String,
        message: String,
        details: Map<String, Any?>? = null,
        requestId: String = UUID.randomUUID().toString(),
    ): ResponseEntity<ApiErrorResponse> = ResponseEntity
        .status(status)
        .body(ApiErrorResponse(ApiError(code, message, details, requestId)))
}
