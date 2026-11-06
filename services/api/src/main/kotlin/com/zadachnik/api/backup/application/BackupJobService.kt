package com.zadachnik.api.backup.application

import com.zadachnik.api.backup.infrastructure.BackupStateStore
import com.zadachnik.api.common.ApiException
import java.time.Clock
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import org.slf4j.LoggerFactory
import org.springframework.core.task.TaskExecutor
import org.springframework.http.HttpStatus
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.stereotype.Service

@Configuration
class BackupAppConfiguration {

    @Bean
    fun clock(): Clock = Clock.systemUTC()

    @Bean(name = ["backupExecutor"])
    fun backupExecutor(): ThreadPoolTaskExecutor {
        val executor = ThreadPoolTaskExecutor()
        executor.corePoolSize = 1
        executor.maxPoolSize = 1
        executor.queueCapacity = 1
        executor.setThreadNamePrefix("backup-")
        executor.initialize()
        return executor
    }
}

@Service
class BackupJobService(
    private val service: BackupService,
    private val store: BackupStateStore,
    private val executor: TaskExecutor,
) {

    private val log = LoggerFactory.getLogger(javaClass)
    private val running = ConcurrentHashMap<UUID, Boolean>()

    fun start(userId: UUID) {
        service.ensureConfigured()
        acquire(userId)
        val now = java.time.Instant.now()
        store.updateState(userId) {
            it.copy(
                running = true,
                operation = "BACKUP",
                startedAt = now,
                lastAttemptAt = now,
                lastError = null,
            )
        }
        try {
            executor.execute {
                try {
                    service.run(userId)
                } catch (exception: Exception) {
                    log.warn("Backup failed for user {}", userId, exception)
                    if (store.readState(userId).lastError == null) {
                        store.updateState(userId) {
                            it.copy(lastError = exception.message ?: "Backup не удался")
                        }
                    }
                } finally {
                    release(userId)
                    store.updateState(userId) {
                        it.copy(running = false, operation = null)
                    }
                }
            }
        } catch (exception: Exception) {
            release(userId)
            store.updateState(userId) {
                it.copy(
                    running = false,
                    operation = null,
                    lastError = "Не удалось запустить backup: ${exception.message}",
                )
            }
            throw ApiException(
                HttpStatus.SERVICE_UNAVAILABLE,
                "BACKUP_START_FAILED",
                "Не удалось запустить резервное копирование",
            )
        }
    }

    fun verify(userId: UUID, archiveId: String): com.zadachnik.api.backup.domain.BackupArchive {
        acquire(userId)
        return try {
            service.verify(userId, archiveId)
        } finally {
            release(userId)
            store.updateState(userId) {
                it.copy(running = false, operation = null)
            }
        }
    }

    private fun acquire(userId: UUID) {
        if (running.putIfAbsent(userId, true) != null) {
            throw ApiException(
                HttpStatus.CONFLICT,
                "BACKUP_RUNNING",
                "Резервное копирование уже выполняется",
            )
        }
    }

    private fun release(userId: UUID) {
        running.remove(userId)
    }
}
