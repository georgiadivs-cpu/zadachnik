package com.zadachnik.api

import com.fasterxml.jackson.databind.ObjectMapper
import com.zadachnik.api.attachment.web.AttachmentResponse
import com.zadachnik.api.identity.web.AuthResponse
import com.zadachnik.api.sync.web.PullResponse
import com.zadachnik.api.sync.web.PushResponse
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.util.UUID
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.client.TestRestTemplate
import org.springframework.boot.testcontainers.service.connection.ServiceConnection
import org.springframework.core.io.ByteArrayResource
import org.springframework.http.HttpEntity
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpMethod
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.springframework.util.LinkedMultiValueMap
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers

@Testcontainers
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    properties = ["app.security.setup-token=test-setup-token"],
)
class AttachmentsIntegrationTest {

    companion object {
        private const val SETUP_TOKEN = "test-setup-token"
        private const val PASSWORD = "correct-horse-battery"

        @JvmStatic
        private val attachmentsDir: Path =
            Files.createTempDirectory("zadachnik-attachments-test")

        @Container
        @ServiceConnection
        @JvmStatic
        val postgres: PostgreSQLContainer<*> = PostgreSQLContainer("postgres:16-alpine")
            .withDatabaseName("zadachnik")
            .withUsername("zadachnik")
            .withPassword("zadachnik")

        @JvmStatic
        @DynamicPropertySource
        fun properties(registry: DynamicPropertyRegistry) {
            registry.add("app.security.jwt.secret") { "test-secret-attachments-0123456789-ab" }
            registry.add("app.attachments.dir") { attachmentsDir.toString() }
        }
    }

    @Autowired
    private lateinit var restTemplate: TestRestTemplate

    @Autowired
    private lateinit var objectMapper: ObjectMapper

    @Autowired
    private lateinit var jdbc: JdbcClient

    @BeforeEach
    fun cleanDatabase() {
        jdbc.sql("truncate table users cascade").update()
    }

    @Test
    fun `upload and download attachment`() {
        val owner = setup()
        val noteId = createNote(owner)
        val attachmentId = UUID.randomUUID()
        val bytes = pngBytes()

        val response = upload(owner, attachmentId, noteId, "photo.png", bytes)

        assertThat(response.statusCode).isEqualTo(HttpStatus.OK)
        val attachment = response.body!!
        assertThat(attachment.fileName).isEqualTo("photo.png")
        assertThat(attachment.mimeType).isEqualTo("image/png")
        assertThat(attachment.sizeBytes).isEqualTo(bytes.size.toLong())
        assertThat(attachment.sha256).hasSize(64)

        val download = restTemplate.exchange(
            "/api/v1/attachments/$attachmentId",
            HttpMethod.GET,
            HttpEntity<Void>(bearer(owner.accessToken)),
            ByteArray::class.java,
        )
        assertThat(download.statusCode).isEqualTo(HttpStatus.OK)
        assertThat(download.body).isEqualTo(bytes)

        val pull = pull(owner.accessToken)
        assertThat(pull.changes.map { it.entityType }).contains("ATTACHMENT")
    }

    @Test
    fun `duplicate upload is idempotent`() {
        val owner = setup()
        val noteId = createNote(owner)
        val attachmentId = UUID.randomUUID()
        val bytes = pngBytes()

        val first = upload(owner, attachmentId, noteId, "photo.png", bytes)
        val second = upload(owner, attachmentId, noteId, "photo.png", bytes)

        assertThat(first.statusCode).isEqualTo(HttpStatus.OK)
        assertThat(second.statusCode).isEqualTo(HttpStatus.OK)
        assertThat(second.body!!.revision).isEqualTo(first.body!!.revision)
        val count = jdbc.sql(
            "select count(*) from change_log where user_id = :userId and entity_type = 'ATTACHMENT'",
        ).param("userId", owner.userId).query(Int::class.java).single()
        assertThat(count).isEqualTo(1)
    }

    @Test
    fun `delete creates tombstone and removes file`() {
        val owner = setup()
        val noteId = createNote(owner)
        val attachmentId = UUID.randomUUID()
        upload(owner, attachmentId, noteId, "photo.png", pngBytes())

        val deleted = restTemplate.exchange(
            "/api/v1/attachments/$attachmentId",
            HttpMethod.DELETE,
            HttpEntity<Void>(bearer(owner.accessToken)),
            Void::class.java,
        )
        assertThat(deleted.statusCode).isEqualTo(HttpStatus.NO_CONTENT)

        val download = restTemplate.exchange(
            "/api/v1/attachments/$attachmentId",
            HttpMethod.GET,
            HttpEntity<Void>(bearer(owner.accessToken)),
            ByteArray::class.java,
        )
        assertThat(download.statusCode).isEqualTo(HttpStatus.NOT_FOUND)

        val pull = pull(owner.accessToken)
        val tombstone = pull.changes.last { it.entityType == "ATTACHMENT" }
        assertThat(tombstone.payload["deletedAt"]).isNotNull()
    }

