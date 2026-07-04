package dk.nota.flutterreadium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.readium.r2.shared.util.Error

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
}
