package dk.nota.flutterreadium

import io.flutter.FlutterInjector
import io.flutter.embedding.engine.loader.FlutterLoader
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
internal class InjectionAssetTest {
    /** Mirrors FlutterLoader's lookup keys without needing an initialized Flutter engine. */
    private class FakeFlutterLoader : FlutterLoader() {
        override fun getLookupKeyForAsset(asset: String): String = "flutter_assets/$asset"

        override fun getLookupKeyForAsset(
            asset: String,
            packageName: String,
        ): String = getLookupKeyForAsset("packages/$packageName/$asset")
    }

    @Before
    fun setUp() {
        // FlutterLoader's constructor reads FlutterInjector itself, so build it before resetting.
        val loader = FakeFlutterLoader()
        FlutterInjector.reset()
        FlutterInjector.setInstance(FlutterInjector.Builder().setFlutterLoader(loader).build())
    }

    @After
    fun tearDown() {
        FlutterInjector.reset()
    }

    @Test
    fun `app asset is served from the root flutter_assets folder`() {
        val asset = InjectionAsset("assets/css/custom.css", packageName = null)

        assertEquals("flutter_assets/assets/css/custom.css", asset.servedPath)
        assertEquals("https://readium_assets/flutter_assets/assets/css/custom.css", asset.assetUrl)
    }

    @Test
    fun `package asset is served from the package folder`() {
        val asset = InjectionAsset("assets/helpers/flutterReadiumTools.js", packageName = "flutter_readium")

        assertEquals("flutter_assets/packages/flutter_readium/assets/helpers/flutterReadiumTools.js", asset.servedPath)
        assertEquals(
            "https://readium_assets/flutter_assets/packages/flutter_readium/assets/helpers/flutterReadiumTools.js",
            asset.assetUrl,
        )
    }
}
