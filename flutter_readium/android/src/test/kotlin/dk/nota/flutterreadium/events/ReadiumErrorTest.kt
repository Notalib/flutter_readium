package dk.nota.flutterreadium.events

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

internal class ReadiumErrorTest {
    @Test
    fun `data serializes as a structured JSON object with only the set fields`() {
        val error =
            ReadiumError(
                message = "boom",
                code = "AudioStreamRetry",
                data = ReadiumErrorDetails(href = "ch1.mp3", attempt = 1, maxAttempts = 3),
            )

        val json = Json.encodeToString(ReadiumError.serializer(), error)

        assertTrue(json.contains("\"href\":\"ch1.mp3\""))
        assertTrue(json.contains("\"attempt\":1"))
        assertTrue(json.contains("\"maxAttempts\":3"))
        assertFalse(json.contains("httpStatus"))
    }

    @Test
    fun `data is omitted when null`() {
        val error = ReadiumError(message = "boom", code = "AudioStreamFailed")

        val json = Json.encodeToString(ReadiumError.serializer(), error)

        assertFalse(json.contains("\"data\""))
    }

    @Test
    fun `terminal failure payload carries href and httpStatus`() {
        val error =
            ReadiumError(
                message = "boom",
                code = "AudioStreamHTTPError",
                data = ReadiumErrorDetails(href = "ch1.mp3", httpStatus = 404),
            )

        val json = Json.encodeToString(ReadiumError.serializer(), error)

        assertEquals(
            true,
            json.contains("\"href\":\"ch1.mp3\"") && json.contains("\"httpStatus\":404"),
        )
    }
}
