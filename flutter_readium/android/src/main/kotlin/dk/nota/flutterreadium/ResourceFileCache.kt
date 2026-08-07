package dk.nota.flutterreadium

import kotlinx.coroutines.ExperimentalCoroutinesApi
import java.io.File
import java.security.MessageDigest

/**
 * Caches publication resources (e.g. tapped EPUB images) to app-owned files
 * under `cacheDir/flutter_readium_resources/`, keyed by a hash of their href.
 *
 * Used so the platform channel can hand Flutter a short `file://` URL
 * instead of transferring the resource's bytes over the bridge.
 */
@OptIn(ExperimentalCoroutinesApi::class)
internal object ResourceFileCache {
    private val directory: File
        get() = File(ReadiumReader.application.applicationContext.cacheDir, "flutter_readium_resources")

    /**
     * Returns the cache file for [href], creating the cache directory if
     * needed. Does not check whether the file itself already exists.
     */
    fun fileFor(href: String): File {
        val dir = directory
        dir.mkdirs()
        val digest = MessageDigest.getInstance("SHA-256").digest(href.toByteArray())
        val hex = digest.joinToString("") { "%02x".format(it) }
        val ext = href.substringAfterLast('.', "")
        val fileName = if (ext.isEmpty()) hex else "$hex.$ext"
        return File(dir, fileName)
    }

    /**
     * Removes all cached resource files. Called when a publication closes so
     * entries don't outlive the publication they were fetched from.
     */
    fun purgeAll() {
        directory.deleteRecursively()
    }
}
