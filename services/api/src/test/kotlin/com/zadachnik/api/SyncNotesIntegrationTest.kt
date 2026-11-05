package com.zadachnik.api

import com.fasterxml.jackson.databind.ObjectMapper
import com.zadachnik.api.identity.web.AuthResponse
import com.zadachnik.api.sync.domain.PushStatus
import com.zadachnik.api.sync.web.PullResponse
import com.zadachnik.api.sync.web.PushResponse
import java.time.Instant
import java.util.UUID
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.client.TestRestTemplate
import org.springframework.boot.testcontainers.service.connection.ServiceConnection
import org.springframework.http.HttpEntity
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpMethod
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers

@Testcontainers
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    properties = ["app.security.setup-token=test-setup-token"],
)
class SyncNotesIntegrationTest {

    companion object {
        private const val SETUP_TOKEN = "test-setup-token"
        private const val PASSWORD = "correct-horse-battery"

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
            registry.add("app.security.jwt.secret") { "test-secret-for-sync-0123456789-abcdef" }
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
    fun `create note is applied and duplicate is not applied twice`() {
        val owner = setup()
        val noteId = UUID.randomUUID()
        val operation = createOperation(owner.deviceId, noteId)

        val first = push(owner.accessToken, operation)
        assertThat(first.results.single().status).isEqualTo(PushStatus.APPLIED)
        assertThat(first.results.single().revision).isEqualTo(1)
        assertThat(first.results.single().changeSeq).isNotNull()

        val duplicate = push(owner.accessToken, operation)
        assertThat(duplicate.results.single().status).isEqualTo(PushStatus.DUPLICATE)
        assertThat(duplicate.results.single().changeSeq).isEqualTo(first.results.single().changeSeq)

        val pull = pull(owner.accessToken, cursor = "0")
        assertThat(pull.changes).hasSize(1)
        assertThat(pull.changes.single().operationType.name).isEqualTo("CREATE")
        assertThat(pull.changes.single().payload["title"]).isEqualTo("Заметка")
    }

    @Test
    fun `note can be created without category`() {
        val owner = setup()
        val noteId = UUID.randomUUID()
        val operation = createOperation(owner.deviceId, noteId).toMutableMap()
        operation["payload"] = mapOf(
            "title" to "Без категории",
            "contentMarkdown" to "",
        )

        val response = push(owner.accessToken, operation)

        assertThat(response.results.single().status).isEqualTo(PushStatus.APPLIED)
        val pull = pull(owner.accessToken, cursor = "0")
        assertThat(pull.changes.single().payload["categoryId"]).isNull()
    }

    @Test
    fun `same operation id with different body is rejected`() {
        val owner = setup()
        val noteId = UUID.randomUUID()
        val original = createOperation(owner.deviceId, noteId)
        push(owner.accessToken, original)

        val changed = original.toMutableMap()
        changed["payload"] = mapOf(
            "title" to "Другое тело",
            "contentMarkdown" to "Другой текст",
            "categoryId" to "personal",
        )

        val response = push(owner.accessToken, changed)

        assertThat(response.results.single().status).isEqualTo(PushStatus.REJECTED)
        assertThat(response.results.single().code).isEqualTo("OPERATION_ID_CONFLICT")
    }

    @Test
    fun `stale update returns conflict without overwriting server note`() {
        val owner = setup()
        val noteId = UUID.randomUUID()
        push(owner.accessToken, createOperation(owner.deviceId, noteId))

        val update = updateOperation(owner.deviceId, noteId, baseRevision = 1, title = "Обновлённая")
        val applied = push(owner.accessToken, update)
        assertThat(applied.results.single().status).isEqualTo(PushStatus.APPLIED)
        assertThat(applied.results.single().revision).isEqualTo(2)

        val stale = push(
            owner.accessToken,
            updateOperation(owner.deviceId, noteId, baseRevision = 1, title = "Устаревшая"),
        )
        assertThat(stale.results.single().status).isEqualTo(PushStatus.CONFLICT)
        assertThat(stale.results.single().serverEntity?.title).isEqualTo("Обновлённая")
        assertThat(stale.results.single().revision).isEqualTo(2)
    }

    @Test
    fun `delete creates tombstone and stale delete conflicts`() {
        val owner = setup()
        val noteId = UUID.randomUUID()
        push(owner.accessToken, createOperation(owner.deviceId, noteId))

        val deleted = push(owner.accessToken, deleteOperation(owner.deviceId, noteId, baseRevision = 1))
        assertThat(deleted.results.single().status).isEqualTo(PushStatus.APPLIED)
        assertThat(deleted.results.single().revision).isEqualTo(2)

        val pull = pull(owner.accessToken, cursor = "0")
        assertThat(pull.changes).hasSize(2)
        assertThat(pull.changes.last().operationType.name).isEqualTo("DELETE")
        assertThat(pull.changes.last().payload["deletedAt"]).isNotNull()

        val stale = push(owner.accessToken, deleteOperation(owner.deviceId, noteId, baseRevision = 1))
        assertThat(stale.results.single().status).isEqualTo(PushStatus.CONFLICT)
        assertThat(stale.results.single().serverEntity?.deletedAt).isNotNull()
    }

    @Test
    fun `batch reports applied and rejected operations independently`() {
        val owner = setup()
        val noteId = UUID.randomUUID()
        val valid = createOperation(owner.deviceId, noteId)
        val invalid = createOperation(
            deviceId = owner.deviceId,
            noteId = UUID.randomUUID(),
            title = "",
        )

        val response = push(owner.accessToken, valid, invalid)

        assertThat(response.results[0].status).isEqualTo(PushStatus.APPLIED)
        assertThat(response.results[1].status).isEqualTo(PushStatus.REJECTED)
        assertThat(response.results[1].code).isEqualTo("VALIDATION_ERROR")

        val pull = pull(owner.accessToken, cursor = "0")
        assertThat(pull.changes).hasSize(1)
    }

    @Test
    fun `pull paginates changes and returns stable cursor`() {
        val owner = setup()
        repeat(3) { index ->
            push(owner.accessToken, createOperation(owner.deviceId, UUID.randomUUID(), title = "Заметка $index"))
        }

        val first = pull(owner.accessToken, cursor = "0", limit = 1)
        assertThat(first.changes).hasSize(1)
        assertThat(first.hasMore).isTrue()
        assertThat(first.nextCursor).isNotEqualTo("0")

        val second = pull(owner.accessToken, cursor = first.nextCursor, limit = 1)
        assertThat(second.changes).hasSize(1)
        assertThat(second.changes.single().seq).isGreaterThan(first.changes.single().seq)

        val third = pull(owner.accessToken, cursor = second.nextCursor, limit = 1)
        assertThat(third.changes).hasSize(1)
        assertThat(third.hasMore).isFalse()

        val empty = pull(owner.accessToken, cursor = third.nextCursor, limit = 1)
        assertThat(empty.changes).isEmpty()
        assertThat(empty.hasMore).isFalse()
        assertThat(empty.nextCursor).isEqualTo(third.nextCursor)
    }

    @Test
    fun `unsupported entity and foreign device are rejected`() {
        val owner = setup()
        val noteId = UUID.randomUUID()
        val unsupported = createOperation(owner.deviceId, noteId).toMutableMap().apply {
            this["entityType"] = "TASK"
        }
        val foreign = createOperation(UUID.randomUUID(), UUID.randomUUID())

        val response = push(owner.accessToken, unsupported, foreign)

        assertThat(response.results[0].status).isEqualTo(PushStatus.REJECTED)
        assertThat(response.results[0].code).isEqualTo("UNSUPPORTED_ENTITY")
        assertThat(response.results[1].status).isEqualTo(PushStatus.REJECTED)
        assertThat(response.results[1].code).isEqualTo("DEVICE_MISMATCH")
    }

    private fun setup(): AuthResponse {
        val body = mapOf(
            "email" to "sync-${UUID.randomUUID()}@example.com",
            "password" to PASSWORD,
            "device" to mapOf(
                "id" to UUID.randomUUID().toString(),
                "name" to "Sync device",
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

    private fun createOperation(
        deviceId: UUID,
        noteId: UUID,
        title: String = "Заметка",
    ): Map<String, Any?> = operation(
        deviceId = deviceId,
        noteId = noteId,
        operationType = "CREATE",
        baseRevision = null,
        title = title,
    )

    private fun updateOperation(
        deviceId: UUID,
        noteId: UUID,
        baseRevision: Long,
        title: String,
    ): Map<String, Any?> = operation(
        deviceId = deviceId,
        noteId = noteId,
        operationType = "UPDATE",
        baseRevision = baseRevision,
        title = title,
    )

    private fun deleteOperation(
        deviceId: UUID,
        noteId: UUID,
        baseRevision: Long,
    ): Map<String, Any?> = mapOf(
        "operationId" to UUID.randomUUID().toString(),
        "deviceId" to deviceId.toString(),
        "entityType" to "NOTE",
        "entityId" to noteId.toString(),
        "operationType" to "DELETE",
        "baseRevision" to baseRevision,
        "clientTimestamp" to Instant.now().toString(),
    )

    private fun operation(
        deviceId: UUID,
        noteId: UUID,
        operationType: String,
        baseRevision: Long?,
        title: String,
    ): Map<String, Any?> = buildMap {
        put("operationId", UUID.randomUUID().toString())
        put("deviceId", deviceId.toString())
        put("entityType", "NOTE")
        put("entityId", noteId.toString())
        put("operationType", operationType)
        if (baseRevision != null) put("baseRevision", baseRevision)
        put("clientTimestamp", Instant.now().toString())
        if (operationType != "DELETE") {
            put(
                "payload",
                mapOf(
                    "title" to title,
                    "contentMarkdown" to "Текст заметки",
                    "categoryId" to "personal",
                ),
            )
        }
    }

    private fun push(token: String, vararg operations: Map<String, Any?>): PushResponse {
        val response = exchange(
            "/api/v1/sync/push",
            HttpMethod.POST,
            token = token,
            body = mapOf("operations" to operations.toList()),
        )
        assertThat(response.statusCode).isEqualTo(HttpStatus.OK)
        return objectMapper.readValue(response.body, PushResponse::class.java)
    }

    private fun pull(
        token: String,
        cursor: String,
        limit: Int = 200,
    ): PullResponse {
        val response = exchange(
            "/api/v1/sync/pull?cursor=$cursor&limit=$limit",
            HttpMethod.GET,
            token = token,
        )
        assertThat(response.statusCode).isEqualTo(HttpStatus.OK)
        return objectMapper.readValue(response.body, PullResponse::class.java)
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
        val response = restTemplate.exchange(path, method, HttpEntity(body, headers), String::class.java)
        return Response(
            HttpStatus.resolve(response.statusCode.value()) ?: error("Unknown status"),
            response.body ?: "",
        )
    }

    private data class Response(val statusCode: HttpStatus, val body: String)
}
