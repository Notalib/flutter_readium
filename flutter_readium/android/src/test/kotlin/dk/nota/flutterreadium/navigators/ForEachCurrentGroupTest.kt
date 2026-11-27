package dk.nota.flutterreadium.navigators

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Test

internal class ForEachCurrentGroupTest {
    @Test
    fun `adding a group while the block suspends does not throw`() =
        runBlocking {
            val groups = linkedMapOf("highlights" to "h", "search" to "s")
            val visited = mutableListOf<String>()

            forEachCurrentGroup(groups) { group, _ ->
                yield()
                if (group == "highlights") groups["page-numbers"] = "p"
                visited += group
            }

            assertEquals(listOf("highlights", "search"), visited)
        }

    @Test
    fun `a group removed while the block suspends is skipped`() =
        runBlocking {
            val groups = linkedMapOf("highlights" to "h", "page-numbers" to "p")
            val visited = mutableListOf<String>()

            forEachCurrentGroup(groups) { group, _ ->
                yield()
                groups.remove("page-numbers")
                visited += group
            }

            assertEquals(listOf("highlights"), visited)
        }

    @Test
    fun `a group replaced while the block suspends uses the new value`() =
        runBlocking {
            val groups = linkedMapOf("highlights" to "old-h", "search" to "old-s")
            val values = mutableListOf<String>()

            forEachCurrentGroup(groups) { _, value ->
                groups["search"] = "new-s"
                values += value
            }

            assertEquals(listOf("old-h", "new-s"), values)
        }
}
