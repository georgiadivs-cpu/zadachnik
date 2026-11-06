package com.zadachnik.api

import com.fasterxml.jackson.databind.ObjectMapper
import com.zadachnik.api.backup.domain.BackupStatus
import com.zadachnik.api.backup.domain.DeviceSnapshot
import com.zadachnik.api.identity.web.AuthResponse
import com.zadachnik.api.sync.web.PushResponse
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.sql.DriverManager
import java.time.Instant
import java.util.UUID
import java.util.zip.ZipFile
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
    properties = [
        "app.security.setup-token=test-setup-token",
        "app.backups.min-free-bytes=0",
        "app.backups.process-timeout=10m",
    ],
)
class BackupsIntegrationTest {

    companion object {
        private const val SETUP_TOKEN = "test-setup-token"
        private const val PASSWORD = "correct-horse-battery"

        @JvmStatic
        private val attachmentsDir: Path = Files.createTempDirectory("zadachnik-backup-attachments")
        @JvmStatic
        private val backupDir: Path = Files.createTempDirectory("zadachnik-backup-data")
        @JvmStatic
        private val keyDir: Path = Files.createTempDirectory("zadachnik-backup-key")
        @JvmStatic
        private val identity: Path = keyDir.resolve("backup.key")
        @JvmStatic
        private val ageKeygen: String = locate("age-keygen")
        @JvmStatic
        private val age: String = locate("age")
        @JvmStatic
        private val pgDump: String = locate("pg_dump")
        @JvmStatic
        private val pgRestore: String = locate("pg_restore")
        @JvmStatic
        private val recipient: String

        init {
            val generated = ProcessBuilder(ageKeygen, "-o", identity.toString()).start()
            check(generated.waitFor() == 0) { "age-keygen failed" }
            Files.setPosixFilePermissions(
                identity,
                setOf(
                    java.nio.file.attribute.PosixFilePermission.OWNER_READ,
                    java.nio.file.attribute.PosixFilePermission.OWNER_WRITE,
                ),
            )
            recipient = ProcessBuilder(ageKeygen, "-y", identity.toString())
                .start()
                .inputStream
                .bufferedReader()
                .readText()
                .lineSequence()
                .map { it.trim() }
                .first { it.startsWith("age1") }
        }

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
            registry.add("app.security.jwt.secret") { "test-secret-backups-0123456789-abcd" }
            registry.add("app.attachments.dir") { attachmentsDir.toString() }
            registry.add("app.backups.dir") { backupDir.toString() }
            registry.add("app.backups.age-identity") { identity.toString() }
            registry.add("app.backups.age-recipient") { recipient }
            registry.add("app.backups.age-binary") { age }
            registry.add("app.backups.age-keygen-binary") { ageKeygen }
            registry.add("app.backups.pg-dump") { pgDump }
            registry.add("app.backups.pg-restore") { pgRestore }
        }

        private fun locate(command: String): String {
            val env = System.getenv("BACKUP_" + command.uppercase().replace('-', '_'))
            if (!env.isNullOrBlank()) {
                return env
            }
            val candidates = listOf(
                "/opt/homebrew/opt/postgresql@16/bin/$command",
                "/usr/local/opt/postgresql@16/bin/$command",
                "/opt/homebrew/opt/libpq/bin/$command",
                "/usr/local/opt/libpq/bin/$command",
                "/opt/homebrew/bin/$command",
                "/usr/local/bin/$command",
            )
            candidates.firstOrNull { Files.isExecutable(Path.of(it)) }?.let { return it }
            return command
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
        clearDirectory(backupDir)
        clearDirectory(attachmentsDir)
        Files.createDirectories(attachmentsDir.resolve("tmp"))
    }

