package com.zadachnik.api.attachment.infrastructure

import com.zadachnik.api.common.ApiException
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.security.DigestInputStream
import java.security.MessageDigest
import java.util.UUID
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service

data class StoredFile(
    val tempPath: Path,
    val sizeBytes: Long,
    val sha256: String,
)

@Service
class LocalAttachmentStorage(
    @Value("\${app.attachments.dir:./data/attachments}") dir: String,
    @Value("\${app.attachments.max-bytes:26214400}") private val maxBytes: Long,
) {

    private val root: Path = Path.of(dir).toAbsolutePath().normalize()

    init {
        Files.createDirectories(root.resolve("tmp"))
    }

    fun saveTemp(userId: UUID, input: InputStream): StoredFile {
        val temp = root.resolve("tmp")
            .resolve("${UUID.randomUUID()}.part")
        val digest = MessageDigest.getInstance("SHA-256")
        var total = 0L
        try {
            DigestInputStream(input, digest).use { stream ->
                Files.newOutputStream(temp).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val read = stream.read(buffer)
                        if (read < 0) {
                            break
                        }
                        total += read
                        if (total > maxBytes) {
                            throw ApiException.payloadTooLarge()
                        }
                        output.write(buffer, 0, read)
                    }
                }
            }
            if (total == 0L) {
                throw ApiException.validation("Файл пуст")
            }
            return StoredFile(
                tempPath = temp,
                sizeBytes = total,
                sha256 = digest.digest().joinToString("") { "%02x".format(it) },
            )
        } catch (exception: Exception) {
            Files.deleteIfExists(temp)
            throw exception
        }
    }

    fun commit(tempPath: Path, userId: UUID, attachmentId: UUID): Path {
        val userDir = root.resolve(userId.toString())
        Files.createDirectories(userDir)
        val target = userDir.resolve(attachmentId.toString())
        try {
            Files.move(
                tempPath,
                target,
                StandardCopyOption.REPLACE_EXISTING,
                StandardCopyOption.ATOMIC_MOVE,
            )
        } catch (_: Exception) {
            Files.move(tempPath, target, StandardCopyOption.REPLACE_EXISTING)
        }
        return target
    }

    fun resolve(userId: UUID, attachmentId: UUID): Path =
        root.resolve(userId.toString()).resolve(attachmentId.toString())

    fun delete(userId: UUID, attachmentId: UUID) {
        Files.deleteIfExists(resolve(userId, attachmentId))
    }

    fun deleteTemp(path: Path) {
        Files.deleteIfExists(path)
    }

    fun maxBytes(): Long = maxBytes
}
