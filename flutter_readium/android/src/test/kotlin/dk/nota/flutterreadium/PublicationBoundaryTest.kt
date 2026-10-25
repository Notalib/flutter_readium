package dk.nota.flutterreadium

import dk.nota.flutterreadium.fragments.isAtPublicationBoundary
import dk.nota.flutterreadium.fragments.logicalPageIndex
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

internal class PublicationBoundaryTest {
    @Test
    fun backward_isBoundaryOnlyOnFirstPageOfFirstResource() {
        assertTrue(isAtPublicationBoundary(false, 0, 3, 0, 4))
        assertFalse(isAtPublicationBoundary(false, 0, 3, 1, 4))
        assertFalse(isAtPublicationBoundary(false, 1, 3, 0, 4))
    }

    @Test
    fun forward_isBoundaryOnlyOnLastPageOfLastResource() {
        assertTrue(isAtPublicationBoundary(true, 2, 3, 3, 4))
        assertFalse(isAtPublicationBoundary(true, 2, 3, 2, 4))
        assertFalse(isAtPublicationBoundary(true, 1, 3, 3, 4))
    }

    @Test
    fun singlePageSingleResource_isBothBoundaries() {
        assertTrue(isAtPublicationBoundary(false, 0, 1, 0, 1))
        assertTrue(isAtPublicationBoundary(true, 0, 1, 0, 1))
    }

    @Test
    fun unknownPageCount_isNeverBoundary() {
        assertFalse(isAtPublicationBoundary(false, 0, 1, 0, 0))
        assertFalse(isAtPublicationBoundary(true, 0, 1, 0, 0))
    }

    @Test
    fun logicalPageIndex_mirrorsOnlyInRtl() {
        assertEquals(0, logicalPageIndex(0, 4, rtl = false))
        assertEquals(3, logicalPageIndex(0, 4, rtl = true))
        assertEquals(0, logicalPageIndex(3, 4, rtl = true))
        assertEquals(2, logicalPageIndex(2, 0, rtl = true))
    }

    @Test
    fun rtl_physicalLastPageIsTheBeginningOfTheResource() {
        // First resource, physical page 3 of 4: the logical first page, so backward is a no-op.
        assertTrue(isAtPublicationBoundary(false, 0, 3, logicalPageIndex(3, 4, true), 4))
        assertFalse(isAtPublicationBoundary(true, 0, 3, logicalPageIndex(3, 4, true), 4))
        // Last resource, physical page 0 of 4: the logical last page, so forward is a no-op.
        assertTrue(isAtPublicationBoundary(true, 2, 3, logicalPageIndex(0, 4, true), 4))
        assertFalse(isAtPublicationBoundary(false, 2, 3, logicalPageIndex(0, 4, true), 4))
    }
}
