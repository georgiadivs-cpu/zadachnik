package com.zadachnik.api

import com.fasterxml.jackson.databind.ObjectMapper
import com.zadachnik.api.identity.web.AuthResponse
import com.zadachnik.api.sync.domain.DefaultLanes
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
class SyncTasksIntegrationTest {

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
            registry.add("app.security.jwt.secret") { "test-secret-for-tasks-0123456789-abcd" }
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
    fun `setup creates four default lanes`() {
        val owner = setup()

        val count = jdbc.sql("select count(*) from board_lanes where user_id = :userId")
            .param("userId", owner.userId)
            .query(Int::class.java)
            .single()

        assertThat(count).isEqualTo(4)
    }

    @Test
    fun `custom lane create, update and duplicate are idempotent`() {
        val owner = setup()
        val laneId = UUID.randomUUID()
        val create = laneOperation(owner.deviceId, laneId, "CREATE", null, "Идеи", 4)

        val first = push(owner.accessToken, create)
        assertThat(first.results.single().status).isEqualTo(PushStatus.APPLIED)
        assertThat(first.results.single().revision).isEqualTo(1)

        val duplicate = push(owner.accessToken, create)
        assertThat(duplicate.results.single().status).isEqualTo(PushStatus.DUPLICATE)

        val update = laneOperation(owner.deviceId, laneId, "UPDATE", 1, "Идеи и планы", 4)
        val updated = push(owner.accessToken, update)
        assertThat(updated.results.single().status).isEqualTo(PushStatus.APPLIED)
        assertThat(updated.results.single().revision).isEqualTo(2)

        val pull = pull(owner.accessToken, "0")
        assertThat(pull.changes).hasSize(2)
        assertThat(pull.changes.last().entityType).isEqualTo("LANE")
        assertThat(pull.changes.last().payload["name"]).isEqualTo("Идеи и планы")
    }

    @Test
    fun `task can be created, moved and cancelled`() {
        val owner = setup()
        val taskId = UUID.randomUUID()
        val create = taskOperation(
            deviceId = owner.deviceId,
            taskId = taskId,
            operationType = "CREATE",
            baseRevision = null,
            laneId = DefaultLanes.NEW,
            title = "Подготовить план",
        )

        val created = push(owner.accessToken, create)
        assertThat(created.results.single().status).isEqualTo(PushStatus.APPLIED)
        assertThat(created.results.single().revision).isEqualTo(1)

        val duplicate = push(owner.accessToken, create)
        assertThat(duplicate.results.single().status).isEqualTo(PushStatus.DUPLICATE)

        val moved = push(
            owner.accessToken,
            taskOperation(
                deviceId = owner.deviceId,
                taskId = taskId,
                operationType = "UPDATE",
                baseRevision = 1,
                laneId = DefaultLanes.IN_PROGRESS,
                title = "Подготовить план",
            ),
        )
        assertThat(moved.results.single().status).isEqualTo(PushStatus.APPLIED)
        assertThat(moved.results.single().revision).isEqualTo(2)

        val cancelled = push(
            owner.accessToken,
            taskOperation(
                deviceId = owner.deviceId,
                taskId = taskId,
                operationType = "UPDATE",
                baseRevision = 2,
                laneId = DefaultLanes.IN_PROGRESS,
                title = "Подготовить план",
                systemState = "CANCELLED",
            ),
        )
        assertThat(cancelled.results.single().status).isEqualTo(PushStatus.APPLIED)
        assertThat(cancelled.results.single().revision).isEqualTo(3)

        val pull = pull(owner.accessToken, "0")
        assertThat(pull.changes).hasSize(3)
        assertThat(pull.changes.last().payload["systemState"]).isEqualTo("CANCELLED")
        assertThat(pull.changes.last().payload["laneId"]).isEqualTo(DefaultLanes.IN_PROGRESS.toString())
    }

    @Test
    fun `stale task update returns server version`() {
        val owner = setup()
        val taskId = UUID.randomUUID()
        push(
            owner.accessToken,
            taskOperation(
                deviceId = owner.deviceId,
                taskId = taskId,
                operationType = "CREATE",
                baseRevision = null,
                laneId = DefaultLanes.NEW,
                title = "Задача",
            ),
        )
        push(
            owner.accessToken,
            taskOperation(
                deviceId = owner.deviceId,
                taskId = taskId,
                operationType = "UPDATE",
                baseRevision = 1,
                laneId = DefaultLanes.REVIEW,
                title = "Обновлённая",
            ),
        )

        val stale = push(
            owner.accessToken,
            taskOperation(
                deviceId = owner.deviceId,
                taskId = taskId,
                operationType = "UPDATE",
                baseRevision = 1,
                laneId = DefaultLanes.DONE,
                title = "Устаревшая",
            ),
        )

        assertThat(stale.results.single().status).isEqualTo(PushStatus.CONFLICT)
        assertThat(stale.results.single().revision).isEqualTo(2)
        assertThat(stale.results.single().serverEntity?.get("title")).isEqualTo("Обновлённая")
        assertThat(stale.results.single().serverEntity?.get("laneId"))
            .isEqualTo(DefaultLanes.REVIEW.toString())
    }

