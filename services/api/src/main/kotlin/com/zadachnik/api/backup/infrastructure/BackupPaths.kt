package com.zadachnik.api.backup.infrastructure

import com.zadachnik.api.backup.application.BackupProperties
import com.zadachnik.api.common.ApiException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermission
import java.util.UUID
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Component

@Component
class BackupPaths(properties: BackupProperties) {

    val root: Path = Path.of(properties.dir).toAbsolutePath().normalize()

    init {
        Files.createDirectories(root)
        runCatching {
            Files.setPosixFilePermissions(
                root,
                setOf(
                    PosixFilePermission.OWNER_READ,
                    PosixFilePermission.OWNER_WRITE,
                    PosixFilePermission.OWNER_EXECUTE,
                ),
            )
        }
    }

    fun userDir(userId: UUID): Path = ensure(root.resolve(userId.toString()))

    fun archivesDir(userId: UUID): Path = ensure(userDir(userId).resolve("archives"))

    fun devicesRoot(userId: UUID): Path = ensure(userDir(userId).resolve("devices"))

    fun deviceDir(userId: UUID, deviceId: UUID): Path =
        ensure(devicesRoot(userId).resolve(deviceId.toString()))

    fun workRoot(): Path = ensure(root.resolve("tmp"))

    fun stateFile(userId: UUID): Path = userDir(userId).resolve("state.json")

    fun lockFile(userId: UUID): Path = userDir(userId).resolve("backup.lock")

    fun verifyPathInsideRoot(path: Path): Path {
        val normalized = path.toAbsolutePath().normalize()
        if (!normalized.startsWith(root)) {
            throw ApiException(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "BACKUP_PATH_ESCAPE",
                "Некорректный путь резервной копии",
            )
        }
        return normalized
    }

    private fun ensure(path: Path): Path {
        Files.createDirectories(path)
        return path
    }
}
