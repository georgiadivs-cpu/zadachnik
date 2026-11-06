package com.zadachnik.api.backup.application

import java.io.ByteArrayOutputStream
import java.time.Duration
import java.util.concurrent.TimeUnit
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Component

data class CommandResult(
    val exitCode: Int,
    val output: String,
)

interface CommandRunner {
    fun run(
        command: List<String>,
        environment: Map<String, String> = emptyMap(),
        timeout: Duration,
    ): CommandResult
}

@Component
class ProcessCommandRunner : CommandRunner {

    private val log = LoggerFactory.getLogger(javaClass)

    override fun run(
        command: List<String>,
        environment: Map<String, String>,
        timeout: Duration,
    ): CommandResult {
        require(command.isNotEmpty()) { "command is empty" }
        val builder = ProcessBuilder(command)
        builder.environment().putAll(environment)
        builder.redirectErrorStream(true)
        val process = try {
            builder.start()
        } catch (exception: Exception) {
            throw IllegalStateException(
                "Не удалось запустить ${command.first()}: ${exception.message}",
                exception,
            )
        }

        val output = ByteArrayOutputStream()
        val reader = Thread {
            runCatching {
                process.inputStream.use { input ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        if (output.size() < MAX_OUTPUT) {
                            output.write(buffer, 0, minOf(read, MAX_OUTPUT - output.size()))
                        }
                    }
                }
            }
        }
        reader.isDaemon = true
        reader.start()

        val finished = process.waitFor(timeout.toMillis(), TimeUnit.MILLISECONDS)
        if (!finished) {
            process.descendants().forEach { it.destroyForcibly() }
            process.destroyForcibly()
            throw IllegalStateException(
                "Команда ${command.first()} не завершилась за ${timeout.toSeconds()} секунд",
            )
        }
        reader.join(5_000)
        val text = output.toString(Charsets.UTF_8).trim()
        if (process.exitValue() != 0) {
            log.warn(
                "Command {} failed with exit code {}: {}",
                command.first(),
                process.exitValue(),
                text.take(2_000),
            )
        }
        return CommandResult(process.exitValue(), text)
    }

    companion object {
        private const val MAX_OUTPUT = 64 * 1024
    }
}
