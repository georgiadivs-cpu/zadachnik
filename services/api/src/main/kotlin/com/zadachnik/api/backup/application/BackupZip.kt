package com.zadachnik.api.backup.application

import org.springframework.stereotype.Component

import com.fasterxml.jackson.databind.ObjectMapper
import com.zadachnik.api.backup.domain.BACKUP_FORMAT_VERSION
import com.zadachnik.api.backup.domain.BackupManifest
import com.zadachnik.api.backup.domain.ManifestFile
import java.io.BufferedOutputStream
import java.nio.file.Files
import java.nio.file.Path
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

data class AttachmentSource(
    val entryName: String,
    val path: Path,
    val expectedSha256: String,
    val expectedSize: Long,
)

data class SnapshotSource(
    val entryName: String,
    val path: Path,
    val expectedSha256: String,
)

@Component
class BackupZip(private val objectMapper: ObjectMapper) {

    fun write(
        destination: Path,
        dump: Path,
        dumpSha256: String,
        schemaVersion: String?,
        counts: Map<String, Long>,
        createdAt: java.time.Instant,
        attachments: List<AttachmentSource>,
        deviceSnapshots: List<SnapshotSource>,
    ) {
        val manifestFiles = mutableListOf<ManifestFile>()
        val snapshotFiles = mutableListOf<ManifestFile>()

        ZipOutputStream(BufferedOutputStream(Files.newOutputStream(destination))).use { zip ->
            addFile(zip, "database.dump", dump, dumpSha256, null)

            attachments.forEach { source ->
                val meta = addFile(
                    zip,
                    source.entryName,
                    source.path,
                    source.expectedSha256,
                    source.expectedSize,
                )
                manifestFiles += meta
            }
            deviceSnapshots.forEach { source ->
                val meta = addFile(
                    zip,
                    source.entryName,
                    source.path,
                    source.expectedSha256,
                    null,
                )
                snapshotFiles += meta
            }

            val manifest = BackupManifest(
                formatVersion = BACKUP_FORMAT_VERSION,
                createdAt = createdAt,
                schemaVersion = schemaVersion,
                databaseDump = "database.dump",
                databaseSha256 = dumpSha256,
                counts = counts,
                attachments = manifestFiles,
                deviceSnapshots = snapshotFiles,
            )
            val bytes = objectMapper.writerWithDefaultPrettyPrinter()
                .writeValueAsBytes(manifest)
            val entry = ZipEntry("manifest.json")
            zip.putNextEntry(entry)
            zip.write(bytes)
            zip.closeEntry()
        }
    }

    fun readManifest(zipPath: Path): BackupManifest {
        ZipFile(zipPath.toFile()).use { zip ->
            val entry = zip.getEntry("manifest.json")
                ?: throw IllegalStateException("В архиве нет manifest.json")
            return zip.getInputStream(entry).use {
                objectMapper.readValue(it, BackupManifest::class.java)
            }
        }
    }

    fun verify(
        zipPath: Path,
        workDir: Path,
        pgRestore: String,
        runner: CommandRunner,
        timeout: java.time.Duration,
    ): BackupManifest {
        val manifest = readManifest(zipPath)
        if (manifest.formatVersion != BACKUP_FORMAT_VERSION) {
            throw IllegalStateException("Неподдерживаемая версия формата архива")
        }
        ZipFile(zipPath.toFile()).use { zip ->
            verifyFiles(zip, manifest.attachments)
            verifyFiles(zip, manifest.deviceSnapshots)
            val dumpEntry = zip.getEntry(manifest.databaseDump)
                ?: throw IllegalStateException("В архиве нет дампа БД")
            val dumpFile = workDir.resolve("verify-database.dump")
            zip.getInputStream(dumpEntry).use { input ->
                Files.newOutputStream(dumpFile).use { output ->
                    val (_, sha) = BackupHashing.copyAndHash(input, output)
                    if (sha != manifest.databaseSha256) {
                        throw IllegalStateException("SHA-256 дампа БД не совпадает")
                    }
                }
            }
            val result = runner.run(
                listOf(pgRestore, "--list", dumpFile.toString()),
                timeout = timeout,
            )
            if (result.exitCode != 0) {
                throw IllegalStateException(
                    "pg_restore не смог прочитать дамп: ${result.output.take(1_000)}",
                )
            }
            Files.deleteIfExists(dumpFile)
        }
        return manifest
    }

    private fun verifyFiles(zip: ZipFile, files: List<ManifestFile>) {
        files.forEach { file ->
            val entry = zip.getEntry(file.path)
                ?: throw IllegalStateException("В архиве нет файла ${file.path}")
            if (entry.size >= 0 && entry.size != file.sizeBytes) {
                throw IllegalStateException("Размер ${file.path} не совпадает")
            }
            zip.getInputStream(entry).use { input ->
                val digest = java.security.MessageDigest.getInstance("SHA-256")
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                var total = 0L
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    digest.update(buffer, 0, read)
                    total += read
                }
                if (total != file.sizeBytes) {
                    throw IllegalStateException("Размер ${file.path} не совпадает")
                }
                val sha = digest.digest().joinToString("") { "%02x".format(it) }
                if (!sha.equals(file.sha256, ignoreCase = true)) {
                    throw IllegalStateException("SHA-256 ${file.path} не совпадает")
                }
            }
        }
    }

    private fun addFile(
        zip: ZipOutputStream,
        entryName: String,
        source: Path,
        expectedSha256: String?,
        expectedSize: Long?,
    ): ManifestFile {
        if (!Files.isRegularFile(source)) {
            throw IllegalStateException("Файл для архива не найден: $entryName")
        }
        val entry = ZipEntry(entryName)
        zip.putNextEntry(entry)
        val (size, sha) = Files.newInputStream(source).use { input ->
            BackupHashing.copyAndHash(input, zip)
        }
        zip.closeEntry()
        if (expectedSize != null && size != expectedSize) {
            throw IllegalStateException("Размер $entryName изменился во время backup")
        }
        if (expectedSha256 != null && !sha.equals(expectedSha256, ignoreCase = true)) {
            throw IllegalStateException("SHA-256 $entryName не совпадает")
        }
        return ManifestFile(
            path = entryName,
            sizeBytes = size,
            sha256 = sha,
        )
    }
}
