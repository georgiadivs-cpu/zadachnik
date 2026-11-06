package com.zadachnik.api.backup.application

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermission
import org.springframework.stereotype.Component

@Component
class BackupCrypto(
    private val properties: BackupProperties,
    private val runner: CommandRunner,
) {
    private val timeout: java.time.Duration = java.time.Duration.ofSeconds(30)

    fun recipient(): String {
        val configured = properties.ageRecipient.trim()
        if (configured.isNotEmpty()) {
            return configured
        }
        val identity = identityFile()
        val result = runner.run(
            listOf(properties.ageKeygenBinary, "-y", identity.toString()),
            timeout = timeout,
        )
        if (result.exitCode != 0) {
            throw IllegalStateException(
                "Не удалось получить age-recipient: ${result.output.take(500)}",
            )
        }
        val value = result.output.lineSequence()
            .map { it.trim() }
            .firstOrNull { it.startsWith("age1") }
            ?: throw IllegalStateException("age-keygen не вернул публичный ключ")
        return value
    }

    fun encrypt(input: Path, output: Path) {
        val result = runner.run(
            listOf(
                properties.ageBinary,
                "--encrypt",
                "--recipient",
                recipient(),
                "--output",
                output.toString(),
                input.toString(),
            ),
            timeout = properties.processTimeout,
        )
        if (result.exitCode != 0) {
            throw IllegalStateException(
                "age не зашифровал архив: ${result.output.take(1_000)}",
            )
        }
    }

    fun decrypt(input: Path, output: Path) {
        val result = runner.run(
            listOf(
                properties.ageBinary,
                "--decrypt",
                "--identity",
                identityFile().toString(),
                "--output",
                output.toString(),
                input.toString(),
            ),
            timeout = properties.processTimeout,
        )
        if (result.exitCode != 0) {
            throw IllegalStateException(
                "age не расшифровал архив: ${result.output.take(1_000)}",
            )
        }
    }

    fun identityFile(): Path {
        val raw = properties.ageIdentity.trim()
        if (raw.isEmpty()) {
            throw IllegalStateException(
                "Не задан BACKUP_AGE_IDENTITY — резервное копирование не настроено",
            )
        }
        val path = Path.of(raw).toAbsolutePath().normalize()
        if (!Files.isRegularFile(path)) {
            throw IllegalStateException("Файл ключа age не найден: $path")
        }
        if (Files.isSymbolicLink(path)) {
            throw IllegalStateException("Файл ключа age не должен быть символической ссылкой")
        }
        try {
            val permissions = Files.getPosixFilePermissions(path)
            val exposed = permissions.any {
                it in setOf(
                    PosixFilePermission.GROUP_READ,
                    PosixFilePermission.GROUP_WRITE,
                    PosixFilePermission.GROUP_EXECUTE,
                    PosixFilePermission.OTHERS_READ,
                    PosixFilePermission.OTHERS_WRITE,
                    PosixFilePermission.OTHERS_EXECUTE,
                )
            }
            if (exposed) {
                throw IllegalStateException("Права на ключ age должны быть 0600")
            }
        } catch (_: UnsupportedOperationException) {
            // Windows ACL: проверка POSIX-прав недоступна.
        }
        return path
    }
}
