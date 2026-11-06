package com.zadachnik.api.sync.infrastructure

import com.zadachnik.api.sync.domain.ReminderSnapshot
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository

@Repository
class ReminderRepository(private val jdbc: JdbcClient) {

    fun find(userId: UUID, id: UUID): ReminderSnapshot? =
        jdbc.sql("$SELECT where user_id = :userId and id = :id")
            .param("userId", userId)
            .param("id", id)
            .query { rs, _ -> map(rs) }
            .optional()
            .orElse(null)

    fun findForUpdate(userId: UUID, id: UUID): ReminderSnapshot? =
        jdbc.sql("$SELECT where user_id = :userId and id = :id for update")
            .param("userId", userId)
            .param("id", id)
            .query { rs, _ -> map(rs) }
            .optional()
            .orElse(null)

    fun findActiveForTask(userId: UUID, taskId: UUID): ReminderSnapshot? =
        jdbc.sql(
            "$SELECT where user_id = :userId and task_id = :taskId and deleted_at is null",
        )
            .param("userId", userId)
            .param("taskId", taskId)
            .query { rs, _ -> map(rs) }
            .optional()
            .orElse(null)

    fun taskExists(userId: UUID, taskId: UUID): Boolean =
        jdbc.sql(
            "select exists(select 1 from tasks where user_id = :userId and id = :taskId and deleted_at is null)",
        )
            .param("userId", userId)
            .param("taskId", taskId)
            .query(Boolean::class.java)
            .single()

    fun create(
        userId: UUID,
        id: UUID,
        taskId: UUID,
        remindAt: Instant,
        now: Instant,
    ): ReminderSnapshot {
        jdbc.sql(
            """
            insert into task_reminders
                (id, user_id, task_id, remind_at, revision, created_at, updated_at)
            values (:id, :userId, :taskId, :remindAt, 1, :now, :now)
            """,
        )
            .param("id", id)
            .param("userId", userId)
            .param("taskId", taskId)
            .param("remindAt", remindAt.atOffset(ZoneOffset.UTC))
            .param("now", now.atOffset(ZoneOffset.UTC))
            .update()

        return find(userId, id) ?: error("Reminder was not created")
    }

    fun update(
        userId: UUID,
        id: UUID,
        taskId: UUID,
        remindAt: Instant,
        baseRevision: Long,
        now: Instant,
    ): ReminderSnapshot? {
        val updated = jdbc.sql(
            """
            update task_reminders
            set task_id = :taskId,
                remind_at = :remindAt,
                revision = revision + 1,
                updated_at = :now
            where user_id = :userId and id = :id
              and revision = :baseRevision and deleted_at is null
            """,
        )
            .param("taskId", taskId)
            .param("remindAt", remindAt.atOffset(ZoneOffset.UTC))
            .param("now", now.atOffset(ZoneOffset.UTC))
            .param("userId", userId)
            .param("id", id)
            .param("baseRevision", baseRevision)
            .update()

        return if (updated == 0) null else find(userId, id)
    }

    fun softDelete(userId: UUID, id: UUID, baseRevision: Long, now: Instant): ReminderSnapshot? {
        val updated = jdbc.sql(
            """
            update task_reminders
            set deleted_at = :now,
                revision = revision + 1,
                updated_at = :now
            where user_id = :userId and id = :id
              and revision = :baseRevision and deleted_at is null
            """,
        )
            .param("now", now.atOffset(ZoneOffset.UTC))
            .param("userId", userId)
            .param("id", id)
            .param("baseRevision", baseRevision)
            .update()

        return if (updated == 0) null else find(userId, id)
    }

    private fun map(rs: java.sql.ResultSet): ReminderSnapshot = ReminderSnapshot(
        id = rs.getObject("id", UUID::class.java),
        userId = rs.getObject("user_id", UUID::class.java),
        taskId = rs.getObject("task_id", UUID::class.java),
        remindAt = rs.getObject("remind_at", OffsetDateTime::class.java).toInstant(),
        revision = rs.getLong("revision"),
        createdAt = rs.getObject("created_at", OffsetDateTime::class.java).toInstant(),
        updatedAt = rs.getObject("updated_at", OffsetDateTime::class.java).toInstant(),
        deletedAt = rs.getObject("deleted_at", OffsetDateTime::class.java)?.toInstant(),
    )

    companion object {
        private const val SELECT = """
            select id, user_id, task_id, remind_at, revision,
                   created_at, updated_at, deleted_at
            from task_reminders
        """
    }
}
