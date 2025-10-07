/*
 * Copyright 2023 Readium Foundation. All rights reserved.
 * Use of this source code is governed by the BSD-style license
 * available in the top-level LICENSE file of the project.
 */

package dk.nota.flutter_readium

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
    override val message: String,
    override val cause: Error? = null,
) : Error {

    class Reading(override val cause: ReadError) :
        PublicationError(cause.message, cause.cause)

    class UnsupportedScheme(cause: Error) :
        PublicationError(cause.message, cause.cause)

    class FormatNotSupported(cause: Error) :
        PublicationError(cause.message, cause.cause)

    class InvalidPublication(cause: Error) :
        PublicationError(cause.message, cause.cause)

    class InvalidPublicationUrl(msg: String) :
        PublicationError(msg)

    class Unexpected(cause: Error) :
        PublicationError(cause.message, cause.cause)

    companion object {
        operator fun invoke(error: AssetRetriever.RetrieveUrlError): PublicationError =
            when (error) {
                is AssetRetriever.RetrieveUrlError.Reading ->
                    Reading(error.cause)

                is AssetRetriever.RetrieveUrlError.FormatNotSupported ->
                    FormatNotSupported(error)

                is AssetRetriever.RetrieveUrlError.SchemeNotSupported ->
                    UnsupportedScheme(error)
            }

        operator fun invoke(error: AssetRetriever.RetrieveError): PublicationError =
            when (error) {
                is AssetRetriever.RetrieveError.Reading ->
                    Reading(error.cause)

                is AssetRetriever.RetrieveError.FormatNotSupported ->
                    FormatNotSupported(error)
            }

        operator fun invoke(error: PublicationOpener.OpenError): PublicationError =
            when (error) {
                is PublicationOpener.OpenError.Reading ->
                    Reading(error.cause)

                is PublicationOpener.OpenError.FormatNotSupported ->
                    FormatNotSupported(error)
            }

        operator fun invoke(error: ReadError): PublicationError =
            Reading(error)

        operator fun invoke(error: AudioEngine.Error): PublicationError =
            Unexpected(error)

        operator fun invoke(error: AudioNavigatorFactory.Error): PublicationError =
            when (error) {
                is AudioNavigatorFactory.Error.UnsupportedPublication
                    -> FormatNotSupported(error)
                is AudioNavigatorFactory.Error.EngineInitialization
                    -> Unexpected(error)
            }

        operator fun invoke(error: TtsNavigator.Error): PublicationError =
            when (error) {
                is TtsNavigator.Error.EngineError<*>
                    -> Unexpected(error)
                is TtsNavigator.Error.ContentError
                    -> FormatNotSupported(error)
            }
    }
}
