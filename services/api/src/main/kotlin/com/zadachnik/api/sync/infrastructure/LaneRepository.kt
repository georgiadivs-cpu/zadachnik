package com.zadachnik.api.sync.infrastructure

import com.zadachnik.api.sync.domain.DefaultLanes
import com.zadachnik.api.sync.domain.LaneSnapshot
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository

@Repository
class LaneRepository(private val jdbc: JdbcClient) {

    fun find(userId: UUID, id: UUID): LaneSnapshot? =
        jdbc.sql("$SELECT where user_id = :userId and id = :id")
            .param("userId", userId)
            .param("id", id)
            .query { rs, _ -> map(rs) }
            .optional()
            .orElse(null)

    fun findForUpdate(userId: UUID, id: UUID): LaneSnapshot? =
        jdbc.sql("$SELECT where user_id = :userId and id = :id for update")
            .param("userId", userId)
            .param("id", id)
            .query { rs, _ -> map(rs) }
            .optional()
            .orElse(null)

    fun activeCount(userId: UUID): Int =
        jdbc.sql(
            "select count(*) from board_lanes where user_id = :userId and deleted_at is null",
        )
            .param("userId", userId)
            .query(Int::class.java)
            .single()

    fun taskCount(userId: UUID, laneId: UUID): Int =
        jdbc.sql(
            "select count(*) from tasks where user_id = :userId and lane_id = :laneId and deleted_at is null",
        )
            .param("userId", userId)
            .param("laneId", laneId)
            .query(Int::class.java)
            .single()

    fun create(
        userId: UUID,
        id: UUID,
        name: String,
        sortOrder: Int,
        now: Instant,
    ): LaneSnapshot {
        jdbc.sql(
            """
            insert into board_lanes
                (id, user_id, name, sort_order, revision, created_at, updated_at)
            values (:id, :userId, :name, :sortOrder, 1, :now, :now)
            """,
        )
            .param("id", id)
            .param("userId", userId)
            .param("name", name)
            .param("sortOrder", sortOrder)
            .param("now", now.atOffset(ZoneOffset.UTC))
            .update()

        return find(userId, id) ?: error("Lane was not created")
    }

    fun update(
        userId: UUID,
        id: UUID,
        name: String,
        sortOrder: Int,
        baseRevision: Long,
        now: Instant,
    ): LaneSnapshot? {
        val updated = jdbc.sql(
            """
            update board_lanes
            set name = :name,
                sort_order = :sortOrder,
                revision = revision + 1,
                updated_at = :now
            where user_id = :userId and id = :id
              and revision = :baseRevision and deleted_at is null
            """,
        )
            .param("name", name)
            .param("sortOrder", sortOrder)
            .param("now", now.atOffset(ZoneOffset.UTC))
            .param("userId", userId)
            .param("id", id)
            .param("baseRevision", baseRevision)
            .update()

        return if (updated == 0) null else find(userId, id)
    }

    fun softDelete(userId: UUID, id: UUID, baseRevision: Long, now: Instant): LaneSnapshot? {
        val updated = jdbc.sql(
            """
            update board_lanes
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

    fun seedDefaults(userId: UUID, now: Instant) {
        val offsetNow = now.atOffset(ZoneOffset.UTC)
        DefaultLanes.all.forEachIndexed { index, (id, name) ->
            jdbc.sql(
                """
                insert into board_lanes
                    (id, user_id, name, sort_order, revision, created_at, updated_at)
                values (:id, :userId, :name, :sortOrder, 1, :now, :now)
                on conflict (user_id, id) do nothing
                """,
            )
                .param("id", id)
                .param("userId", userId)
                .param("name", name)
                .param("sortOrder", index)
                .param("now", offsetNow)
                .update()
        }
    }

    private fun map(rs: java.sql.ResultSet): LaneSnapshot = LaneSnapshot(
        id = rs.getObject("id", UUID::class.java),
        userId = rs.getObject("user_id", UUID::class.java),
        name = rs.getString("name"),
        sortOrder = rs.getInt("sort_order"),
        revision = rs.getLong("revision"),
        createdAt = rs.getObject("created_at", OffsetDateTime::class.java).toInstant(),
        updatedAt = rs.getObject("updated_at", OffsetDateTime::class.java).toInstant(),
        deletedAt = rs.getObject("deleted_at", OffsetDateTime::class.java)?.toInstant(),
    )

    companion object {
        private const val SELECT = """
            select id, user_id, name, sort_order, revision,
                   created_at, updated_at, deleted_at
            from board_lanes
        """
    }
}
