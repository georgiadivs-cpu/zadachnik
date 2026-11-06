package com.zadachnik.api.sync.infrastructure

import com.zadachnik.api.sync.domain.TaskSnapshot
import java.sql.Types
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository

@Repository
class TaskRepository(private val jdbc: JdbcClient) {

    fun find(userId: UUID, id: UUID): TaskSnapshot? =
        jdbc.sql("$SELECT where user_id = :userId and id = :id")
            .param("userId", userId)
            .param("id", id)
            .query { rs, _ -> map(rs) }
            .optional()
            .orElse(null)

    fun findForUpdate(userId: UUID, id: UUID): TaskSnapshot? =
        jdbc.sql("$SELECT where user_id = :userId and id = :id for update")
            .param("userId", userId)
            .param("id", id)
            .query { rs, _ -> map(rs) }
            .optional()
            .orElse(null)

    fun activeLaneExists(userId: UUID, laneId: UUID): Boolean =
        jdbc.sql(
            "select exists(select 1 from board_lanes where user_id = :userId and id = :laneId and deleted_at is null)",
        )
            .param("userId", userId)
            .param("laneId", laneId)
            .query(Boolean::class.java)
            .single()

    fun categoryExists(categoryId: String): Boolean =
        jdbc.sql("select exists(select 1 from categories where id = :id)")
            .param("id", categoryId)
            .query(Boolean::class.java)
            .single()

    fun create(
        userId: UUID,
        id: UUID,
        title: String,
        description: String,
        laneId: UUID,
        systemState: String,
        categoryId: String?,
        priority: String,
        plannedStartAt: Instant?,
        plannedEndAt: Instant?,
        actualStartAt: Instant?,
        actualEndAt: Instant?,
        now: Instant,
    ): TaskSnapshot {
        jdbc.sql(
            """
            insert into tasks
                (id, user_id, title, description, lane_id, system_state, category_id,
                 priority, planned_start_at, planned_end_at, actual_start_at, actual_end_at,
                 revision, created_at, updated_at)
            values
                (:id, :userId, :title, :description, :laneId, :systemState, :categoryId,
                 :priority, :plannedStartAt, :plannedEndAt, :actualStartAt, :actualEndAt,
                 1, :now, :now)
            """,
        )
            .param("id", id)
            .param("userId", userId)
            .param("title", title)
            .param("description", description)
            .param("laneId", laneId)
            .param("systemState", systemState)
            .param("categoryId", categoryId, Types.VARCHAR)
            .param("priority", priority)
            .param("plannedStartAt", plannedStartAt?.atOffset(ZoneOffset.UTC), Types.TIMESTAMP_WITH_TIMEZONE)
            .param("plannedEndAt", plannedEndAt?.atOffset(ZoneOffset.UTC), Types.TIMESTAMP_WITH_TIMEZONE)
            .param("actualStartAt", actualStartAt?.atOffset(ZoneOffset.UTC), Types.TIMESTAMP_WITH_TIMEZONE)
            .param("actualEndAt", actualEndAt?.atOffset(ZoneOffset.UTC), Types.TIMESTAMP_WITH_TIMEZONE)
            .param("now", now.atOffset(ZoneOffset.UTC))
            .update()

        return find(userId, id) ?: error("Task was not created")
    }

    fun update(
        userId: UUID,
        id: UUID,
        title: String,
        description: String,
        laneId: UUID,
        systemState: String,
        categoryId: String?,
        priority: String,
        plannedStartAt: Instant?,
        plannedEndAt: Instant?,
        actualStartAt: Instant?,
        actualEndAt: Instant?,
        baseRevision: Long,
        now: Instant,
    ): TaskSnapshot? {
        val updated = jdbc.sql(
            """
            update tasks
            set title = :title,
                description = :description,
                lane_id = :laneId,
                system_state = :systemState,
                category_id = :categoryId,
                priority = :priority,
                planned_start_at = :plannedStartAt,
                planned_end_at = :plannedEndAt,
                actual_start_at = :actualStartAt,
                actual_end_at = :actualEndAt,
                revision = revision + 1,
                updated_at = :now
            where user_id = :userId and id = :id
              and revision = :baseRevision and deleted_at is null
            """,
        )
            .param("title", title)
            .param("description", description)
            .param("laneId", laneId)
            .param("systemState", systemState)
            .param("categoryId", categoryId, Types.VARCHAR)
            .param("priority", priority)
            .param("plannedStartAt", plannedStartAt?.atOffset(ZoneOffset.UTC), Types.TIMESTAMP_WITH_TIMEZONE)
            .param("plannedEndAt", plannedEndAt?.atOffset(ZoneOffset.UTC), Types.TIMESTAMP_WITH_TIMEZONE)
            .param("actualStartAt", actualStartAt?.atOffset(ZoneOffset.UTC), Types.TIMESTAMP_WITH_TIMEZONE)
            .param("actualEndAt", actualEndAt?.atOffset(ZoneOffset.UTC), Types.TIMESTAMP_WITH_TIMEZONE)
            .param("now", now.atOffset(ZoneOffset.UTC))
            .param("userId", userId)
            .param("id", id)
            .param("baseRevision", baseRevision)
            .update()

        return if (updated == 0) null else find(userId, id)
    }

    fun softDelete(userId: UUID, id: UUID, baseRevision: Long, now: Instant): TaskSnapshot? {
        val updated = jdbc.sql(
            """
            update tasks
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

    private fun map(rs: java.sql.ResultSet): TaskSnapshot = TaskSnapshot(
        id = rs.getObject("id", UUID::class.java),
        userId = rs.getObject("user_id", UUID::class.java),
        title = rs.getString("title"),
        description = rs.getString("description"),
        laneId = rs.getObject("lane_id", UUID::class.java),
        systemState = rs.getString("system_state"),
        categoryId = rs.getString("category_id"),
        priority = rs.getString("priority"),
        plannedStartAt = rs.getObject("planned_start_at", OffsetDateTime::class.java)?.toInstant(),
        plannedEndAt = rs.getObject("planned_end_at", OffsetDateTime::class.java)?.toInstant(),
        actualStartAt = rs.getObject("actual_start_at", OffsetDateTime::class.java)?.toInstant(),
        actualEndAt = rs.getObject("actual_end_at", OffsetDateTime::class.java)?.toInstant(),
        revision = rs.getLong("revision"),
        createdAt = rs.getObject("created_at", OffsetDateTime::class.java).toInstant(),
        updatedAt = rs.getObject("updated_at", OffsetDateTime::class.java).toInstant(),
        deletedAt = rs.getObject("deleted_at", OffsetDateTime::class.java)?.toInstant(),
    )

    companion object {
        private const val SELECT = """
            select id, user_id, title, description, lane_id, system_state, category_id,
                   priority, planned_start_at, planned_end_at, actual_start_at, actual_end_at,
                   revision, created_at, updated_at, deleted_at
            from tasks
        """
    }
}
