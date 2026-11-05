package com.zadachnik.api.identity.web

import com.zadachnik.api.common.ApiException
import com.zadachnik.api.identity.application.AuthService
import com.zadachnik.api.identity.application.DeviceCommand
import com.zadachnik.api.identity.application.LoginCommand
import com.zadachnik.api.identity.application.SetupCommand
import jakarta.validation.Valid
import org.springframework.http.HttpStatus
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/v1/auth")
class AuthController(private val auth: AuthService) {

    @PostMapping("/setup")
    @ResponseStatus(HttpStatus.CREATED)
    fun setup(
        @RequestHeader("X-Setup-Token") setupToken: String,
        @Valid @RequestBody request: SetupRequest,
    ): AuthResponse = AuthResponse.from(
        auth.setup(
            providedSetupToken = setupToken,
            command = SetupCommand(
                email = request.email,
                password = request.password,
                device = request.device.toCommand(),
            ),
        ),
    )

    @PostMapping("/login")
    fun login(@Valid @RequestBody request: LoginRequest): AuthResponse = AuthResponse.from(
        auth.login(
            LoginCommand(
                email = request.email,
                password = request.password,
                device = request.device.toCommand(),
            ),
        ),
    )

    @PostMapping("/refresh")
    fun refresh(@Valid @RequestBody request: RefreshRequest): AuthResponse =
        AuthResponse.from(auth.refresh(request.refreshToken))

    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun logout(@Valid @RequestBody request: RefreshRequest) {
        auth.logout(request.refreshToken)
    }

    private fun DeviceRequest.toCommand(): DeviceCommand {
        if (name.isBlank()) {
            throw ApiException.validation("Имя устройства обязательно")
        }
        return DeviceCommand(id = id, name = name.trim(), platform = platform)
    }
}
