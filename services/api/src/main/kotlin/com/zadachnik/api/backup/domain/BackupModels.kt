package com.zadachnik.api.backup.domain

import com.fasterxml.jackson.annotation.JsonIgnore
import java.time.Instant
import java.util.UUID

const val BACKUP_FORMAT_VERSION = 1

data class ManifestFile(
    val path: String,
    val sizeBytes: Long,
    val sha256: String,
)

data class BackupManifest(
    val formatVersion: Int = BACKUP_FORMAT_VERSION,
    val createdAt: Instant,
    val schemaVersion: String?,
    val databaseDump: String,
    val databaseSha256: String,
    val counts: Map<String, Long>,
    val attachments: List<ManifestFile>,
    val deviceSnapshots: List<ManifestFile>,
)

data class BackupArchive(
    val id: String,
    val fileName: String,
    val createdAt: Instant,
    val finishedAt: Instant,
    val sizeBytes: Long,
    val sha256: String,
    val status: String,
    val verifiedAt: Instant? = null,
    val schemaVersion: String? = null,
    val counts: Map<String, Long> = emptyMap(),
    val error: String? = null,
) {
    @get:JsonIgnore
    val verified: Boolean get() = status == STATUS_VERIFIED && verifiedAt != null

    companion object {
        const val STATUS_SUCCESS = "SUCCESS"
        const val STATUS_VERIFIED = "VERIFIED"
    }
}

data class DeviceSnapshot(
    val id: String,
    val userId: String,
    val deviceId: String,
    val fileName: String,
    val createdAt: Instant,
    val sizeBytes: Long,
    val sha256: String,
    val encryptedSha256: String,
    val schemaVersion: Int,
    val verifiedAt: Instant? = null,
)

data class BackupState(
    val running: Boolean = false,
    val operation: String? = null,
    val startedAt: Instant? = null,
    val lastAttemptAt: Instant? = null,
    val lastSuccessAt: Instant? = null,
    val lastVerifiedAt: Instant? = null,
    val lastError: String? = null,
)

data class BackupDiskInfo(
    val freeBytes: Long,
    val totalBytes: Long,
)

data class BackupDeviceInfo(
    val deviceId: String,
    val latest: DeviceSnapshot,
    val snapshotCount: Int,
)

data class BackupStatus(
    val configured: Boolean,
    val configError: String?,
    val state: BackupState,
    val archives: List<BackupArchive>,
    val devices: List<BackupDeviceInfo>,
    val disk: BackupDiskInfo,
    val retention: RetentionDescription,
)

data class RetentionDescription(
    val recent: Int,
    val weekly: Int,
    val monthly: Int,
    val deviceSnapshots: Int,
)

data class BackupDownload(
    val path: java.nio.file.Path,
    val fileName: String,
)

data class DeviceSnapshotUpload(
    val userId: UUID,
    val deviceId: UUID,
    val schemaVersion: Int,
    val declaredSha256: String,
    val input: java.io.InputStream,
)
