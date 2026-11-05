package com.zadachnik.api

import com.fasterxml.jackson.databind.ObjectMapper
import com.zadachnik.api.identity.web.AuthResponse
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
class IdentityIntegrationTest {

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
            registry.add("app.security.jwt.secret") { "test-secret-for-identity-0123456789" }
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
    fun `setup rejects wrong token when no owner exists`() {
        val response = exchange(
            path = "/api/v1/auth/setup",
            method = HttpMethod.POST,
            setupToken = "wrong-token",
            body = authBody(uniqueEmail(), UUID.randomUUID()),
        )

        assertThat(response.statusCode).isEqualTo(HttpStatus.UNAUTHORIZED)
        assertThat(response.body).contains("SETUP_TOKEN_INVALID")
    }

    @Test
    fun `setup rejects short password`() {
        val response = exchange(
            path = "/api/v1/auth/setup",
            method = HttpMethod.POST,
            setupToken = SETUP_TOKEN,
            body = mapOf(
                "email" to uniqueEmail(),
                "password" to "short",
                "device" to mapOf(
                    "id" to UUID.randomUUID().toString(),
                    "name" to "Integration device",
                    "platform" to "MACOS",
                ),
            ),
        )

        assertThat(response.statusCode).isEqualTo(HttpStatus.BAD_REQUEST)
        assertThat(response.body).contains("VALIDATION_ERROR")
    }

    @Test
    fun `setup creates owner only once`() {
        val first = setup()
        val second = exchange(
            path = "/api/v1/auth/setup",
            method = HttpMethod.POST,
            setupToken = SETUP_TOKEN,
            body = authBody(uniqueEmail(), UUID.randomUUID()),
        )

        assertThat(first.userId).isNotNull()
        assertThat(second.statusCode).isEqualTo(HttpStatus.CONFLICT)
        assertThat(second.body).contains("SETUP_ALREADY_COMPLETED")
    }

    @Test
    fun `login returns tokens and devices require access token`() {
        val email = uniqueEmail()
        val owner = setup(email = email)
        val login = login(email, owner.deviceId)

        assertThat(login.accessToken).isNotBlank()
        assertThat(login.refreshToken).isNotBlank()

        val unauthorized = exchange("/api/v1/devices", HttpMethod.GET)
        assertThat(unauthorized.statusCode).isEqualTo(HttpStatus.UNAUTHORIZED)

        val devices = exchange("/api/v1/devices", HttpMethod.GET, token = login.accessToken)
        assertThat(devices.statusCode).isEqualTo(HttpStatus.OK)
        assertThat(devices.body).contains(login.deviceId.toString())
    }

    @Test
    fun `refresh rotates token and reusing old token revokes device`() {
        val owner = setup()
        val refreshed = refresh(owner.refreshToken)
        assertThat(refreshed.refreshToken).isNotEqualTo(owner.refreshToken)

        val reuse = exchange(
            path = "/api/v1/auth/refresh",
            method = HttpMethod.POST,
            body = mapOf("refreshToken" to owner.refreshToken),
        )
        assertThat(reuse.statusCode).isEqualTo(HttpStatus.UNAUTHORIZED)
        assertThat(reuse.body).contains("REFRESH_TOKEN_INVALID")

        val afterRevoke = exchange("/api/v1/devices", HttpMethod.GET, token = owner.accessToken)
        assertThat(afterRevoke.statusCode).isEqualTo(HttpStatus.UNAUTHORIZED)
    }

    @Test
    fun `logout revokes refresh token`() {
        val owner = setup()

        val logout = exchange(
            path = "/api/v1/auth/logout",
            method = HttpMethod.POST,
            body = mapOf("refreshToken" to owner.refreshToken),
        )
        assertThat(logout.statusCode).isEqualTo(HttpStatus.NO_CONTENT)

        val refresh = exchange(
            path = "/api/v1/auth/refresh",
            method = HttpMethod.POST,
            body = mapOf("refreshToken" to owner.refreshToken),
        )
        assertThat(refresh.statusCode).isEqualTo(HttpStatus.UNAUTHORIZED)
    }

    @Test
    fun `revoking device invalidates its access token`() {
        val owner = setup()

        val revoke = exchange(
            path = "/api/v1/devices/${owner.deviceId}",
            method = HttpMethod.DELETE,
            token = owner.accessToken,
        )
        assertThat(revoke.statusCode).isEqualTo(HttpStatus.NO_CONTENT)

        val afterRevoke = exchange("/api/v1/devices", HttpMethod.GET, token = owner.accessToken)
        assertThat(afterRevoke.statusCode).isEqualTo(HttpStatus.UNAUTHORIZED)
    }

    @Test
    fun `wrong password and unknown user return unauthorized`() {
        setup()

        val wrong = exchange(
            path = "/api/v1/auth/login",
            method = HttpMethod.POST,
            body = authBody("unused@example.com", UUID.randomUUID()),
        )
        assertThat(wrong.statusCode).isEqualTo(HttpStatus.UNAUTHORIZED)

        val unknown = exchange(
            path = "/api/v1/auth/login",
            method = HttpMethod.POST,
            body = authBody(uniqueEmail(), UUID.randomUUID()),
        )
        assertThat(unknown.statusCode).isEqualTo(HttpStatus.UNAUTHORIZED)
    }

    private fun setup(
        email: String = uniqueEmail(),
        deviceId: UUID = UUID.randomUUID(),
    ): AuthResponse {
        val response = exchange(
            path = "/api/v1/auth/setup",
            method = HttpMethod.POST,
            setupToken = SETUP_TOKEN,
            body = authBody(email, deviceId),
        )
        assertThat(response.statusCode).isEqualTo(HttpStatus.CREATED)
        return objectMapper.readValue(response.body, AuthResponse::class.java)
    }

    private fun login(email: String, deviceId: UUID): AuthResponse {
        val response = exchange(
            path = "/api/v1/auth/login",
            method = HttpMethod.POST,
            body = authBody(email, deviceId),
        )
        assertThat(response.statusCode).isEqualTo(HttpStatus.OK)
        return objectMapper.readValue(response.body, AuthResponse::class.java)
    }

    private fun refresh(refreshToken: String): AuthResponse {
        val response = exchange(
            path = "/api/v1/auth/refresh",
            method = HttpMethod.POST,
            body = mapOf("refreshToken" to refreshToken),
        )
        assertThat(response.statusCode).isEqualTo(HttpStatus.OK)
        return objectMapper.readValue(response.body, AuthResponse::class.java)
    }

    private fun authBody(email: String, deviceId: UUID): Map<String, Any> = mapOf(
        "email" to email,
        "password" to PASSWORD,
        "device" to mapOf(
            "id" to deviceId.toString(),
            "name" to "Integration device",
            "platform" to "MACOS",
        ),
    )

    private fun uniqueEmail(): String = "owner-${UUID.randomUUID()}@example.com"

    private fun exchange(
        path: String,
        method: HttpMethod,
        token: String? = null,
        setupToken: String? = null,
        body: Any? = null,
    ): Response {
        val headers = HttpHeaders().apply {
            contentType = MediaType.APPLICATION_JSON
            if (token != null) {
                setBearerAuth(token)
            }
            if (setupToken != null) {
                set("X-Setup-Token", setupToken)
            }
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

    private data class Response(val statusCode: HttpStatus, val body: String)
}
