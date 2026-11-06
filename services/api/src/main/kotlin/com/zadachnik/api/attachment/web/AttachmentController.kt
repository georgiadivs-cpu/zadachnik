package com.zadachnik.api.attachment.web

import com.zadachnik.api.attachment.application.AttachmentService
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
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RequestPart
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.multipart.MultipartFile

@RestController
@RequestMapping("/api/v1/attachments")
class AttachmentController(private val attachments: AttachmentService) {

    @PostMapping("/{id}", consumes = [MediaType.MULTIPART_FORM_DATA_VALUE])
    fun upload(
        authentication: Authentication,
        @PathVariable id: UUID,
        @RequestParam ownerType: String,
        @RequestParam ownerId: UUID,
        @RequestPart("file") file: MultipartFile,
    ): AttachmentResponse {
        if (file.isEmpty) {
            throw ApiException.validation("Файл пуст")
        }
        val userId = UUID.fromString(authentication.name)
        val deviceId = deviceId(authentication)
        val fileName = file.originalFilename
            ?: throw ApiException.validation("Имя файла обязательно")
        val snapshot = attachments.upload(
            userId = userId,
            deviceId = deviceId,
            attachmentId = id,
            ownerType = ownerType,
            ownerId = ownerId,
            fileName = fileName,
            declaredMime = file.contentType,
            input = file.inputStream,
        )
        return AttachmentResponse.from(snapshot)
    }

    @GetMapping("/{id}")
    fun download(
        authentication: Authentication,
        @PathVariable id: UUID,
    ): ResponseEntity<FileSystemResource> {
        val userId = UUID.fromString(authentication.name)
        val file = attachments.download(userId, id)
        val disposition = ContentDisposition.attachment()
            .filename(file.fileName, StandardCharsets.UTF_8)
            .build()
        return ResponseEntity.ok()
            .contentType(MediaType.parseMediaType(file.mimeType))
            .header(HttpHeaders.CONTENT_DISPOSITION, disposition.toString())
            .contentLength(file.snapshot.sizeBytes)
            .body(FileSystemResource(file.path))
    }

    @DeleteMapping("/{id}")
    fun delete(
        authentication: Authentication,
        @PathVariable id: UUID,
    ): ResponseEntity<Void> {
        attachments.delete(
            userId = UUID.fromString(authentication.name),
            deviceId = deviceId(authentication),
            attachmentId = id,
        )
        return ResponseEntity.status(HttpStatus.NO_CONTENT).build()
    }

    private fun deviceId(authentication: Authentication): UUID =
        authentication.details?.toString()?.let(UUID::fromString)
            ?: throw ApiException.unauthenticated("Устройство не определено")
}
