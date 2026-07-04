/*
 * Copyright 2023 Readium Foundation. All rights reserved.
 * Use of this source code is governed by the BSD-style license
 * available in the top-level LICENSE file of the project.
 */

package dk.nota.flutterreadium

import dk.nota.flutterreadium.events.ReadiumErrorDetails
import org.readium.navigator.media.audio.AudioEngine
import org.readium.navigator.media.audio.AudioNavigatorFactory
import org.readium.navigator.media.tts.TtsNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.util.Error
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.data.ReadError
import org.readium.r2.streamer.PublicationOpener

@OptIn(ExperimentalReadiumApi::class)
sealed class PublicationError(
    val errorCode: ReadiumExceptionType,
    override val message: String,
    override val cause: Error? = null,
) : Error {
    class Reading(
        override val cause: ReadError,
    ) : PublicationError(ReadiumExceptionType.READING_ERROR, cause.message, cause.cause)

    class UnsupportedScheme(
        cause: Error,
    ) : PublicationError(ReadiumExceptionType.UNSUPPORTED_SCHEME, cause.message, cause.cause)

    class FormatNotSupported(
        cause: Error,
    ) : PublicationError(ReadiumExceptionType.FORMAT_NOT_SUPPORTED, cause.message, cause.cause)

    class InvalidPublicationUrl(
        msg: String,
    ) : PublicationError(ReadiumExceptionType.NOT_FOUND, msg)

    class Unexpected(
        cause: Error,
    ) : PublicationError(ReadiumExceptionType.UNKNOWN, cause.message, cause.cause)

    class Unavailable(
        message: String = "Resource unavailable",
    ) : PublicationError(ReadiumExceptionType.UNAVAILABLE, message)

    class Unknown(
        message: String = "Unknown error",
    ) : PublicationError(ReadiumExceptionType.UNKNOWN, message)

    enum class ReadiumExceptionType(
        val wireValue: String,
    ) {
        FORMAT_NOT_SUPPORTED("formatNotSupported"),
        UNSUPPORTED_SCHEME("unsupportedScheme"),
        READING_ERROR("readingError"),
        NOT_FOUND("notFound"),
        FORBIDDEN("forbidden"),
        UNAVAILABLE("unavailable"),
        INCORRECT_CREDENTIALS("incorrectCredentials"),
        UNKNOWN("unknown"),
    }

    companion object {
        operator fun invoke(error: AssetRetriever.RetrieveUrlError): PublicationError =
            when (error) {
                is AssetRetriever.RetrieveUrlError.Reading -> {
                    Reading(error.cause)
                }

                is AssetRetriever.RetrieveUrlError.FormatNotSupported -> {
                    FormatNotSupported(error)
                }

                is AssetRetriever.RetrieveUrlError.SchemeNotSupported -> {
                    UnsupportedScheme(error)
                }
            }

        operator fun invoke(error: AssetRetriever.RetrieveError): PublicationError =
            when (error) {
                is AssetRetriever.RetrieveError.Reading -> {
                    Reading(error.cause)
                }

                is AssetRetriever.RetrieveError.FormatNotSupported -> {
                    FormatNotSupported(error)
                }
            }

        operator fun invoke(error: PublicationOpener.OpenError): PublicationError =
            when (error) {
                is PublicationOpener.OpenError.Reading -> {
                    Reading(error.cause)
                }

                is PublicationOpener.OpenError.FormatNotSupported -> {
                    FormatNotSupported(error)
                }
            }

        operator fun invoke(error: ReadError): PublicationError = Reading(error)

        operator fun invoke(error: AudioEngine.Error): PublicationError = Unexpected(error)

        operator fun invoke(error: AudioNavigatorFactory.Error): PublicationError =
            when (error) {
                is AudioNavigatorFactory.Error.UnsupportedPublication,
                -> FormatNotSupported(error)

                is AudioNavigatorFactory.Error.EngineInitialization,
                -> Unexpected(error)
            }

        operator fun invoke(error: TtsNavigator.Error): PublicationError =
            when (error) {
                is TtsNavigator.Error.EngineError<*>,
                -> Unexpected(error)

                is TtsNavigator.Error.ContentError,
                -> FormatNotSupported(error)
            }
    }
}

fun PublicationError.toReadiumErrorDetails(): ReadiumErrorDetails? = cause?.message?.let { ReadiumErrorDetails(message = it) }

fun PublicationError.toMethodChannelDetails(): Map<String, Any?>? =
    toReadiumErrorDetails()?.let { details ->
        buildMap {
            details.href?.let { put("href", it) }
            details.attempt?.let { put("attempt", it) }
            details.maxAttempts?.let { put("maxAttempts", it) }
            details.httpStatus?.let { put("httpStatus", it) }
            details.message?.let { put("message", it) }
        }.takeIf { it.isNotEmpty() }
    }
