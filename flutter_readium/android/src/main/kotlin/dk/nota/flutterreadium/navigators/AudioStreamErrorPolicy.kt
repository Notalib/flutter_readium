package dk.nota.flutterreadium.navigators

import org.readium.r2.shared.util.Error
import org.readium.r2.shared.util.http.HttpError

/**
 * What the audio navigator should do about a playback failure.
 *
 * Mirrors iOS's `AudioStreamErrorAction`
 * (ios/flutter_readium/Sources/flutter_readium/utils/AudioStreamErrorPolicy.swift).
 */
sealed class AudioStreamErrorAction {
    /** Not a real failure worth surfacing. */
    object Ignore : AudioStreamErrorAction()

    /** Transient network-class error: attempt connection recovery. */
    object Retry : AudioStreamErrorAction()

    /** Terminal error: emit failure state + error event with this code. */
    data class Fail(
        val code: String,
    ) : AudioStreamErrorAction()
}

/**
 * Classifies an [Error] surfaced by ExoPlayer/kotlin-toolkit's `AudioEngine.State.Failure`
 * for audio streaming purposes. Unwraps the cause chain looking for an [HttpError], since
 * ExoPlayer's `PlaybackException` (wrapped as `ThrowableError`) or the toolkit's
 * `ReadError.Access(HttpError)` may appear at any depth.
 *
 * Any non-HTTP error (e.g. decoding/local-file errors) is treated as an unclassifiable
 * network-adjacent failure and reported terminal, matching iOS's `.other -> .retry` /
 * default-terminal split for the audio-streaming (remote-HTTP-only) use case.
 */
fun Error.audioStreamAction(): AudioStreamErrorAction =
    findHttpError()?.classify() ?: AudioStreamErrorAction.Fail(code = "AudioStreamNetworkError")

/**
 * The HTTP status code behind this error, if its cause chain contains an
 * [HttpError.ErrorResponse]. `null` for all other error shapes (offline, timeout,
 * decoding, etc.). Mirrors iOS's `ReadError.httpStatus`.
 */
fun Error.audioStreamHttpStatus(): Int? = (findHttpError() as? HttpError.ErrorResponse)?.status?.code

private fun HttpError.classify(): AudioStreamErrorAction =
    when (this) {
        is HttpError.Timeout, is HttpError.Unreachable, is HttpError.Redirection,
        is HttpError.MalformedResponse, is HttpError.IO, is HttpError.SslHandshake,
        -> {
            AudioStreamErrorAction.Retry
        }

        is HttpError.ErrorResponse -> {
            when (status.code) {
                401, 403 -> AudioStreamErrorAction.Fail(code = "AudioStreamAuthError")
                in 500..599 -> AudioStreamErrorAction.Retry
                else -> AudioStreamErrorAction.Fail(code = "AudioStreamHTTPError")
            }
        }
    }

private tailrec fun Error.findHttpError(): HttpError? =
    when (this) {
        is HttpError -> this
        else -> cause?.findHttpError()
    }

/**
 * Exponential backoff policy for audio stream recovery: 1s, 2s, 4s.
 *
 * Mirrors iOS's `AudioRecoveryPolicy`.
 */
data class AudioRecoveryPolicy(
    val maxAttempts: Int = 3,
) {
    fun delayMillis(forAttempt: Int): Long {
        val attempt = maxOf(forAttempt, 1) - 1
        return (1000L shl attempt)
    }
}
