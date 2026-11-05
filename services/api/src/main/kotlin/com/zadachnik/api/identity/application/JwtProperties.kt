package com.zadachnik.api.identity.application

import java.time.Duration
import org.springframework.boot.context.properties.ConfigurationProperties

@ConfigurationProperties(prefix = "app.security.jwt")
data class JwtProperties(
    var secret: String = "",
    var issuer: String = "zadachnik-api",
    var audience: String = "zadachnik-client",
    var accessTtl: Duration = Duration.ofMinutes(15),
    var refreshTtl: Duration = Duration.ofDays(30),
)
