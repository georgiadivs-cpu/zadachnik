package com.zadachnik.api.backup.infrastructure

import com.fasterxml.jackson.databind.ObjectMapper
import com.zadachnik.api.backup.domain.BackupArchive
import com.zadachnik.api.backup.domain.BackupState
import com.zadachnik.api.backup.domain.DeviceSnapshot
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.util.UUID
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Component

@Component
class BackupStateStore(
    private val paths: BackupPaths,
    private val objectMapper: ObjectMapper,
) {

    private val log = LoggerFactory.getLogger(javaClass)
    private val monitor = Any()

    fun readState(userId: UUID): BackupState {
        val file = paths.stateFile(userId)
        if (!Files.isRegularFile(file)) {
            return BackupState()
        }
        return runCatching {
            objectMapper.readValue(Files.readString(file), BackupState::class.java)
        }.getOrElse {
            log.warn("Backup state is unreadable: {}", file, it)
            BackupState(lastError = "Файл состояния повреждён")
        }
    }

    fun writeState(userId: UUID, state: BackupState) {
        synchronized(monitor) {
            writeJson(paths.stateFile(userId), state)
        }
    }

    fun updateState(userId: UUID, transform: (BackupState) -> BackupState): BackupState {
        synchronized(monitor) {
            val updated = transform(readState(userId))
            writeJson(paths.stateFile(userId), updated)
            return updated
        }
    }

    fun listArchives(userId: UUID): List<BackupArchive> {
        val dir = paths.archivesDir(userId)
        val files = Files.list(dir).use { stream ->
            stream.filter { it.fileName.toString().endsWith(".json") }.toList()
        }
        return files.mapNotNull { file -> readJson(file, BackupArchive::class.java) }
            .sortedByDescending { it.createdAt }
    }

    fun findArchive(userId: UUID, archiveId: String): BackupArchive? =
        listArchives(userId).firstOrNull { it.id == archiveId }

    fun saveArchive(userId: UUID, archive: BackupArchive) {
        synchronized(monitor) {
            writeJson(
                paths.archivesDir(userId).resolve("${archive.id}.json"),
                archive,
            )
        }
    }

    fun deleteArchive(userId: UUID, archive: BackupArchive) {
        synchronized(monitor) {
            Files.deleteIfExists(paths.archivesDir(userId).resolve("${archive.id}.json"))
            Files.deleteIfExists(paths.archivesDir(userId).resolve(archive.fileName))
        }
    }

    fun containsArchiveFile(userId: UUID, fileName: String): Boolean =
        Files.isRegularFile(paths.archivesDir(userId).resolve(fileName))

    fun listDeviceSnapshots(userId: UUID): List<DeviceSnapshot> {
        val devicesRoot = paths.devicesRoot(userId)
        val deviceDirs = Files.list(devicesRoot).use { stream ->
            stream.filter { Files.isDirectory(it) }.toList()
        }
        return deviceDirs.flatMap { deviceDir ->
            val files = Files.list(deviceDir).use { stream ->
                stream.filter { it.fileName.toString().endsWith(".json") }.toList()
            }
            files.mapNotNull { file -> readJson(file, DeviceSnapshot::class.java) }
        }.sortedByDescending { it.createdAt }
    }

    fun saveDeviceSnapshot(snapshot: DeviceSnapshot) {
        synchronized(monitor) {
            val userId = UUID.fromString(snapshot.userId)
            val deviceId = UUID.fromString(snapshot.deviceId)
            writeJson(
                paths.deviceDir(userId, deviceId).resolve("${snapshot.id}.json"),
                snapshot,
            )
        }
    }

    fun deleteDeviceSnapshot(snapshot: DeviceSnapshot) {
        val userId = UUID.fromString(snapshot.userId)
        val deviceId = UUID.fromString(snapshot.deviceId)
        val dir = paths.deviceDir(userId, deviceId)
        synchronized(monitor) {
            Files.deleteIfExists(dir.resolve("${snapshot.id}.json"))
            Files.deleteIfExists(dir.resolve(snapshot.fileName))
        }
    }

    private fun <T> readJson(file: Path, type: Class<T>): T? = runCatching {
        objectMapper.readValue(Files.readString(file), type)
    }.getOrElse {
        log.warn("Backup metadata is unreadable: {}", file, it)
        null
    }

    private fun writeJson(file: Path, value: Any) {
        val parent = file.parent
        Files.createDirectories(parent)
        val temp = parent.resolve("${file.fileName}.tmp")
        objectMapper.writerWithDefaultPrettyPrinter()
            .writeValue(temp.toFile(), value)
        try {
            Files.move(
                temp,
                file,
                StandardCopyOption.REPLACE_EXISTING,
                StandardCopyOption.ATOMIC_MOVE,
            )
        } catch (_: Exception) {
            Files.move(temp, file, StandardCopyOption.REPLACE_EXISTING)
        }
    }
}
