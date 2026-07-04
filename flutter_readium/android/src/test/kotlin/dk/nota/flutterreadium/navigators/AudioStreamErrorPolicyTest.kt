package dk.nota.flutterreadium.navigators

import org.junit.Assert.assertEquals
import org.junit.Test
import org.readium.r2.shared.util.DebugError
import org.readium.r2.shared.util.Error
import org.readium.r2.shared.util.http.HttpError
import org.readium.r2.shared.util.http.HttpStatus

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
    fun `unclassifiable non-http error is terminal network error`() {
        val error: Error = DebugError("mystery failure")
        assertEquals(AudioStreamErrorAction.Fail("AudioStreamNetworkError"), error.audioStreamAction())
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
    fun `recovery policy has 3 max attempts`() {
        assertEquals(3, AudioRecoveryPolicy().maxAttempts)
    }

    @Test
    fun `recovery policy backs off 1s, 2s, 4s`() {
        val policy = AudioRecoveryPolicy()
        assertEquals(1000L, policy.delayMillis(forAttempt = 1))
        assertEquals(2000L, policy.delayMillis(forAttempt = 2))
        assertEquals(4000L, policy.delayMillis(forAttempt = 3))
    }
}
