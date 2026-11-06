package com.zadachnik.api.attachment.application

import com.zadachnik.api.common.ApiException
import java.nio.file.Files
import java.nio.file.Path

object AttachmentRules {

    private val extensionMime = mapOf(
        "jpg" to "image/jpeg",
        "jpeg" to "image/jpeg",
        "png" to "image/png",
        "webp" to "image/webp",
        "heic" to "image/heic",
        "heif" to "image/heic",
        "pdf" to "application/pdf",
        "txt" to "text/plain",
        "md" to "text/markdown",
        "markdown" to "text/markdown",
        "mp3" to "audio/mpeg",
        "m4a" to "audio/mp4",
    )

    fun validateAndNormalize(
        fileName: String,
        declaredMime: String?,
        path: Path,
    ): String {
        val extension = fileName.substringAfterLast('.', "").lowercase()
        val expected = extensionMime[extension]
            ?: throw ApiException.validation("Тип файла не разрешён: .$extension")
        val declared = normalizeMime(declaredMime)
        if (declared != null &&
            declared != "application/octet-stream" &&
            declared != expected
        ) {
            throw ApiException.validation("MIME-тип файла не совпадает с расширением")
        }
        val header = Files.newInputStream(path).use { it.readNBytes(512) }
        if (!matchesMagic(expected, header)) {
            throw ApiException.validation("Содержимое файла не соответствует типу")
        }
        return expected
    }

    fun sanitizeFileName(raw: String): String {
        val base = raw.substringAfterLast('/').substringAfterLast('\\').trim()
        if (base.isEmpty()) {
            throw ApiException.validation("Имя файла обязательно")
        }
        if (base.length > 255) {
            throw ApiException.validation("Имя файла слишком длинное")
        }
        if (base.any { it.code < 32 }) {
            throw ApiException.validation("Имя файла содержит недопустимые символы")
        }
        return base
    }

    private fun normalizeMime(value: String?): String? {
        val normalized = value?.substringBefore(';')?.trim()?.lowercase() ?: return null
        return when (normalized) {
            "image/jpg", "image/pjpeg" -> "image/jpeg"
            "text/x-markdown" -> "text/markdown"
            "audio/x-m4a", "audio/m4a" -> "audio/mp4"
            else -> normalized
        }
    }

    private fun matchesMagic(mime: String, bytes: ByteArray): Boolean = when (mime) {
        "image/jpeg" -> bytes.size >= 3 &&
            bytes[0] == 0xFF.toByte() &&
            bytes[1] == 0xD8.toByte() &&
            bytes[2] == 0xFF.toByte()

        "image/png" -> bytes.size >= 8 &&
            bytes[0] == 0x89.toByte() &&
            bytes[1] == 0x50.toByte() &&
            bytes[2] == 0x4E.toByte() &&
            bytes[3] == 0x47.toByte()

        "image/webp" -> bytes.size >= 12 &&
            String(bytes, 0, 4, Charsets.US_ASCII) == "RIFF" &&
            String(bytes, 8, 4, Charsets.US_ASCII) == "WEBP"

        "image/heic" -> bytes.size >= 12 &&
            String(bytes, 4, 4, Charsets.US_ASCII) == "ftyp" &&
            String(bytes, 8, 4, Charsets.US_ASCII) in
            setOf("heic", "heix", "hevc", "mif1", "msf1")

        "application/pdf" -> bytes.size >= 4 &&
            String(bytes, 0, 4, Charsets.US_ASCII) == "%PDF"

        "audio/mpeg" -> bytes.size >= 3 && (
            String(bytes, 0, 3, Charsets.US_ASCII) == "ID3" ||
                (bytes[0] == 0xFF.toByte() && (bytes[1].toInt() and 0xE0) == 0xE0)
            )

        "audio/mp4" -> bytes.size >= 12 &&
            String(bytes, 4, 4, Charsets.US_ASCII) == "ftyp"

        "text/plain", "text/markdown" -> !bytes.contains(0.toByte())

        else -> false
    }
}
