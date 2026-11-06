package com.zadachnik.api.backup.application

import java.net.URI
import org.springframework.boot.autoconfigure.jdbc.JdbcConnectionDetails
import org.springframework.stereotype.Component

data class PostgresConnection(
    val host: String,
    val port: Int,
    val database: String,
    val user: String,
    val password: String,
) {
    fun environment(): Map<String, String> = mapOf(
        "PGHOST" to host,
        "PGPORT" to port.toString(),
        "PGDATABASE" to database,
        "PGUSER" to user,
        "PGPASSWORD" to password,
        "PGCONNECT_TIMEOUT" to "10",
    )
}

@Component
class PostgresConnectionFactory(
    private val details: JdbcConnectionDetails,
) {

    fun current(): PostgresConnection {
        val raw = details.jdbcUrl.removePrefix("jdbc:postgresql:")
        val uri = runCatching { URI(raw) }.getOrElse {
            throw IllegalStateException("Некорректный DATABASE_URL")
        }
        val host = uri.host ?: throw IllegalStateException("В DATABASE_URL нет хоста")
        val database = uri.path?.removePrefix("/")?.takeIf { it.isNotBlank() }
            ?: throw IllegalStateException("В DATABASE_URL нет имени БД")
        val port = if (uri.port > 0) uri.port else 5432
        return PostgresConnection(
            host = host,
            port = port,
            database = database,
            user = details.username,
            password = details.password,
        )
    }
}
