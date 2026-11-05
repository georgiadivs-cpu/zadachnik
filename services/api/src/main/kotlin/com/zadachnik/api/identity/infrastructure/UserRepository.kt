package com.zadachnik.api.identity.infrastructure

import com.zadachnik.api.identity.domain.UserRecord
import com.zadachnik.api.identity.domain.UserStatus
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository

@Repository
class UserRepository(private val jdbc: JdbcClient) {

    fun count(): Long = jdbc.sql("select count(*) from users").query(Long::class.java).single()

    fun findById(id: UUID): UserRecord? =
        jdbc.sql("select id, email, password_hash, status from users where id = :id")
            .param("id", id)
            .query { rs, _ ->
                UserRecord(
                    id = rs.getObject("id", UUID::class.java),
                    email = rs.getString("email"),
                    passwordHash = rs.getString("password_hash"),
                    status = UserStatus.valueOf(rs.getString("status")),
                )
            }
            .optional()
            .orElse(null)

    fun findByEmail(email: String): UserRecord? =
        jdbc.sql("select id, email, password_hash, status from users where email = :email")
            .param("email", email)
            .query { rs, _ ->
                UserRecord(
                    id = rs.getObject("id", UUID::class.java),
                    email = rs.getString("email"),
                    passwordHash = rs.getString("password_hash"),
                    status = UserStatus.valueOf(rs.getString("status")),
                )
            }
            .optional()
            .orElse(null)

    fun insert(id: UUID, email: String, passwordHash: String, now: Instant) {
        jdbc.sql(
            """
            insert into users (id, email, password_hash, status, created_at, updated_at)
            values (:id, :email, :passwordHash, 'ACTIVE', :now, :now)
            """,
        )
            .param("id", id)
            .param("email", email)
            .param("passwordHash", passwordHash)
            .param("now", now.atOffset(ZoneOffset.UTC))
            .update()
    }
}
