package com.zadachnik.api.backup.application

import com.zadachnik.api.backup.infrastructure.BackupPaths
import java.nio.file.Files
import java.nio.file.Path
import java.time.Duration
import java.time.Instant
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Component

data class BackupConfigStatus(
    val configured: Boolean,
    val error: String?,
)

@Component
class BackupConfigChecker(
    private val properties: BackupProperties,
    private val paths: BackupPaths,
    private val crypto: BackupCrypto,
    private val runner: CommandRunner,
    @Value("\${app.attachments.dir:./data/attachments}") attachmentsDir: String,
) {

    private val attachmentsRoot = Path.of(attachmentsDir).toAbsolutePath().normalize()
    @Volatile
    private var cached: Pair<Instant, BackupConfigStatus>? = null

    fun check(): BackupConfigStatus {
        val now = Instant.now()
        cached?.let { (checkedAt, value) ->
            if (Duration.between(checkedAt, now).seconds < CACHE_SECONDS) {
                return value
            }
        }
        val result = runCatching { verify() }.getOrElse { error ->
            BackupConfigStatus(
                configured = false,
                error = error.message ?: "Резервное копирование не настроено",
            )
        }
        cached = now to result
        return result
    }

    private fun verify(): BackupConfigStatus {
        if (paths.root.startsWith(attachmentsRoot) || attachmentsRoot.startsWith(paths.root)) {
            throw IllegalStateException(
                "BACKUP_DIR должен находиться вне ATTACHMENTS_DIR",
            )
        }
        val identity = crypto.identityFile()
        if (identity.toString().startsWith(paths.root.toString())) {
            throw IllegalStateException(
                "Ключ age нельзя хранить внутри BACKUP_DIR",
            )
        }
        crypto.recipient()

        val commands = listOf(properties.ageBinary, properties.pgDump, properties.pgRestore)
        commands.forEach { command ->
            val result = runner.run(
                listOf(command, "--version"),
                timeout = Duration.ofSeconds(15),
            )
            if (result.exitCode != 0) {
                throw IllegalStateException("Команда $command недоступна")
            }
        }
        if (!Files.isWritable(paths.root)) {
            throw IllegalStateException("Каталог BACKUP_DIR недоступен для записи")
        }
        val disk = Files.getFileStore(paths.root)
        if (disk.usableSpace < properties.minFreeBytes) {
            throw IllegalStateException(
                "Недостаточно места на диске резервных копий",
            )
        }
        return BackupConfigStatus(configured = true, error = null)
    }

    companion object {
        private const val CACHE_SECONDS = 20L
    }
}
