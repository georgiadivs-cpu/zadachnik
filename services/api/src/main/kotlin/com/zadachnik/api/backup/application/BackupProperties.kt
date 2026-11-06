package com.zadachnik.api.backup.application

import java.time.Duration
import org.springframework.boot.context.properties.ConfigurationProperties

@ConfigurationProperties(prefix = "app.backups")
data class BackupProperties(
    val dir: String = "./data/backups",
    val ageBinary: String = "age",
    val ageKeygenBinary: String = "age-keygen",
    val ageIdentity: String = "",
    val ageRecipient: String = "",
    val pgDump: String = "pg_dump",
    val pgRestore: String = "pg_restore",
    val deviceSnapshotMaxBytes: Long = 268_435_456,
    val minFreeBytes: Long = 10L * 1024 * 1024 * 1024,
    val retentionRecent: Int = 7,
    val retentionWeekly: Int = 4,
    val retentionMonthly: Int = 6,
    val deviceRetention: Int = 3,
    val processTimeout: Duration = Duration.ofMinutes(30),
)