    @Test
    fun `server backup is encrypted, verified and restorable`() {
        val owner = setup()
        val noteId = createNote(owner)
        uploadAttachment(owner, noteId, UUID.randomUUID())

        val started = exchange(
            "/api/v1/backups",
            HttpMethod.POST,
            token = owner.accessToken,
        )
        assertThat(started.statusCode).isEqualTo(HttpStatus.ACCEPTED)

        val status = waitForBackup(owner.accessToken)
        assertThat(status.configured).isTrue()
        assertThat(status.state.lastError).isNull()
        assertThat(status.archives).hasSize(1)
        assertThat(status.archives.single().status).isEqualTo("VERIFIED")
        assertThat(status.archives.single().counts["notes"]).isEqualTo(1)
        assertThat(status.archives.single().counts["attachments"]).isEqualTo(1)

        val archive = backupDir.resolve(owner.userId.toString())
            .resolve("archives")
            .resolve(status.archives.single().fileName)
        assertThat(Files.isRegularFile(archive)).isTrue()
        assertThat(Files.readAllBytes(archive).take(20).toByteArray().toString(Charsets.US_ASCII))
            .startsWith("age-encryption.org")

        val restoreZip = keyDir.resolve("restore-${UUID.randomUUID()}.zip")
        val decrypted = ProcessBuilder(
            age,
            "--decrypt",
            "--identity",
            identity.toString(),
            "--output",
            restoreZip.toString(),
            archive.toString(),
        ).start()
        assertThat(decrypted.waitFor()).isZero()

        ZipFile(restoreZip.toFile()).use { zip ->
            assertThat(zip.getEntry("manifest.json")).isNotNull()
            assertThat(zip.getEntry("database.dump")).isNotNull()
            assertThat(zip.getEntry("attachments/${owner.userId}/$noteId")).isNull()
        }

        val restoreDatabase = "restore_${UUID.randomUUID().toString().replace("-", "").take(12)}"
        createDatabase(restoreDatabase)
        try {
            val dump = keyDir.resolve("database.dump")
            ZipFile(restoreZip.toFile()).use { zip ->
                zip.getInputStream(zip.getEntry("database.dump")).use { input ->
                    Files.newOutputStream(dump).use { output -> input.copyTo(output) }
                }
            }
            val restored = ProcessBuilder(
                pgRestore,
                "--no-owner",
                "--no-privileges",
                "--dbname",
                restoreDatabase,
                dump.toString(),
            ).apply {
                environment()["PGHOST"] = postgres.host
                environment()["PGPORT"] = postgres.getMappedPort(5432).toString()
                environment()["PGUSER"] = postgres.username
                environment()["PGPASSWORD"] = postgres.password
            }.redirectErrorStream(true).start()
            val restoredOutput = restored.inputStream.bufferedReader().readText()
            assertThat(restored.waitFor())
                .withFailMessage("pg_restore failed: $restoredOutput")
                .isZero()

            val restoredNotes = DriverManager.getConnection(
                postgres.jdbcUrl.replace("/zadachnik", "/$restoreDatabase"),
                postgres.username,
                postgres.password,
            ).use { connection ->
                connection.createStatement().use { statement ->
                    statement.executeQuery("select count(*) from notes").use { rows ->
                        rows.next()
                        rows.getInt(1)
                    }
                }
            }
            assertThat(restoredNotes).isEqualTo(1)
        } finally {
            dropDatabase(restoreDatabase)
        }
    }

    @Test
    fun `device snapshot is encrypted and idempotent`() {
        val owner = setup()
        val bytes = sqliteBytes()
        val sha = sha256(bytes)

        val first = uploadSnapshot(owner, bytes, sha)
        assertThat(first.statusCode).isEqualTo(HttpStatus.OK)
        assertThat(first.body!!.sha256).isEqualTo(sha)

        val second = uploadSnapshot(owner, bytes, sha)
        assertThat(second.statusCode).isEqualTo(HttpStatus.OK)
        assertThat(second.body!!.id).isEqualTo(first.body!!.id)

        val status = getStatus(owner.accessToken)
        assertThat(status.devices).hasSize(1)
        assertThat(status.devices.single().snapshotCount).isEqualTo(1)
        val snapshotDir = backupDir.resolve(owner.userId.toString())
            .resolve("devices")
            .resolve(owner.deviceId.toString())
        val files = Files.list(snapshotDir).use { stream ->
            stream.filter { it.fileName.toString().endsWith(".db.age") }.toList()
        }
        assertThat(files).hasSize(1)
        assertThat(Files.readAllBytes(files.single()).take(20).toByteArray().toString(Charsets.US_ASCII))
            .startsWith("age-encryption.org")
    }

