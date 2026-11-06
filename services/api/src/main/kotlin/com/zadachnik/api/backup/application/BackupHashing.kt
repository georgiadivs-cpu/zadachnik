package com.zadachnik.api.backup.application

import java.io.InputStream
import java.io.OutputStream
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest

object BackupHashing {

    fun sha256(path: Path): String =
        Files.newInputStream(path).use { sha256(it) }

    fun sha256(input: InputStream): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            digest.update(buffer, 0, read)
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun copyAndHash(input: InputStream, output: OutputStream): Pair<Long, String> {
        val digest = MessageDigest.getInstance("SHA-256")
        var total = 0L
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            digest.update(buffer, 0, read)
            output.write(buffer, 0, read)
            total += read
        }
        return total to digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun isValidSha256(value: String): Boolean =
        value.length == 64 && value.all { it in "0123456789abcdefABCDEF" }
}
