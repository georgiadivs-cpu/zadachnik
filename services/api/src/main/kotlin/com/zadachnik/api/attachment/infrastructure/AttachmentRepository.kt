package com.zadachnik.api.attachment.infrastructure

import com.zadachnik.api.attachment.domain.AttachmentSnapshot
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository

@Repository
class AttachmentRepository(private val jdbc: JdbcClient) {

    fun find(userId: UUID, id: UUID): AttachmentSnapshot? =
        jdbc.sql("$SELECT where user_id = :userId and id = :id")
            .param("userId", userId)
            .param("id", id)
            .query { rs, _ -> map(rs) }
            .optional()
            .orElse(null)

    fun ownerExists(userId: UUID, ownerType: String, ownerId: UUID): Boolean {
        val table = when (ownerType) {
            "NOTE" -> "notes"
            "TASK" -> "tasks"
            else -> return false
        }
        return jdbc.sql(
            "select exists(select 1 from $table where user_id = :userId and id = :id and deleted_at is null)",
        )
            .param("userId", userId)
            .param("id", ownerId)
            .query(Boolean::class.java)
            .single()
    }

    fun insert(
        userId: UUID,
        id: UUID,
        ownerType: String,
        ownerId: UUID,
        fileName: String,
        mimeType: String,
        sizeBytes: Long,
        sha256: String,
        storageKey: String,
        now: Instant,
    ): AttachmentSnapshot {
        jdbc.sql(
            """
            insert into attachments
                (id, user_id, owner_type, owner_id, file_name, mime_type,
                 size_bytes, sha256, storage_key, revision, created_at, updated_at)
            values
                (:id, :userId, :ownerType, :ownerId, :fileName, :mimeType,
                 :sizeBytes, :sha256, :storageKey, 1, :now, :now)
            """,
        )
            .param("id", id)
            .param("userId", userId)
            .param("ownerType", ownerType)
            .param("ownerId", ownerId)
            .param("fileName", fileName)
            .param("mimeType", mimeType)
            .param("sizeBytes", sizeBytes)
            .param("sha256", sha256)
            .param("storageKey", storageKey)
            .param("now", now.atOffset(ZoneOffset.UTC))
            .update()

        return find(userId, id) ?: error("Attachment was not created")
    }

    fun softDelete(userId: UUID, id: UUID, now: Instant): AttachmentSnapshot? {
        val updated = jdbc.sql(
            """
            update attachments
            set deleted_at = :now,
                revision = revision + 1,
                updated_at = :now
            where user_id = :userId and id = :id and deleted_at is null
            """,
        )
            .param("now", now.atOffset(ZoneOffset.UTC))
            .param("userId", userId)
            .param("id", id)
            .update()

        return if (updated == 0) null else find(userId, id)
    }

    private fun map(rs: java.sql.ResultSet): AttachmentSnapshot = AttachmentSnapshot(
        id = rs.getObject("id", UUID::class.java),
        userId = rs.getObject("user_id", UUID::class.java),
        ownerType = rs.getString("owner_type"),
        ownerId = rs.getObject("owner_id", UUID::class.java),
        fileName = rs.getString("file_name"),
        mimeType = rs.getString("mime_type"),
        sizeBytes = rs.getLong("size_bytes"),
        sha256 = rs.getString("sha256"),
        storageKey = rs.getString("storage_key"),
        revision = rs.getLong("revision"),
        createdAt = rs.getObject("created_at", OffsetDateTime::class.java).toInstant(),
        updatedAt = rs.getObject("updated_at", OffsetDateTime::class.java).toInstant(),
        deletedAt = rs.getObject("deleted_at", OffsetDateTime::class.java)?.toInstant(),
    )

    companion object {
        private const val SELECT = """
            select id, user_id, owner_type, owner_id, file_name, mime_type,
                   size_bytes, sha256, storage_key, revision,
                   created_at, updated_at, deleted_at
            from attachments
        """
    }
}
