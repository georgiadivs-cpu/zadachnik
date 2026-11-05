package com.zadachnik.api.identity.application

import com.nimbusds.jose.JOSEObjectType
import com.nimbusds.jose.JWSAlgorithm
import com.nimbusds.jose.JWSHeader
import com.nimbusds.jose.crypto.MACSigner
import com.nimbusds.jose.crypto.MACVerifier
import com.nimbusds.jwt.JWTClaimsSet
import com.nimbusds.jwt.SignedJWT
import com.zadachnik.api.common.ApiException
import java.time.Instant
import java.util.Date
import java.util.UUID
import org.springframework.stereotype.Service

data class IssuedAccessToken(val token: String, val expiresAt: Instant)

data class AccessClaims(val userId: UUID, val deviceId: UUID)

@Service
class JwtService(properties: JwtProperties) {

    private val secret = properties.secret.toByteArray(Charsets.UTF_8)
    private val issuer = properties.issuer
    private val audience = properties.audience
    private val accessTtl = properties.accessTtl
    private val signer: MACSigner
    private val verifier: MACVerifier

    init {
        require(secret.size >= 32) { "JWT_SECRET must contain at least 32 bytes" }
        signer = MACSigner(secret)
        verifier = MACVerifier(secret)
    }

    fun issueAccess(userId: UUID, deviceId: UUID, now: Instant = Instant.now()): IssuedAccessToken {
        val expiresAt = now.plus(accessTtl)
        val claims = JWTClaimsSet.Builder()
            .subject(userId.toString())
            .issuer(issuer)
            .audience(audience)
            .issueTime(Date.from(now))
            .expirationTime(Date.from(expiresAt))
            .jwtID(UUID.randomUUID().toString())
            .claim("deviceId", deviceId.toString())
            .build()

        val header = JWSHeader.Builder(JWSAlgorithm.HS256)
            .type(JOSEObjectType.JWT)
            .build()
        val jwt = SignedJWT(header, claims)
        jwt.sign(signer)

        return IssuedAccessToken(jwt.serialize(), expiresAt)
    }

    fun verifyAccess(token: String): AccessClaims {
        try {
            val jwt = SignedJWT.parse(token)
            if (jwt.header.algorithm != JWSAlgorithm.HS256 || !jwt.verify(verifier)) {
                throw ApiException.unauthenticated("Недействительный токен")
            }

            val claims = jwt.jwtClaimsSet
            val expiration = claims.expirationTime
            if (claims.issuer != issuer ||
                audience !in claims.audience.orEmpty() ||
                expiration == null ||
                expiration.toInstant().isBefore(Instant.now())
            ) {
                throw ApiException.unauthenticated("Недействительный токен")
            }

            val userId = claims.subject?.let(UUID::fromString)
                ?: throw ApiException.unauthenticated("Недействительный токен")
            val deviceId = claims.getClaimAsString("deviceId")?.let(UUID::fromString)
                ?: throw ApiException.unauthenticated("Недействительный токен")

            return AccessClaims(userId, deviceId)
        } catch (exception: ApiException) {
            throw exception
        } catch (exception: Exception) {
            throw ApiException.unauthenticated("Недействительный токен")
        }
    }
}
