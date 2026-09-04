package dk.nota.flutterreadium.navigators

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.readium.r2.shared.util.DebugError
import org.readium.r2.shared.util.Error
import org.readium.r2.shared.util.http.HttpError
import org.readium.r2.shared.util.http.HttpStatus
import kotlin.time.Duration.Companion.seconds

internal class AudioStreamErrorPolicyTest {
    @Test
    fun `401 is terminal auth error`() {
        val error = HttpError.ErrorResponse(status = HttpStatus(401))
        assertEquals(AudioStreamErrorAction.Fail("AudioStreamAuthError"), error.audioStreamAction())
    }

    @Test
    fun `403 is terminal auth error`() {
        val error = HttpError.ErrorResponse(status = HttpStatus(403))
        assertEquals(AudioStreamErrorAction.Fail("AudioStreamAuthError"), error.audioStreamAction())
    }

    @Test
    fun `503 is retryable`() {
        val error = HttpError.ErrorResponse(status = HttpStatus(503))
        assertEquals(AudioStreamErrorAction.Retry, error.audioStreamAction())
    }

    @Test
    fun `500 is retryable`() {
        val error = HttpError.ErrorResponse(status = HttpStatus(500))
        assertEquals(AudioStreamErrorAction.Retry, error.audioStreamAction())
    }

    @Test
    fun `404 is terminal http error`() {
        val error = HttpError.ErrorResponse(status = HttpStatus(404))
        assertEquals(AudioStreamErrorAction.Fail("AudioStreamHTTPError"), error.audioStreamAction())
    }

    @Test
    fun `400 is terminal http error`() {
        val error = HttpError.ErrorResponse(status = HttpStatus(400))
        assertEquals(AudioStreamErrorAction.Fail("AudioStreamHTTPError"), error.audioStreamAction())
    }

    @Test
    fun `timeout is retryable`() {
        val error = HttpError.Timeout(DebugError("timed out"))
        assertEquals(AudioStreamErrorAction.Retry, error.audioStreamAction())
    }

    @Test
    fun `unreachable is retryable`() {
        val error = HttpError.Unreachable(DebugError("unreachable"))
        assertEquals(AudioStreamErrorAction.Retry, error.audioStreamAction())
    }

    @Test
    fun `IO error is retryable`() {
        val error = HttpError.IO(DebugError("io error"))
        assertEquals(AudioStreamErrorAction.Retry, error.audioStreamAction())
    }

    @Test
    fun `http error nested in a wrapping cause is still classified`() {
        val wrapper = DebugError("engine error", cause = HttpError.ErrorResponse(status = HttpStatus(401)))
        assertEquals(AudioStreamErrorAction.Fail("AudioStreamAuthError"), wrapper.audioStreamAction())
    }

    @Test
    fun `unclassifiable non-http error is retryable`() {
        val error: Error = DebugError("mystery failure")
        assertEquals(AudioStreamErrorAction.Retry, error.audioStreamAction())
    }

    @Test
    fun `httpStatus extracts status from ErrorResponse`() {
        val error = HttpError.ErrorResponse(status = HttpStatus(401))
        assertEquals(401, error.audioStreamHttpStatus())
    }

    @Test
    fun `httpStatus extracts status from a nested cause`() {
        val wrapper = DebugError("engine error", cause = HttpError.ErrorResponse(status = HttpStatus(503)))
        assertEquals(503, wrapper.audioStreamHttpStatus())
    }

    @Test
    fun `httpStatus is null for non-ErrorResponse http errors`() {
        val error = HttpError.Timeout(DebugError("timed out"))
        assertEquals(null, error.audioStreamHttpStatus())
    }

    @Test
    fun `httpStatus is null for unclassifiable errors`() {
        val error: Error = DebugError("mystery failure")
        assertEquals(null, error.audioStreamHttpStatus())
    }

    @Test
    fun `recovery policy has 3 max attempts by default`() {
        assertEquals(3, AudioRecoveryPolicy().maxAttempts)
    }

    @Test
    fun `recovery policy backs off 1s, 2s, 4s by default`() {
        val policy = AudioRecoveryPolicy()
        assertEquals(1000L, policy.delayMillis(forAttempt = 1))
        assertEquals(2000L, policy.delayMillis(forAttempt = 2))
        assertEquals(4000L, policy.delayMillis(forAttempt = 3))
    }

    @Test
    fun `recovery policy defaults stallTimeoutSeconds to 20`() {
        assertEquals(20.0, AudioRecoveryPolicy().stallTimeoutSeconds, 0.0)
    }

