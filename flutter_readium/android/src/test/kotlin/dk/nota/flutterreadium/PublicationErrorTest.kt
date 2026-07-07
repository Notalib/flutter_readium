package dk.nota.flutterreadium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.readium.r2.shared.util.Error
import org.readium.r2.shared.util.data.ReadError
import org.readium.r2.shared.util.http.HttpError
import org.readium.r2.shared.util.http.HttpStatus

internal class PublicationErrorTest {
    @Test
    fun `method-channel details mirror publication error data payload`() {
        val rootCause =
            object : Error {
                override val message: String = "root cause"
                override val cause: Error? = null
            }
        val cause =
            object : Error {
                override val message: String = "outer cause"
                override val cause: Error? = rootCause
            }

        val error = PublicationError.Unexpected(cause)
        val details = error.toMethodChannelDetails()

        assertEquals(mapOf("message" to "root cause"), details)
    }

    @Test
    fun `method-channel details stay null when publication error has no structured payload`() {
        assertNull(PublicationError.InvalidPublicationUrl("missing").toMethodChannelDetails())
    }

    @Test
    fun `401 opening error maps to incorrectCredentials with httpStatus`() {
        val readError = ReadError.Access(HttpError.ErrorResponse(status = HttpStatus(401)))
        val error = PublicationError.Reading(readError)

        assertEquals(PublicationError.ReadiumExceptionType.INCORRECT_CREDENTIALS, error.errorCode)
        assertEquals(401, error.toMethodChannelDetails()?.get("httpStatus"))
    }

    @Test
    fun `403 opening error maps to forbidden with httpStatus`() {
        val readError = ReadError.Access(HttpError.ErrorResponse(status = HttpStatus(403)))
        val error = PublicationError.Reading(readError)

        assertEquals(PublicationError.ReadiumExceptionType.FORBIDDEN, error.errorCode)
        assertEquals(403, error.toMethodChannelDetails()?.get("httpStatus"))
    }

    @Test
    fun `404 opening error maps to notFound with httpStatus`() {
        val readError = ReadError.Access(HttpError.ErrorResponse(status = HttpStatus(404)))
        val error = PublicationError.Reading(readError)

        assertEquals(PublicationError.ReadiumExceptionType.NOT_FOUND, error.errorCode)
        assertEquals(404, error.toMethodChannelDetails()?.get("httpStatus"))
    }

    @Test
    fun `415 opening error maps to formatNotSupported with httpStatus`() {
        val readError = ReadError.Access(HttpError.ErrorResponse(status = HttpStatus(415)))
        val error = PublicationError.Reading(readError)

        assertEquals(PublicationError.ReadiumExceptionType.FORMAT_NOT_SUPPORTED, error.errorCode)
        assertEquals(415, error.toMethodChannelDetails()?.get("httpStatus"))
    }

    @Test
    fun `500 opening error maps to unavailable with httpStatus`() {
        val readError = ReadError.Access(HttpError.ErrorResponse(status = HttpStatus(500)))
        val error = PublicationError.Reading(readError)

        assertEquals(PublicationError.ReadiumExceptionType.UNAVAILABLE, error.errorCode)
        assertEquals(500, error.toMethodChannelDetails()?.get("httpStatus"))
    }

    @Test
    fun `non-500 5xx opening error stays readingError like iOS`() {
        val readError = ReadError.Access(HttpError.ErrorResponse(status = HttpStatus(503)))
        val error = PublicationError.Reading(readError)

        assertEquals(PublicationError.ReadiumExceptionType.READING_ERROR, error.errorCode)
        assertEquals(503, error.toMethodChannelDetails()?.get("httpStatus"))
    }

    @Test
    fun `non-http opening error stays readingError without httpStatus`() {
        val readError = ReadError.Decoding("malformed content")
        val error = PublicationError.Reading(readError)

        assertEquals(PublicationError.ReadiumExceptionType.READING_ERROR, error.errorCode)
        assertNull(error.toMethodChannelDetails()?.get("httpStatus"))
    }

    @Test
    fun `InvalidArgument uses the wire string Dart special-cases as a raw PlatformException`() {
        val error = PublicationError.InvalidArgument("bad arg")

        assertEquals("InvalidArgument", error.errorCode.wireValue)
    }

    @Test
    fun `NoPublicationOpened maps to the NoPublication wire code`() {
        assertEquals(
            "NoPublication",
            PublicationError.NoPublicationOpened().errorCode.wireValue,
        )
    }

    @Test
    fun `Search maps to the SearchError wire code`() {
        assertEquals(
            "SearchError",
            PublicationError.Search("query failed").errorCode.wireValue,
        )
    }

    @Test
    fun `TTSFailure maps to the TTSError wire code`() {
        assertEquals(
            "TTSError",
            PublicationError.TTSFailure("tts failed").errorCode.wireValue,
        )
    }

    @Test
    fun `TTSUtteranceFailure maps to the TTSUtteranceFailed wire code`() {
        assertEquals(
            "TTSUtteranceFailed",
            PublicationError.TTSUtteranceFailure("utterance failed").errorCode.wireValue,
        )
    }

    @Test
    fun `ResourceRead surfaces its reason as the sole details entry`() {
        val error = PublicationError.ResourceRead("no resource", reason = "notFound")

        assertEquals(mapOf("reason" to "notFound"), error.toMethodChannelDetails())
    }

    @Test
    fun `ResourceRead without a reason has no structured details`() {
        val error = PublicationError.ResourceRead("read failed")

        assertNull(error.toMethodChannelDetails())
    }
}
