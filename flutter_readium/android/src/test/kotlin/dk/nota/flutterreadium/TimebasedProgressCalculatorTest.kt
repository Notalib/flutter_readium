package dk.nota.flutterreadium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

internal class TimebasedProgressCalculatorTest {
    @Test
    fun computePublicationDurationMs_returnsNull_whenMissingDuration() {
        val result = computePublicationDurationMs(listOf(10.0, null, 20.0))

        assertNull(result)
    }

    @Test
    fun computePublicationDurationMs_returnsNull_whenNonPositiveDuration() {
        val result = computePublicationDurationMs(listOf(10.0, 0.0, 20.0))

        assertNull(result)
    }

    @Test
    fun computePublicationDurationMs_sumsDurationsInMilliseconds() {
        val result = computePublicationDurationMs(listOf(10.0, 20.5))

        assertEquals(30500.0, result)
    }

    @Test
    fun computeTotalProgressDurationMs_returnsNull_whenInputsUnavailable() {
        assertNull(computeTotalProgressDurationMs(null, 1000.0))
        assertNull(computeTotalProgressDurationMs(0.5, null))
    }

    @Test
    fun computeTotalProgressDurationMs_clampsAndRoundsResult() {
        assertEquals(15000.0, computeTotalProgressDurationMs(0.5, 30000.0))
        assertEquals(0.0, computeTotalProgressDurationMs(-1.0, 30000.0))
        assertEquals(30000.0, computeTotalProgressDurationMs(2.0, 30000.0))
        assertEquals(10001.0, computeTotalProgressDurationMs(0.500025, 20001.0))
    }
}