    @Test
    fun `recovery policy honours a custom backoffBaseSeconds`() {
        val policy = AudioRecoveryPolicy(backoffBaseSeconds = 2.0)
        assertEquals(2000L, policy.delayMillis(forAttempt = 1))
        assertEquals(4000L, policy.delayMillis(forAttempt = 2))
        assertEquals(8000L, policy.delayMillis(forAttempt = 3))
    }

    @Test
    fun `recovery policy backoff does not overflow for large attempt counts`() {
        val policy = AudioRecoveryPolicy()
        // attempt 32 exercises 2^31, which wrapped to a negative Int under the old
        // `1 shl attempt` implementation but stays a valid positive Long via pow-based math.
        assertEquals(2_147_483_648_000L, policy.delayMillis(forAttempt = 32))
    }

    @Test
    fun `fromMap parses all fields`() {
        val policy =
            AudioRecoveryPolicy.fromMap(
                mapOf(
                    "maxAttempts" to 5,
                    "backoffBaseSeconds" to 2.0,
                    "stallTimeoutSeconds" to 30.0,
                ),
            )
        assertEquals(5, policy.maxAttempts)
        assertEquals(2.0, policy.backoffBaseSeconds, 0.0)
        assertEquals(30.0, policy.stallTimeoutSeconds, 0.0)
    }

    @Test
    fun `fromMap falls back to defaults for missing or null map`() {
        assertEquals(AudioRecoveryPolicy(), AudioRecoveryPolicy.fromMap(null))
        assertEquals(AudioRecoveryPolicy(), AudioRecoveryPolicy.fromMap(emptyMap<String, Any>()))
    }
}

internal class AudioStallWatchdogTest {
    @Test
    fun `watches only requested unsuppressed playback`() {
        assertTrue(shouldWatchForAudioStall(playWhenReady = true, ended = false, suppressed = false))
        assertFalse(shouldWatchForAudioStall(playWhenReady = false, ended = false, suppressed = false))
        assertFalse(shouldWatchForAudioStall(playWhenReady = true, ended = true, suppressed = false))
        assertFalse(shouldWatchForAudioStall(playWhenReady = true, ended = false, suppressed = true))
    }

    @Test
    fun `frozen position stalls at deadline`() {
        val watchdog = AudioStallWatchdog(timeoutMillis = 3_000)

        assertFalse(watchdog.observe(true, 0, 10.seconds, nowMillis = 0))
        assertFalse(watchdog.observe(true, 0, 10.seconds, nowMillis = 2_999))
        assertTrue(watchdog.observe(true, 0, 10.seconds, nowMillis = 3_000))
    }

    @Test
    fun `forward progress moves deadline`() {
        val watchdog = AudioStallWatchdog(timeoutMillis = 3_000)

        assertFalse(watchdog.observe(true, 0, 10.seconds, nowMillis = 0))
        assertFalse(watchdog.observe(true, 0, 10.2.seconds, nowMillis = 2_000))
        assertFalse(watchdog.observe(true, 0, 10.2.seconds, nowMillis = 4_999))
        assertTrue(watchdog.observe(true, 0, 10.2.seconds, nowMillis = 5_000))
    }

    @Test
    fun `backward seek moves deadline`() {
        val watchdog = AudioStallWatchdog(timeoutMillis = 3_000)

        assertFalse(watchdog.observe(true, 0, 10.seconds, nowMillis = 0))
        assertFalse(watchdog.observe(true, 0, 2.seconds, nowMillis = 2_000))
        assertFalse(watchdog.observe(true, 0, 2.seconds, nowMillis = 4_000))
    }

    @Test
    fun `resource change moves deadline despite offset reset`() {
        val watchdog = AudioStallWatchdog(timeoutMillis = 3_000)

        assertFalse(watchdog.observe(true, 0, 10.seconds, nowMillis = 0))
        assertFalse(watchdog.observe(true, 1, 0.seconds, nowMillis = 2_000))
        assertFalse(watchdog.observe(true, 1, 0.seconds, nowMillis = 4_000))
    }

    @Test
    fun `pause and resume start a fresh window`() {
        val watchdog = AudioStallWatchdog(timeoutMillis = 3_000)

        assertFalse(watchdog.observe(true, 0, 10.seconds, nowMillis = 0))
        assertFalse(watchdog.observe(false, 0, 10.seconds, nowMillis = 4_000))
        assertFalse(watchdog.observe(true, 0, 10.seconds, nowMillis = 10_000))
        assertFalse(watchdog.observe(true, 0, 10.seconds, nowMillis = 12_000))
    }
}
