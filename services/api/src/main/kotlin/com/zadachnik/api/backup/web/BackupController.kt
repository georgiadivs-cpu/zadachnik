package com.zadachnik.api.backup.web

import com.zadachnik.api.backup.application.BackupJobService
import com.zadachnik.api.backup.application.BackupService
import com.zadachnik.api.backup.domain.BackupArchive
import com.zadachnik.api.backup.domain.BackupStatus
import com.zadachnik.api.backup.domain.DeviceSnapshot
import com.zadachnik.api.backup.domain.DeviceSnapshotUpload
import com.zadachnik.api.common.ApiException
import java.nio.charset.StandardCharsets
import java.util.UUID
import org.springframework.core.io.FileSystemResource
import org.springframework.http.ContentDisposition
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RequestPart
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.multipart.MultipartFile

@RestController
@RequestMapping("/api/v1/backups")
class BackupController(
    private val service: BackupService,
    private val jobs: BackupJobService,
) {

    @GetMapping("/status")
    fun status(authentication: Authentication): BackupStatus =
        service.status(userId(authentication))

    @GetMapping
    fun list(authentication: Authentication): BackupStatus =
        service.status(userId(authentication))

    @PostMapping
    fun start(authentication: Authentication): ResponseEntity<BackupStatus> {
        val userId = userId(authentication)
        jobs.start(userId)
        return ResponseEntity.status(HttpStatus.ACCEPTED)
            .body(service.status(userId))
    }

    @PostMapping("/{id}/verify")
    fun verify(
        authentication: Authentication,
        @PathVariable id: String,
    ): BackupArchive = jobs.verify(userId(authentication), id)

    @GetMapping("/{id}/download")
    fun download(
        authentication: Authentication,
        @PathVariable id: String,
    ): ResponseEntity<FileSystemResource> {
        val file = service.download(userId(authentication), id)
        val disposition = ContentDisposition.attachment()
            .filename(file.fileName, StandardCharsets.UTF_8)
            .build()
        return ResponseEntity.ok()
            .contentType(MediaType.APPLICATION_OCTET_STREAM)
            .header(HttpHeaders.CONTENT_DISPOSITION, disposition.toString())
            .body(FileSystemResource(file.path))
    }

    @PostMapping("/devices", consumes = [MediaType.MULTIPART_FORM_DATA_VALUE])
    fun uploadDeviceSnapshot(
        authentication: Authentication,
        @RequestParam sha256: String,
        @RequestParam schemaVersion: Int,
        @RequestPart("file") file: MultipartFile,
    ): DeviceSnapshot {
        if (file.isEmpty) {
            throw ApiException.validation("Снимок пуст")
        }
        val userId = userId(authentication)
        val deviceId = deviceId(authentication)
        return service.uploadDeviceSnapshot(
            DeviceSnapshotUpload(
                userId = userId,
                deviceId = deviceId,
                schemaVersion = schemaVersion,
                declaredSha256 = sha256,
                input = file.inputStream,
            ),
        )
    }

    private fun userId(authentication: Authentication): UUID =
        UUID.fromString(authentication.name)

    private fun deviceId(authentication: Authentication): UUID =
        authentication.details?.toString()?.let(UUID::fromString)
            ?: throw ApiException.unauthenticated("Устройство не определено")
}
