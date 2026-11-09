package dk.nota.flutterreadium

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

internal class HasAbsoluteUrlSchemeTest {
    @Test
    fun detectsAbsoluteUrls() {
        assertTrue(hasAbsoluteUrlScheme("https://example.com/pub.epub"))
        assertTrue(hasAbsoluteUrlScheme("http://example.com/pub.epub"))
        assertTrue(hasAbsoluteUrlScheme("content://com.example/document/1"))
        assertTrue(hasAbsoluteUrlScheme("file:///sdcard/pub.epub"))
    }

    @Test
    fun rejectsPlainPaths() {
        assertFalse(hasAbsoluteUrlScheme("/sdcard/pub.epub"))
        assertFalse(hasAbsoluteUrlScheme("pubs/pub.epub"))
        // `://` later in the string is not a leading scheme.
        assertFalse(hasAbsoluteUrlScheme("/sdcard/a://b.epub"))
        // Windows drive letter must not read as a scheme.
        assertFalse(hasAbsoluteUrlScheme("C:\\pubs\\pub.epub"))
        // Scheme without the `://` separator.
        assertFalse(hasAbsoluteUrlScheme("mailto:user@example.com"))
    }
}
