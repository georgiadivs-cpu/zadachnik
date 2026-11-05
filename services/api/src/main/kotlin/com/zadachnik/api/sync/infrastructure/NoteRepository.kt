package com.zadachnik.api.sync.infrastructure

import com.zadachnik.api.sync.domain.NoteSnapshot
import java.sql.Types
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository

@Repository
class NoteRepository(private val jdbc: JdbcClient) {

    fun find(userId: UUID, id: UUID): NoteSnapshot? =
        jdbc.sql("$SELECT where id = :id and user_id = :userId")
            .param("id", id)
            .param("userId", userId)
            .query { rs, _ -> map(rs) }
            .optional()
            .orElse(null)

    fun findForUpdate(userId: UUID, id: UUID): NoteSnapshot? =
        jdbc.sql("$SELECT where id = :id and user_id = :userId for update")
            .param("id", id)
            .param("userId", userId)
            .query { rs, _ -> map(rs) }
            .optional()
            .orElse(null)

    fun categoryExists(categoryId: String): Boolean =
        jdbc.sql("select exists(select 1 from categories where id = :id)")
            .param("id", categoryId)
            .query(Boolean::class.java)
            .single()

    fun create(
        userId: UUID,
        id: UUID,
        title: String,
        contentMarkdown: String,
        categoryId: String?,
        now: Instant,
    ): NoteSnapshot {
        jdbc.sql(
            """
            insert into notes
                (id, user_id, title, content_markdown, category_id, revision, created_at, updated_at)
            values (:id, :userId, :title, :content, :categoryId, 1, :now, :now)
            """,
        )
            .param("id", id)
            .param("userId", userId)
            .param("title", title)
            .param("content", contentMarkdown)
            .param("categoryId", categoryId, Types.VARCHAR)
            .param("now", now.atOffset(ZoneOffset.UTC))
            .update()

        return find(userId, id) ?: error("Note was not created")
    }

    fun update(
        userId: UUID,
        id: UUID,
        title: String,
        contentMarkdown: String,
        categoryId: String?,
        baseRevision: Long,
        now: Instant,
    ): NoteSnapshot? {
        val updated = jdbc.sql(
            """
            update notes
            set title = :title,
                content_markdown = :content,
                category_id = :categoryId,
                revision = revision + 1,
                updated_at = :now
            where id = :id and user_id = :userId
              and revision = :baseRevision and deleted_at is null
            """,
        )
            .param("title", title)
            .param("content", contentMarkdown)
            .param("categoryId", categoryId, Types.VARCHAR)
            .param("now", now.atOffset(ZoneOffset.UTC))
            .param("id", id)
            .param("userId", userId)
            .param("baseRevision", baseRevision)
            .update()

        return if (updated == 0) null else find(userId, id)
    }

    fun softDelete(userId: UUID, id: UUID, baseRevision: Long, now: Instant): NoteSnapshot? {
        val updated = jdbc.sql(
            """
            update notes
            set deleted_at = :now,
                revision = revision + 1,
                updated_at = :now
            where id = :id and user_id = :userId
              and revision = :baseRevision and deleted_at is null
            """,
        )
            .param("now", now.atOffset(ZoneOffset.UTC))
            .param("id", id)
            .param("userId", userId)
            .param("baseRevision", baseRevision)
            .update()

        return if (updated == 0) null else find(userId, id)
    }

    private fun map(rs: java.sql.ResultSet): NoteSnapshot = NoteSnapshot(
        id = rs.getObject("id", UUID::class.java),
        userId = rs.getObject("user_id", UUID::class.java),
        title = rs.getString("title"),
        contentMarkdown = rs.getString("content_markdown"),
        categoryId = rs.getString("category_id"),
        revision = rs.getLong("revision"),
        createdAt = rs.getObject("created_at", OffsetDateTime::class.java).toInstant(),
        updatedAt = rs.getObject("updated_at", OffsetDateTime::class.java).toInstant(),
        deletedAt = rs.getObject("deleted_at", OffsetDateTime::class.java)?.toInstant(),
    )

    companion object {
        private const val SELECT = """
            select id, user_id, title, content_markdown, category_id,
                   revision, created_at, updated_at, deleted_at
            from notes
        """
    }
}
