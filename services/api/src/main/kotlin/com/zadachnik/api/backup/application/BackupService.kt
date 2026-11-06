package com.zadachnik.api.backup.application

import com.fasterxml.jackson.databind.ObjectMapper
import com.zadachnik.api.backup.domain.BackupArchive
import com.zadachnik.api.backup.domain.BackupDeviceInfo
import com.zadachnik.api.backup.domain.BackupDownload
import com.zadachnik.api.backup.domain.BackupDiskInfo
import com.zadachnik.api.backup.domain.BackupState
import com.zadachnik.api.backup.domain.BackupStatus
import com.zadachnik.api.backup.domain.DeviceSnapshot
import com.zadachnik.api.backup.domain.DeviceSnapshotUpload
import com.zadachnik.api.backup.domain.RetentionDescription
import com.zadachnik.api.backup.infrastructure.BackupPaths
import com.zadachnik.api.backup.infrastructure.BackupStateStore
import com.zadachnik.api.common.ApiException
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.http.HttpStatus
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Service

@Service
class BackupService(
    private val properties: BackupProperties,
    private val paths: BackupPaths,
    private val store: BackupStateStore,
    private val crypto: BackupCrypto,
    private val config: BackupConfigChecker,
    private val zip: BackupZip,
    private val runner: CommandRunner,
    private val postgres: PostgresConnectionFactory,
    private val jdbc: JdbcClient,
    private val objectMapper: ObjectMapper,
    @Value("\${app.attachments.dir:./data/attachments}") attachmentsDir: String,
    private val clock: Clock = Clock.systemUTC(),
) {

    private val log = LoggerFactory.getLogger(javaClass)
    private val attachmentsRoot = Path.of(attachmentsDir).toAbsolutePath().normalize()
    private val timestamp = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")
        .withZone(ZoneOffset.UTC)

    fun ensureConfigured() {
        requireConfigured()
    }

    fun status(userId: UUID): BackupStatus {
        val configuration = config.check()
        val state = store.readState(userId)
        val archives = store.listArchives(userId)
        val snapshots = store.listDeviceSnapshots(userId)
        val devices = snapshots.groupBy { it.deviceId }
            .mapNotNull { (deviceId, items) ->
                val latest = items.maxByOrNull { it.createdAt } ?: return@mapNotNull null
                BackupDeviceInfo(
                    deviceId = deviceId,
                    latest = latest,
                    snapshotCount = items.size,
                )
            }
            .sortedByDescending { it.latest.createdAt }
        val disk = runCatching { Files.getFileStore(paths.root) }.getOrNull()
        return BackupStatus(
            configured = configuration.configured,
            configError = configuration.error,
            state = state,
            archives = archives,
            devices = devices,
            disk = BackupDiskInfo(
                freeBytes = disk?.usableSpace ?: 0,
                totalBytes = disk?.totalSpace ?: 0,
            ),
            retention = RetentionDescription(
                recent = properties.retentionRecent,
                weekly = properties.retentionWeekly,
                monthly = properties.retentionMonthly,
                deviceSnapshots = properties.deviceRetention,
            ),
        )
    }

    fun run(userId: UUID) {
        requireConfigured()
        withUserLock(userId) {
            val work = Files.createTempDirectory(paths.workRoot(), "backup-")
            val startedAt = Instant.now(clock)
            store.updateState(userId) {
                it.copy(
                    running = true,
                    operation = "BACKUP",
                    startedAt = startedAt,
                    lastAttemptAt = startedAt,
                    lastError = null,
                )
            }
            try {
                val dump = work.resolve("database.dump")
                dumpDatabase(dump)
                val dumpSha = BackupHashing.sha256(dump)
                val counts = counts()
                val schemaVersion = schemaVersion()
                val attachments = attachmentSources()
                val snapshots = latestSnapshotSources(userId)

                val zipPath = work.resolve("archive.zip")
                zip.write(
                    destination = zipPath,
                    dump = dump,
                    dumpSha256 = dumpSha,
                    schemaVersion = schemaVersion,
                    counts = counts,
                    createdAt = startedAt,
                    attachments = attachments,
                    deviceSnapshots = snapshots,
                )

                val archiveId = UUID.randomUUID().toString()
                val fileName = "zadachnik-${timestamp.format(startedAt)}-" +
                    "${archiveId.take(8)}.zip.age"
                val encryptedTemp = work.resolve("$fileName.tmp")
                crypto.encrypt(zipPath, encryptedTemp)
                val sha = BackupHashing.sha256(encryptedTemp)
                val size = Files.size(encryptedTemp)

                val finishedAt = Instant.now(clock)
                val target = paths.archivesDir(userId).resolve(fileName)
                moveAtomically(encryptedTemp, target)
                val success = BackupArchive(
                    id = archiveId,
                    fileName = fileName,
                    createdAt = startedAt,
                    finishedAt = finishedAt,
                    sizeBytes = size,
                    sha256 = sha,
                    status = BackupArchive.STATUS_SUCCESS,
                    schemaVersion = schemaVersion,
                    counts = counts,
                )
                store.saveArchive(userId, success)
                store.updateState(userId) {
                    it.copy(
                        running = true,
                        operation = "VERIFY",
                        lastSuccessAt = finishedAt,
                        lastError = null,
                    )
                }

                try {
                    val verified = verifyArchiveFile(userId, success, work)
                    store.saveArchive(userId, verified)
                    store.updateState(userId) {
                        it.copy(
                            lastVerifiedAt = verified.verifiedAt,
                            lastError = null,
                        )
                    }
                    pruneArchives(userId)
                } catch (exception: Exception) {
                    val message = "Копия создана, но проверка не удалась: " +
                        (exception.message ?: "неизвестная ошибка")
                    store.updateState(userId) { it.copy(lastError = message) }
                    throw IllegalStateException(message, exception)
                }
            } catch (exception: Exception) {
                store.updateState(userId) {
                    it.copy(lastError = safeMessage(exception))
                }
                throw exception
            } finally {
                deleteRecursively(work)
            }
        }
    }

    fun verify(userId: UUID, archiveId: String): BackupArchive {
        requireConfigured()
        val archive = store.findArchive(userId, archiveId)
            ?: throw ApiException.notFound("Резервная копия не найдена")
        val file = paths.archivesDir(userId).resolve(archive.fileName)
        if (!Files.isRegularFile(file)) {
            throw ApiException.notFound("Файл резервной копии не найден")
        }
        return withUserLock(userId) {
            val work = Files.createTempDirectory(paths.workRoot(), "verify-")
            store.updateState(userId) {
                it.copy(
                    running = true,
                    operation = "VERIFY",
                    startedAt = Instant.now(clock),
                    lastAttemptAt = Instant.now(clock),
                    lastError = null,
                )
            }
            try {
                val verified = verifyArchiveFile(userId, archive, work)
                store.saveArchive(userId, verified)
                store.updateState(userId) {
                    it.copy(
                        lastVerifiedAt = verified.verifiedAt,
                        lastError = null,
                    )
                }
                verified
            } catch (exception: Exception) {
                store.updateState(userId) {
                    it.copy(lastError = safeMessage(exception))
                }
                throw exception
            } finally {
                deleteRecursively(work)
            }
        }
    }

    fun uploadDeviceSnapshot(upload: DeviceSnapshotUpload): DeviceSnapshot {
        requireConfigured()
        if (upload.schemaVersion <= 0) {
            throw ApiException.validation("Некорректная версия схемы")
        }
        if (!BackupHashing.isValidSha256(upload.declaredSha256)) {
            throw ApiException.validation("Некорректный SHA-256 снимка")
        }
        return withUserLock(upload.userId) {
            val existing = store.listDeviceSnapshots(upload.userId).firstOrNull {
                it.deviceId == upload.deviceId.toString() &&
                    it.sha256.equals(upload.declaredSha256, ignoreCase = true)
            }
            if (existing != null) {
                return@withUserLock existing
            }
            val work = Files.createTempDirectory(paths.workRoot(), "device-")
            val raw = work.resolve("snapshot.db")
            try {
                var total = 0L
                val digest = java.security.MessageDigest.getInstance("SHA-256")
                Files.newOutputStream(raw).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val read = upload.input.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > properties.deviceSnapshotMaxBytes) {
                            throw ApiException.payloadTooLarge()
                        }
                        digest.update(buffer, 0, read)
                        output.write(buffer, 0, read)
                    }
                }
                if (total == 0L) {
                    throw ApiException.validation("Снимок пуст")
                }
                val actual = digest.digest().joinToString("") { "%02x".format(it) }
                if (!actual.equals(upload.declaredSha256, ignoreCase = true)) {
                    throw ApiException.validation("SHA-256 снимка не совпадает")
                }
                validateSqliteHeader(raw)

                val createdAt = Instant.now(clock)
                val id = UUID.randomUUID().toString()
                val fileName = "snapshot-${timestamp.format(createdAt)}-" +
                    "${id.take(8)}.db.age"
                val encrypted = work.resolve("$fileName.tmp")
                crypto.encrypt(raw, encrypted)
                val encryptedSha = BackupHashing.sha256(encrypted)
                val size = Files.size(encrypted)
                val target = paths.deviceDir(upload.userId, upload.deviceId).resolve(fileName)
                moveAtomically(encrypted, target)
                val snapshot = DeviceSnapshot(
                    id = id,
                    userId = upload.userId.toString(),
                    deviceId = upload.deviceId.toString(),
                    fileName = fileName,
                    createdAt = createdAt,
                    sizeBytes = size,
                    sha256 = actual,
                    encryptedSha256 = encryptedSha,
                    schemaVersion = upload.schemaVersion,
                )
                store.saveDeviceSnapshot(snapshot)
                pruneDeviceSnapshots(upload.userId, upload.deviceId)
                snapshot
            } finally {
                deleteRecursively(work)
            }
        }
    }

    fun download(userId: UUID, archiveId: String): BackupDownload {
        val archive = store.findArchive(userId, archiveId)
            ?: throw ApiException.notFound("Резервная копия не найдена")
        val file = paths.archivesDir(userId).resolve(archive.fileName)
        if (!Files.isRegularFile(file)) {
            throw ApiException.notFound("Файл резервной копии не найден")
        }
        return BackupDownload(file, archive.fileName)
    }

    private fun verifyArchiveFile(
        userId: UUID,
        archive: BackupArchive,
        work: Path,
    ): BackupArchive {
        val file = paths.archivesDir(userId).resolve(archive.fileName)
        if (!Files.isRegularFile(file)) {
            throw IllegalStateException("Файл архива исчез")
        }
        val decrypted = work.resolve("verify.zip")
        crypto.decrypt(file, decrypted)
        zip.verify(
            zipPath = decrypted,
            workDir = work,
            pgRestore = properties.pgRestore,
            runner = runner,
            timeout = properties.processTimeout,
        )
        return archive.copy(
            status = BackupArchive.STATUS_VERIFIED,
            verifiedAt = Instant.now(clock),
        )
    }

    private fun dumpDatabase(destination: Path) {
        val connection = postgres.current()
        val result = runner.run(
            listOf(
                properties.pgDump,
                "--format=custom",
                "--no-owner",
                "--no-privileges",
                "--file",
                destination.toString(),
            ),
            environment = connection.environment(),
            timeout = properties.processTimeout,
        )
        if (result.exitCode != 0) {
            throw IllegalStateException(
                "pg_dump завершился с ошибкой: ${result.output.take(1_000)}",
            )
        }
        if (!Files.isRegularFile(destination) || Files.size(destination) == 0L) {
            throw IllegalStateException("pg_dump создал пустой файл")
        }
    }

    private fun counts(): Map<String, Long> = mapOf(
        "users" to count("users"),
        "notes" to count("notes", "deleted_at is null"),
        "tasks" to count("tasks", "deleted_at is null"),
        "attachments" to count("attachments", "deleted_at is null"),
    )

    private fun count(table: String, where: String? = null): Long {
        val sql = if (where == null) {
            "select count(*) from $table"
        } else {
            "select count(*) from $table where $where"
        }
        return jdbc.sql(sql).query(Long::class.java).single()
    }

    private fun schemaVersion(): String? = runCatching {
        jdbc.sql(
            """
            select version from flyway_schema_history
            where success = true
            order by installed_rank desc
            limit 1
            """,
        ).query(String::class.java).optional().orElse(null)
    }.getOrNull()

    private fun attachmentSources(): List<AttachmentSource> {
        val rows = jdbc.sql(
            """
            select user_id, storage_key, sha256, size_bytes
            from attachments
            where deleted_at is null
            order by user_id, storage_key
            """,
        ).query { rs, _ ->
            AttachmentRow(
                userId = rs.getObject("user_id", UUID::class.java),
                storageKey = rs.getString("storage_key"),
                sha256 = rs.getString("sha256"),
                sizeBytes = rs.getLong("size_bytes"),
            )
        }.list()
        return rows.map { row ->
            val safeKey = Path.of(row.storageKey).fileName.toString()
            if (safeKey != row.storageKey) {
                throw IllegalStateException("Некорректный storage_key вложения")
            }
            val source = attachmentsRoot.resolve(row.userId.toString()).resolve(safeKey)
            if (!Files.isRegularFile(source)) {
                throw IllegalStateException(
                    "Файл вложения ${row.sha256.take(8)} не найден",
                )
            }
            AttachmentSource(
                entryName = "attachments/${row.userId}/${safeKey}",
                path = source,
                expectedSha256 = row.sha256,
                expectedSize = row.sizeBytes,
            )
        }
    }

    private fun latestSnapshotSources(userId: UUID): List<SnapshotSource> =
        store.listDeviceSnapshots(userId)
            .groupBy { it.deviceId }
            .mapNotNull { (_, items) ->
                val latest = items.maxByOrNull { it.createdAt } ?: return@mapNotNull null
                val path = paths.deviceDir(
                    userId,
                    UUID.fromString(latest.deviceId),
                ).resolve(latest.fileName)
                if (!Files.isRegularFile(path)) {
                    return@mapNotNull null
                }
                SnapshotSource(
                    entryName = "device-snapshots/${latest.deviceId}/${latest.fileName}",
                    path = path,
                    expectedSha256 = latest.encryptedSha256,
                )
            }

    private fun pruneArchives(userId: UUID) {
        val archives = store.listArchives(userId)
        val toDelete = RetentionPolicy.selectForDeletion(
            archives = archives,
            now = Instant.now(clock),
            recent = properties.retentionRecent,
            weekly = properties.retentionWeekly,
            monthly = properties.retentionMonthly,
        )
        toDelete.forEach { archive ->
            try {
                store.deleteArchive(userId, archive)
            } catch (exception: Exception) {
                log.warn("Failed to delete archive {}", archive.id, exception)
            }
        }
    }

    private fun pruneDeviceSnapshots(userId: UUID, deviceId: UUID) {
        val snapshots = store.listDeviceSnapshots(userId)
            .filter { it.deviceId == deviceId.toString() }
            .sortedByDescending { it.createdAt }
        snapshots.drop(properties.deviceRetention.coerceAtLeast(1)).forEach { snapshot ->
            runCatching { store.deleteDeviceSnapshot(snapshot) }
                .onFailure { log.warn("Failed to delete device snapshot {}", snapshot.id, it) }
        }
    }

    private fun requireConfigured() {
        val configuration = config.check()
        if (!configuration.configured) {
            throw ApiException(
                HttpStatus.SERVICE_UNAVAILABLE,
                "BACKUP_NOT_CONFIGURED",
                configuration.error ?: "Резервное копирование не настроено",
            )
        }
    }

    private fun <T> withUserLock(userId: UUID, block: () -> T): T {
        val lockPath = paths.lockFile(userId)
        FileChannel.open(
            lockPath,
            StandardOpenOption.CREATE,
            StandardOpenOption.WRITE,
        ).use { channel ->
            val lock: FileLock = channel.tryLock()
                ?: throw ApiException(
                    HttpStatus.CONFLICT,
                    "BACKUP_RUNNING",
                    "Резервное копирование уже выполняется",
                )
            return try {
                block()
            } finally {
                lock.release()
            }
        }
    }

    private fun validateSqliteHeader(path: Path) {
        val header = Files.newInputStream(path).use { it.readNBytes(16) }
        val expected = "SQLite format 3\u0000".toByteArray(Charsets.US_ASCII)
        if (!header.contentEquals(expected)) {
            throw ApiException.validation("Файл не является снимком SQLite")
        }
    }

    private fun moveAtomically(source: Path, target: Path) {
        try {
            Files.move(
                source,
                target,
                StandardCopyOption.REPLACE_EXISTING,
                StandardCopyOption.ATOMIC_MOVE,
            )
        } catch (_: Exception) {
            Files.move(source, target, StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private fun deleteRecursively(path: Path) {
        if (!Files.exists(path)) {
            return
        }
        Files.walk(path).sorted(Comparator.reverseOrder()).use { stream ->
            stream.forEach { Files.deleteIfExists(it) }
        }
    }

    private fun safeMessage(exception: Exception): String {
        val message = exception.message ?: "Неизвестная ошибка"
        return message.lineSequence().first().take(1_000)
    }

    private data class AttachmentRow(
        val userId: UUID,
        val storageKey: String,
        val sha256: String,
        val sizeBytes: Long,
    )
}
