package com.zadachnik.api.backup.application

import com.zadachnik.api.backup.domain.BackupArchive
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneOffset
import java.time.temporal.IsoFields

/**
 * Retention: keep the newest N archives, the newest archive of the last
 * N ISO weeks and the newest archive of the last N calendar months.
 * It also protects the newest verified archive (or the newest successful
 * archive when nothing has been verified yet).
 */
object RetentionPolicy {

    fun selectForDeletion(
        archives: List<BackupArchive>,
        now: Instant,
        recent: Int,
        weekly: Int,
        monthly: Int,
    ): List<BackupArchive> {
        val eligible = archives.filter {
            it.status == BackupArchive.STATUS_SUCCESS ||
                it.status == BackupArchive.STATUS_VERIFIED
        }
        if (eligible.isEmpty()) {
            return emptyList()
        }
        val ordered = eligible.sortedByDescending { it.createdAt }
        val keep = linkedSetOf<String>()

        ordered.take(recent.coerceAtLeast(0)).forEach { keep += it.id }

        ordered.groupBy { isoWeekKey(it.createdAt) }
            .entries
            .sortedByDescending { it.value.maxOf { archive -> archive.createdAt } }
            .take(weekly.coerceAtLeast(0))
            .forEach { (_, group) ->
                group.maxByOrNull { it.createdAt }?.let { keep += it.id }
            }

        ordered.groupBy { YearMonth.from(it.createdAt.atZone(ZoneOffset.UTC)) }
            .entries
            .sortedByDescending { it.key }
            .take(monthly.coerceAtLeast(0))
            .forEach { (_, group) ->
                group.maxByOrNull { it.createdAt }?.let { keep += it.id }
            }

        val protected = ordered.filter { it.verifiedAt != null }.maxByOrNull { it.createdAt }
            ?: ordered.firstOrNull()
        protected?.let { keep += it.id }

        // Never delete an archive created after "now" (clock skew or a
        // concurrent run); it is safer to keep it until the next pass.
        return ordered.filter { archive ->
            archive.id !in keep && !archive.createdAt.isAfter(now)
        }
    }

    private fun isoWeekKey(instant: Instant): String {
        val date = instant.atZone(ZoneOffset.UTC).toLocalDate()
        val year = date.get(IsoFields.WEEK_BASED_YEAR)
        val week = date.get(IsoFields.WEEK_OF_WEEK_BASED_YEAR)
        return "$year-$week"
    }
}