    @Test
    fun `backup status requires authentication`() {
        val response = restTemplate.exchange(
            "/api/v1/backups/status",
            HttpMethod.GET,
            HttpEntity<Void>(HttpHeaders()),
            String::class.java,
        )
        assertThat(response.statusCode).isEqualTo(HttpStatus.UNAUTHORIZED)
    }

    private fun waitForBackup(token: String): BackupStatus {
        val deadline = System.nanoTime() + 90_000_000_000L
        var last: BackupStatus? = null
        while (System.nanoTime() < deadline) {
            last = getStatus(token)
            if (!last.state.running) {
                return last
            }
            Thread.sleep(250)
        }
        error("Backup did not finish: ${last?.state}")
    }

    private fun getStatus(token: String): BackupStatus {
        val response = restTemplate.exchange(
            "/api/v1/backups/status",
            HttpMethod.GET,
            HttpEntity<Void>(bearer(token)),
            BackupStatus::class.java,
        )
        assertThat(response.statusCode).isEqualTo(HttpStatus.OK)
        return response.body!!
    }

    private fun uploadSnapshot(
        owner: AuthResponse,
        bytes: ByteArray,
        sha: String,
    ): org.springframework.http.ResponseEntity<DeviceSnapshot> {
        val resource = object : ByteArrayResource(bytes) {
            override fun getFilename(): String = "snapshot.db"
        }
        val headers = bearer(owner.accessToken)
        headers.contentType = MediaType.MULTIPART_FORM_DATA
        val body = LinkedMultiValueMap<String, Any>()
        body.add("sha256", sha)
        body.add("schemaVersion", "6")
        body.add("file", HttpEntity(resource, HttpHeaders()))
        return restTemplate.postForEntity(
            "/api/v1/backups/devices",
            HttpEntity(body, headers),
            DeviceSnapshot::class.java,
        )
    }

    private fun setup(): AuthResponse {
        val body = mapOf(
            "email" to "backups-${UUID.randomUUID()}@example.com",
            "password" to PASSWORD,
            "device" to mapOf(
                "id" to UUID.randomUUID().toString(),
                "name" to "Backup device",
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

    private fun uploadAttachment(owner: AuthResponse, noteId: UUID, attachmentId: UUID) {
        val resource = object : ByteArrayResource(pngBytes()) {
            override fun getFilename(): String = "photo.png"
        }
        val headers = bearer(owner.accessToken)
        headers.contentType = MediaType.MULTIPART_FORM_DATA
        val fileHeaders = HttpHeaders().apply { contentType = MediaType.IMAGE_PNG }
        val body = LinkedMultiValueMap<String, Any>()
        body.add("ownerType", "NOTE")
        body.add("ownerId", noteId.toString())
        body.add("file", HttpEntity(resource, fileHeaders))
        val response = restTemplate.postForEntity(
            "/api/v1/attachments/$attachmentId",
            HttpEntity(body, headers),
            String::class.java,
        )
        assertThat(response.statusCode).isEqualTo(HttpStatus.OK)
    }

    private fun createDatabase(name: String) {
        DriverManager.getConnection(
            postgres.jdbcUrl.replace("/zadachnik", "/postgres"),
            postgres.username,
            postgres.password,
        ).use { connection ->
            connection.createStatement().use { it.execute("create database $name") }
        }
    }

    private fun dropDatabase(name: String) {
        DriverManager.getConnection(
            postgres.jdbcUrl.replace("/zadachnik", "/postgres"),
            postgres.username,
            postgres.password,
        ).use { connection ->
            connection.createStatement().use { it.execute("drop database if exists $name") }
        }
    }

    private fun clearDirectory(path: Path) {
        if (!Files.exists(path)) return
        Files.walk(path).sorted(Comparator.reverseOrder()).use { stream ->
            stream.filter { it != path }.forEach { Files.deleteIfExists(it) }
        }
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }

    private fun sqliteBytes(): ByteArray {
        val header = "SQLite format 3\u0000".toByteArray(Charsets.US_ASCII)
        return header + ByteArray(256)
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

    private data class Response(val statusCode: HttpStatus, val body: String)
}
