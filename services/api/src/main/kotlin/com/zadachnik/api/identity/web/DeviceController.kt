package com.zadachnik.api.identity.web

import com.zadachnik.api.identity.application.AuthService
import java.util.UUID
import org.springframework.http.HttpStatus
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/v1/devices")
class DeviceController(private val auth: AuthService) {

    @GetMapping
    fun list(authentication: Authentication): List<DeviceResponse> =
        auth.listDevices(UUID.fromString(authentication.name)).map(DeviceResponse::from)

    @DeleteMapping("/{deviceId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun revoke(authentication: Authentication, @PathVariable deviceId: UUID) {
        auth.revokeDevice(UUID.fromString(authentication.name), deviceId)
    }
}