    @Test
    fun `lane with tasks cannot be deleted but empty custom lane can`() {
        val owner = setup()
        val taskId = UUID.randomUUID()
        push(
            owner.accessToken,
            taskOperation(
                deviceId = owner.deviceId,
                taskId = taskId,
                operationType = "CREATE",
                baseRevision = null,
                laneId = DefaultLanes.NEW,
                title = "Задача",
            ),
        )

        val blocked = push(
            owner.accessToken,
            laneOperation(owner.deviceId, DefaultLanes.NEW, "DELETE", 1, null, null),
        )
        assertThat(blocked.results.single().status).isEqualTo(PushStatus.REJECTED)
        assertThat(blocked.results.single().code).isEqualTo("LANE_NOT_EMPTY")

        val laneId = UUID.randomUUID()
        push(owner.accessToken, laneOperation(owner.deviceId, laneId, "CREATE", null, "Временная", 4))
        val deleted = push(
            owner.accessToken,
            laneOperation(owner.deviceId, laneId, "DELETE", 1, null, null),
        )
        assertThat(deleted.results.single().status).isEqualTo(PushStatus.APPLIED)
        assertThat(deleted.results.single().revision).isEqualTo(2)

        val pull = pull(owner.accessToken, "0")
        assertThat(pull.changes.last().operationType.name).isEqualTo("DELETE")
        assertThat(pull.changes.last().payload["deletedAt"]).isNotNull()
    }

    @Test
    fun `reminder can be created, updated and deleted`() {
        val owner = setup()
        val taskId = UUID.randomUUID()
        push(
            owner.accessToken,
            taskOperation(
                deviceId = owner.deviceId,
                taskId = taskId,
                operationType = "CREATE",
                baseRevision = null,
                laneId = DefaultLanes.NEW,
                title = "Задача с напоминанием",
            ),
        )

        val reminderId = UUID.randomUUID()
        val create = reminderOperation(
            owner.deviceId,
            reminderId,
            "CREATE",
            null,
            taskId,
            "2026-11-06T14:00:00Z",
        )
        val created = push(owner.accessToken, create)
        assertThat(created.results.single().status).isEqualTo(PushStatus.APPLIED)
        assertThat(created.results.single().revision).isEqualTo(1)

        val duplicate = push(owner.accessToken, create)
        assertThat(duplicate.results.single().status).isEqualTo(PushStatus.DUPLICATE)

        val update = reminderOperation(
            owner.deviceId,
            reminderId,
            "UPDATE",
            1,
            taskId,
            "2026-11-06T15:30:00Z",
        )
        val updated = push(owner.accessToken, update)
        assertThat(updated.results.single().status).isEqualTo(PushStatus.APPLIED)
        assertThat(updated.results.single().revision).isEqualTo(2)

        val pull = pull(owner.accessToken, "0")
        assertThat(pull.changes).hasSize(3)
        assertThat(pull.changes.last().entityType).isEqualTo("REMINDER")
        assertThat(pull.changes.last().payload["remindAt"])
            .isEqualTo("2026-11-06T15:30:00Z")

        val deleted = push(
            owner.accessToken,
            reminderOperation(
                owner.deviceId,
                reminderId,
                "DELETE",
                2,
                taskId,
                null,
            ),
        )
        assertThat(deleted.results.single().status).isEqualTo(PushStatus.APPLIED)
        assertThat(deleted.results.single().revision).isEqualTo(3)

        val afterDelete = pull(owner.accessToken, "0")
        assertThat(afterDelete.changes.last().payload["deletedAt"]).isNotNull()
    }

    @Test
    fun `second active reminder for task is rejected`() {
        val owner = setup()
        val taskId = UUID.randomUUID()
        push(
            owner.accessToken,
            taskOperation(
                deviceId = owner.deviceId,
                taskId = taskId,
                operationType = "CREATE",
                baseRevision = null,
                laneId = DefaultLanes.NEW,
                title = "Задача",
            ),
        )
        push(
            owner.accessToken,
            reminderOperation(
                owner.deviceId,
                UUID.randomUUID(),
                "CREATE",
                null,
                taskId,
                "2026-11-06T14:00:00Z",
            ),
        )

        val second = push(
            owner.accessToken,
            reminderOperation(
                owner.deviceId,
                UUID.randomUUID(),
                "CREATE",
                null,
                taskId,
                "2026-11-06T15:00:00Z",
            ),
        )

        assertThat(second.results.single().status).isEqualTo(PushStatus.REJECTED)
        assertThat(second.results.single().code).isEqualTo("REMINDER_EXISTS")
    }

