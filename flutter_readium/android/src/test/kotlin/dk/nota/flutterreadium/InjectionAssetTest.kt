package dk.nota.flutterreadium

import org.junit.Assert.assertEquals
import org.junit.Test

internal class InjectionAssetTest {
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
