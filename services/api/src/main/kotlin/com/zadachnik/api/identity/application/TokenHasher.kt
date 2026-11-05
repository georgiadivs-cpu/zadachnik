package com.zadachnik.api.identity.application

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

object TokenHasher {
    private val random = SecureRandom()

    fun randomToken(): String {
        val bytes = ByteArray(32)
        random.nextBytes(bytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }

    fun hash(token: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(token.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
}