    @Test
    fun `reminder for missing task is rejected`() {
        val owner = setup()
        val response = push(
            owner.accessToken,
            reminderOperation(
                owner.deviceId,
                UUID.randomUUID(),
                "CREATE",
                null,
                UUID.randomUUID(),
                "2026-11-06T14:00:00Z",
            ),
        )

        assertThat(response.results.single().status).isEqualTo(PushStatus.REJECTED)
        assertThat(response.results.single().code).isEqualTo("TASK_NOT_FOUND")
    }

    @Test
    fun `task pull returns lane before dependent task`() {
        val owner = setup()
        val laneId = UUID.randomUUID()
        val taskId = UUID.randomUUID()

        push(
            owner.accessToken,
            laneOperation(owner.deviceId, laneId, "CREATE", null, "Новая дорожка", 4),
            taskOperation(
                deviceId = owner.deviceId,
                taskId = taskId,
                operationType = "CREATE",
                baseRevision = null,
                laneId = laneId,
                title = "Задача в новой дорожке",
            ),
        )

        val pull = pull(owner.accessToken, "0")

        assertThat(pull.changes).hasSize(2)
        assertThat(pull.changes[0].entityType).isEqualTo("LANE")
        assertThat(pull.changes[1].entityType).isEqualTo("TASK")
    }

    private fun setup(): AuthResponse {
        val body = mapOf(
            "email" to "tasks-${UUID.randomUUID()}@example.com",
            "password" to PASSWORD,
            "device" to mapOf(
                "id" to UUID.randomUUID().toString(),
                "name" to "Tasks device",
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

    private fun laneOperation(
        deviceId: UUID,
        laneId: UUID,
        operationType: String,
        baseRevision: Long?,
        name: String?,
        sortOrder: Int?,
    ): Map<String, Any?> = buildMap {
        put("operationId", UUID.randomUUID().toString())
        put("deviceId", deviceId.toString())
        put("entityType", "LANE")
        put("entityId", laneId.toString())
        put("operationType", operationType)
        if (baseRevision != null) put("baseRevision", baseRevision)
        put("clientTimestamp", Instant.now().toString())
        if (operationType != "DELETE") {
            put("payload", mapOf("name" to name, "sortOrder" to sortOrder))
        }
    }

    private fun taskOperation(
        deviceId: UUID,
        taskId: UUID,
        operationType: String,
        baseRevision: Long?,
        laneId: UUID,
        title: String,
        systemState: String = "ACTIVE",
    ): Map<String, Any?> = buildMap {
        put("operationId", UUID.randomUUID().toString())
        put("deviceId", deviceId.toString())
        put("entityType", "TASK")
        put("entityId", taskId.toString())
        put("operationType", operationType)
        if (baseRevision != null) put("baseRevision", baseRevision)
        put("clientTimestamp", Instant.now().toString())
        if (operationType != "DELETE") {
            put(
                "payload",
                mapOf(
                    "title" to title,
                    "description" to "Описание",
                    "laneId" to laneId.toString(),
                    "systemState" to systemState,
                    "categoryId" to "work",
                    "priority" to "HIGH",
                    "plannedStartAt" to "2026-11-06T09:00:00Z",
                    "plannedEndAt" to "2026-11-08T18:00:00Z",
                    "actualStartAt" to "2026-11-06T10:00:00Z",
                    "actualEndAt" to null,
                ),
            )
        }
    }

    private fun reminderOperation(
        deviceId: UUID,
        reminderId: UUID,
        operationType: String,
        baseRevision: Long?,
        taskId: UUID,
        remindAt: String?,
    ): Map<String, Any?> = buildMap {
        put("operationId", UUID.randomUUID().toString())
        put("deviceId", deviceId.toString())
        put("entityType", "REMINDER")
        put("entityId", reminderId.toString())
        put("operationType", operationType)
        if (baseRevision != null) put("baseRevision", baseRevision)
        put("clientTimestamp", Instant.now().toString())
        if (operationType != "DELETE") {
            put("payload", mapOf("taskId" to taskId.toString(), "remindAt" to remindAt))
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

    private fun pull(token: String, cursor: String, limit: Int = 200): PullResponse {
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
