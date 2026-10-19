package dk.nota.flutterreadium

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
internal class OrderedLocatorEmitterTest {
    @Test
    fun slowOwnerLookupCannotBeOvertakenByAnAlreadyOwnedCue() =
        runBlocking {
            fun cue(
                id: String,
                owner: String? = null,
            ) = Locator(
                href = Url("chapter.xhtml")!!,
                mediaType = MediaType.XHTML,
                locations =
                    Locator.Locations(
                        otherLocations =
                            mapOf("cssSelector" to "#$id") +
                                (owner?.let { mapOf("tocHref" to it) } ?: emptyMap()),
                    ),
            )
            val first = cue("p1")
            val second = cue("p2", "chapter.xhtml#second")
            val release = CompletableDeferred<Unit>()
            val emitted = mutableListOf<Locator>()
            val lookups = mutableListOf<Locator>()
            val emitter =
                OrderedLocatorEmitter(
                    enrich = { locator ->
                        lookups.add(locator)
                        release.await()
                        locator.copy(
                            locations =
                                locator.locations.copy(
                                    otherLocations =
                                        locator.locations.otherLocations + ("tocHref" to "chapter.xhtml#first"),
                                ),
                        )
                    },
                    onLocator = { locator, _ -> emitted.add(locator) },
                )
            val earlier = launch(start = CoroutineStart.UNDISPATCHED) { emitter.emit(first, null) }
            val later = launch(start = CoroutineStart.UNDISPATCHED) { emitter.emit(second, null) }
            assertTrue(emitted.isEmpty())
            assertEquals(listOf(first), lookups)
            release.complete(Unit)
            earlier.join()
            later.join()
            assertEquals(listOf("#p1", "#p2"), emitted.map { it.locations.otherLocations["cssSelector"] })
            assertEquals(listOf("chapter.xhtml#first", "chapter.xhtml#second"), emitted.map { it.locations.tocHref })
            assertEquals(listOf(first), lookups)
        }
}