    @Test
    fun `unsupported file type is rejected`() {
        val owner = setup()
        val noteId = createNote(owner)
        val response = uploadRaw(
            owner,
            UUID.randomUUID(),
            noteId,
            "archive.zip",
            byteArrayOf(0x50, 0x4B, 0x03, 0x04),
        )

        assertThat(response.statusCode).isEqualTo(HttpStatus.BAD_REQUEST)
    }

    private fun setup(): AuthResponse {
        val body = mapOf(
            "email" to "attachments-${UUID.randomUUID()}@example.com",
            "password" to PASSWORD,
            "device" to mapOf(
                "id" to UUID.randomUUID().toString(),
                "name" to "Attachments device",
                "platform" to "MACOS",
            ),
        )
        val response = exchange(
            "/api/v1/auth/setup",
            HttpMethod.POST,
            body = body,
            setupToken = SETUP_TOKEN,
        )
        assertThat(response.statusCode).isEqualTo(HttpStatus.CREATED)
        return objectMapper.readValue(response.body, AuthResponse::class.java)
    }

    private fun createNote(owner: AuthResponse): UUID {
        val noteId = UUID.randomUUID()
        val operation = mapOf(
            "operationId" to UUID.randomUUID().toString(),
            "deviceId" to owner.deviceId.toString(),
            "entityType" to "NOTE",
            "entityId" to noteId.toString(),
            "operationType" to "CREATE",
            "clientTimestamp" to Instant.now().toString(),
            "payload" to mapOf(
                "title" to "Заметка",
                "contentMarkdown" to "Текст",
                "categoryId" to "personal",
            ),
        )
        val response = exchange(
            "/api/v1/sync/push",
            HttpMethod.POST,
            token = owner.accessToken,
            body = mapOf("operations" to listOf(operation)),
        )
        assertThat(response.statusCode).isEqualTo(HttpStatus.OK)
        val push = objectMapper.readValue(response.body, PushResponse::class.java)
        assertThat(push.results.single().revision).isEqualTo(1)
        return noteId
    }

    private fun upload(
        owner: AuthResponse,
        attachmentId: UUID,
        noteId: UUID,
        fileName: String,
        bytes: ByteArray,
    ): org.springframework.http.ResponseEntity<AttachmentResponse> {
        val resource = object : ByteArrayResource(bytes) {
            override fun getFilename(): String = fileName
        }
        val headers = bearer(owner.accessToken)
        headers.contentType = MediaType.MULTIPART_FORM_DATA
        val fileHeaders = HttpHeaders()
        fileHeaders.contentType = MediaType.IMAGE_PNG
        val fileEntity = HttpEntity(resource, fileHeaders)
        val body = LinkedMultiValueMap<String, Any>()
        body.add("ownerType", "NOTE")
        body.add("ownerId", noteId.toString())
        body.add("file", fileEntity)
        return restTemplate.postForEntity(
            "/api/v1/attachments/$attachmentId",
            HttpEntity(body, headers),
            AttachmentResponse::class.java,
        )
    }

    private fun uploadRaw(
        owner: AuthResponse,
        attachmentId: UUID,
        noteId: UUID,
        fileName: String,
        bytes: ByteArray,
    ): org.springframework.http.ResponseEntity<String> {
        val resource = object : ByteArrayResource(bytes) {
            override fun getFilename(): String = fileName
        }
        val headers = bearer(owner.accessToken)
        headers.contentType = MediaType.MULTIPART_FORM_DATA
        val fileHeaders = HttpHeaders()
        fileHeaders.contentType = MediaType.IMAGE_PNG
        val body = LinkedMultiValueMap<String, Any>()
        body.add("ownerType", "NOTE")
        body.add("ownerId", noteId.toString())
        body.add("file", HttpEntity(resource, fileHeaders))
        return restTemplate.postForEntity(
            "/api/v1/attachments/$attachmentId",
            HttpEntity(body, headers),
            String::class.java,
        )
    }

    private fun pull(token: String): PullResponse {
        val response = exchange(
            "/api/v1/sync/pull?cursor=0&limit=200",
            HttpMethod.GET,
            token = token,
        )
        assertThat(response.statusCode).isEqualTo(HttpStatus.OK)
        return objectMapper.readValue(response.body, PullResponse::class.java)
    }

    private fun bearer(token: String): HttpHeaders = HttpHeaders().apply {
        setBearerAuth(token)
    }

    private fun exchange(
        path: String,
        method: HttpMethod,
        token: String? = null,
        setupToken: String? = null,
        body: Any? = null,
    ): Response {
        val headers = HttpHeaders().apply {
            contentType = MediaType.APPLICATION_JSON
            if (token != null) setBearerAuth(token)
            if (setupToken != null) set("X-Setup-Token", setupToken)
        }
        val response = restTemplate.exchange(
            path,
            method,
            HttpEntity(body, headers),
            String::class.java,
        )
        return Response(
            HttpStatus.resolve(response.statusCode.value()) ?: error("Unknown status"),
            response.body ?: "",
        )
    }

    private fun pngBytes(): ByteArray = byteArrayOf(
        0x89.toByte(),
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
    )

    private data class Response(val statusCode: HttpStatus, val body: String)
}
