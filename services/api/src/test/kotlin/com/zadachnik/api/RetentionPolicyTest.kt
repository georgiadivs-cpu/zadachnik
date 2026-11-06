package com.zadachnik.api

import com.zadachnik.api.backup.application.RetentionPolicy
import com.zadachnik.api.backup.domain.BackupArchive
import java.time.Instant
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test

class RetentionPolicyTest {

    private val now = Instant.parse("2026-11-06T12:00:00Z")

    @Test
    fun `keeps seven most recent plus weekly and monthly representatives`() {
        val archives = (0 until 20).map { index ->
            archive(
                id = "a$index",
                createdAt = now.minus(java.time.Duration.ofDays(index.toLong())),
            )
        }

        val deleted = RetentionPolicy.selectForDeletion(
            archives = archives,
            now = now,
            recent = 7,
            weekly = 4,
            monthly = 6,
        )

        assertThat(deleted.map { it.id }).doesNotContain("a0", "a1", "a2", "a3", "a4", "a5", "a6")
        // The oldest archive is removed, the newest verified one is protected.
        assertThat(deleted.map { it.id }).contains("a18")
        assertThat(deleted.map { it.id }).doesNotContain("a4")
    }

    @Test
    fun `never deletes the only verified archive`() {
        val only = archive(id = "only", createdAt = now.minusSeconds(86_400), verified = true)

        val deleted = RetentionPolicy.selectForDeletion(
            archives = listOf(only),
            now = now,
            recent = 1,
            weekly = 1,
            monthly = 1,
        )

        assertThat(deleted).isEmpty()
    }

    @Test
    fun `keeps newest archive of each of the last four iso weeks`() {
        val archiveCurrent = archive("w0", now.minusSeconds(3600))
        val previousWeek = archive("w1", now.minusSeconds(7 * 24 * 3600L))
        val twoWeeks = archive("w2", now.minusSeconds(14 * 24 * 3600L))
        val threeWeeks = archive("w3", now.minusSeconds(21 * 24 * 3600L))
        val fourWeeks = archive("w4", now.minusSeconds(28 * 24 * 3600L))

        val deleted = RetentionPolicy.selectForDeletion(
            archives = listOf(archiveCurrent, previousWeek, twoWeeks, threeWeeks, fourWeeks),
            now = now,
            recent = 1,
            weekly = 4,
            monthly = 1,
        )

        assertThat(deleted.map { it.id }).contains("w4")
    }

    @Test
    fun `failed archives are not part of retention`() {
        val failed = archive("failed", now.minusSeconds(3600)).copy(status = "FAILED")
        val success = archive("success", now)

        val deleted = RetentionPolicy.selectForDeletion(
            archives = listOf(failed, success),
            now = now,
            recent = 1,
            weekly = 1,
            monthly = 1,
        )

        assertThat(deleted.map { it.id }).doesNotContain("failed")
    }

    private fun archive(
        id: String,
        createdAt: Instant,
        verified: Boolean = false,
    ): BackupArchive = BackupArchive(
        id = id,
        fileName = "$id.zip.age",
        createdAt = createdAt,
        finishedAt = createdAt,
        sizeBytes = 100,
        sha256 = "0".repeat(64),
        status = if (verified) BackupArchive.STATUS_VERIFIED else BackupArchive.STATUS_SUCCESS,
        verifiedAt = if (verified) createdAt else null,
    )
}
