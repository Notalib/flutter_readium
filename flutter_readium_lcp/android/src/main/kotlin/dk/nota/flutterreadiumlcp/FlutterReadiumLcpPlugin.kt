package dk.nota.flutterreadiumlcp

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import dk.nota.flutterreadium.FlutterReadiumContentProtections
import dk.nota.flutterreadium.FlutterReadiumRestrictions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.readium.r2.lcp.LcpAuthenticating
import org.readium.r2.lcp.LcpError
import org.readium.r2.lcp.LcpLicense
import org.readium.r2.lcp.LcpService
import org.readium.r2.shared.publication.protection.ContentProtection
import org.readium.r2.shared.publication.services.protectionError
import org.readium.r2.shared.publication.services.protectionScheme
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.http.DefaultHttpClient
import java.io.File
import kotlin.coroutines.resume
import kotlin.time.Instant

private const val TAG = "FlutterReadiumLcp"
private const val CHANNEL_NAME = "dk.nota/flutter_readium_lcp"

private class Services(
    val service: LcpService,
    val assetRetriever: AssetRetriever,
)

/**
 * Registers LCP with `flutter_readium`. Needs EDRLab's private LCP library on the app's classpath,
 * which this plugin never ships; without it LCP stays disabled.
 */
class FlutterReadiumLcpPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var scope: CoroutineScope? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        this.channel = channel
        PendingPassphrases.attach(channel)
        registerWithCore(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.let {
            it.setMethodCallHandler(null)
            PendingPassphrases.detach(it)
        }
        channel = null
        scope?.cancel()
        scope = null
        appContext = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "isAvailable" -> result.success(didRegisterWithCore)
            "acquirePublication" -> acquirePublication(call, result)
            "getLicenseInfo" -> getLicenseInfo(call, result)
            "renewLoan" -> renewLoan(call, result)
            "returnPublication" -> returnPublication(call, result)
            else -> result.notImplemented()
        }
    }

    // Acquisition and license info.

    private fun services(): Services? {
        val context = appContext ?: return null
        return if (didRegisterWithCore) sharedServices(context) else null
    }

    private fun acquirePublication(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val lcplPath = call.argument<String>("lcplPath")
        val progressId = call.argument<Int>("progressId")
        val context = appContext
        val services = services()
        if (lcplPath == null || context == null || services == null) {
            result.error("lcpError", "LCP is unavailable or the license path is invalid.", null)
            return
        }
        val mainHandler = Handler(Looper.getMainLooper())
        scope?.launch {
            var lastPercent = -1
            val acquired =
                services.service.acquirePublication(File(lcplPath)) { fraction ->
                    val percent = (fraction * 100).toInt()
                    if (progressId == null || percent == lastPercent) return@acquirePublication
                    lastPercent = percent
                    mainHandler.post {
                        channel?.invokeMethod("acquisitionProgress", mapOf("id" to progressId, "progress" to fraction))
                    }
                }
            when (acquired) {
                is Try.Failure -> {
                    LcpErrors.report(result, acquired.value)
                }

                is Try.Success -> {
                    val publication = acquired.value
                    try {
                        val target = withContext(Dispatchers.IO) { moveToAcquiredDirectory(context, publication) }
                        result.success(
                            mapOf(
                                "path" to target.absolutePath,
                                "fileName" to target.name,
                                "licenseId" to publication.licenseDocument.id,
                                "mediaType" to publication.format.mediaType.toString(),
                                "fileExtension" to publication.format.fileExtension.value,
                            ),
                        )
                    } catch (e: IllegalArgumentException) {
                        Log.w(TAG, "::acquirePublication. ${e.message}")
                        LcpErrors.report(result, LcpError.Parsing.LicenseDocument)
                    } catch (e: java.io.IOException) {
                        Log.w(TAG, "::acquirePublication. Could not store the publication: ${e.message}")
                        result.error("lcpError", "Could not store the acquired publication.", null)
                    } finally {
                        // Already gone after a successful move.
                        withContext(Dispatchers.IO) { publication.localFile.delete() }
                    }
                }
            }
        }
    }

    /** Copies the download from the toolkit's temp location into `filesDir/flutter_readium_lcp/acquired`. */
    private fun moveToAcquiredDirectory(
        context: Context,
        publication: LcpService.AcquiredPublication,
    ): File {
        val dir = File(context.filesDir, "flutter_readium_lcp/acquired").also { it.mkdirs() }.canonicalFile
        val target = File(dir, publication.suggestedFilename).canonicalFile
        // The file name comes from the license id, which the license document controls.
        require(target.parentFile == dir) { "Acquired file name leaves the acquired directory." }
        publication.localFile.copyTo(target, overwrite = true)
        return target
    }

    /** Opens the license of the publication at `path` and runs [body] with it, then closes it. */
    private fun withLicense(
        call: MethodCall,
        result: MethodChannel.Result,
        body: suspend (LcpLicense) -> Unit,
    ) {
        val path = call.argument<String>("path")
        val services = services()
        if (path == null || services == null) {
            result.error("lcpError", "LCP is unavailable or the path is invalid.", null)
            return
        }
        scope?.launch {
            val asset =
                when (val retrieved = services.assetRetriever.retrieve(File(path))) {
                    is Try.Failure -> {
                        LcpErrors.report(result, retrieved.value)
                        return@launch
                    }

                    is Try.Success -> {
                        retrieved.value
                    }
                }
            try {
                when (val license = services.service.retrieveLicense(asset, DartAuthentication, allowUserInteraction = true)) {
                    is Try.Failure -> {
                        LcpErrors.report(result, license.value)
                    }

                    is Try.Success -> {
                        try {
                            body(license.value)
                        } finally {
                            license.value.close()
                        }
                    }
                }
            } finally {
                asset.close()
            }
        }
    }

    private fun getLicenseInfo(
        call: MethodCall,
        result: MethodChannel.Result,
    ) = withLicense(call, result) { license -> result.success(licenseInfo(license)) }

    private fun renewLoan(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val preferredEnd = call.argument<Number>("endMillis")?.let { Instant.fromEpochMilliseconds(it.toLong()) }
        withLicense(call, result) { license ->
            val listener = RenewListener(preferredEnd)
            when (val renewed = license.renewLoan(listener, prefersWebPage = false)) {
                is Try.Failure -> {
                    val webPageUrl = listener.webPageUrl
                    if (webPageUrl != null) {
                        LcpErrors.reportRenewWebPage(result, webPageUrl)
                    } else {
                        LcpErrors.reportLoan(result, renewed.value)
                    }
                }

                is Try.Success -> {
                    result.success(licenseInfo(license))
                }
            }
        }
    }

    private fun returnPublication(
        call: MethodCall,
        result: MethodChannel.Result,
    ) = withLicense(call, result) { license ->
        when (val returned = license.returnPublication()) {
            is Try.Failure -> LcpErrors.reportLoan(result, returned.value)
            is Try.Success -> result.success(true)
        }
    }

    private fun licenseInfo(lcpLicense: LcpLicense): Map<String, Any?> {
        val document = lcpLicense.license
        val rights = document.rights
        val status = lcpLicense.status
        return mapOf(
            "licenseId" to document.id,
            "provider" to document.provider,
            "issued" to document.issued.toString(),
            "updated" to document.updated.toString(),
            "rightsStart" to rights.start?.toString(),
            "rightsEnd" to rights.end?.toString(),
            "copyLimit" to rights.copy,
            "printLimit" to rights.print,
            "charactersToCopyLeft" to lcpLicense.charactersToCopyLeft.value,
            "pagesToPrintLeft" to lcpLicense.pagesToPrintLeft.value,
            "state" to status?.status?.value,
            "statusMessage" to status?.message,
            "statusUpdated" to status?.statusUpdated?.toString(),
            "canRenewLoan" to lcpLicense.canRenewLoan,
            "maxRenewDate" to lcpLicense.maxRenewDate?.toString(),
            "canReturnPublication" to lcpLicense.canReturnPublication,
        )
    }

    companion object {
        /** Channel of the latest attached engine; the toolkit's passphrase prompts go through it. */
        internal val channel: MethodChannel? get() = PendingPassphrases.latestChannel()

        @Volatile
        private var didRegisterWithCore = false

        @Volatile
        private var services: Services? = null

        /**
         * The one `LcpService` of the process, shared by core's content protection, acquisition and
         * license info. It has its own `AssetRetriever` and `HttpClient`, so it never sees the headers
         * the app sets for core's requests. Created on first use and never torn down with an engine.
         */
        @Synchronized
        private fun sharedServices(context: Context): Services? {
            services?.let { return it }
            val httpClient = DefaultHttpClient()
            val assetRetriever = AssetRetriever(context.contentResolver, httpClient)
            val service = LcpService(context, assetRetriever, httpClient = httpClient) ?: return null
            return Services(service, assetRetriever).also { services = it }
        }

        @Synchronized
        private fun registerWithCore(context: Context) {
            if (didRegisterWithCore) return
            if (!isLcpClientAvailable()) {
                Log.i(TAG, "::registerWithCore. No LCP client library on the classpath; LCP is disabled.")
                return
            }
            didRegisterWithCore = true

            FlutterReadiumContentProtections.register {
                val shared =
                    checkNotNull(sharedServices(context)) {
                        "LcpService is null although the LCP client library was found."
                    }
                shared.service.contentProtection(DartAuthentication)
            }
            FlutterReadiumRestrictions.registerMapper { publication ->
                if (publication.protectionScheme == ContentProtection.Scheme.Lcp) {
                    LcpErrors.map(publication.protectionError)
                } else {
                    null
                }
            }
        }

        /** The same reflective probe `LcpService` runs; it returns null when the library is missing. */
        private fun isLcpClientAvailable(): Boolean =
            try {
                Class.forName("org.readium.lcp.sdk.Lcp").getDeclaredConstructor().newInstance()
                true
            } catch (e: ReflectiveOperationException) {
                false
            } catch (e: LinkageError) {
                // The library is there but its native part does not load on this device.
                Log.w(TAG, "::isLcpClientAvailable. The LCP client library failed to load: $e")
                false
            }
    }
}

/** Renew listener that never shows a web page: it records the URL and fails, so the app can open it. */
private class RenewListener(
    private val preferredEnd: Instant?,
) : LcpLicense.RenewListener {
    class WebPageNotSupportedException : Exception()

    var webPageUrl: String? = null
        private set

    override suspend fun preferredEndDate(maximumDate: Instant?): Instant? =
        preferredEnd?.let { if (maximumDate != null && maximumDate < it) maximumDate else it }

    override suspend fun openWebPage(url: Url) {
        webPageUrl = url.toString()
        throw WebPageNotSupportedException()
    }
}

/** Asks Dart for the passphrase. A null result (cancel, no provider, no engine) makes the toolkit give up. */
private object DartAuthentication : LcpAuthenticating {
    override suspend fun retrievePassphrase(
        license: LcpAuthenticating.AuthenticatedLicense,
        reason: LcpAuthenticating.AuthenticationReason,
        allowUserInteraction: Boolean,
    ): String? {
        val channel = FlutterReadiumLcpPlugin.channel
        if (!allowUserInteraction || channel == null) return null

        val args =
            mapOf(
                "reason" to
                    if (reason == LcpAuthenticating.AuthenticationReason.InvalidPassphrase) "invalid" else "notFound",
                "hint" to license.hint,
                "hintUrl" to license.hintLink?.href?.toString(),
                "provider" to license.provider,
                "licenseId" to license.document.id,
            )
        return PendingPassphrases.ask(channel, args)
    }
}

/**
 * Passphrase requests waiting for Dart, and the engines that can answer them. Each request is resumed
 * exactly once: by Dart's answer, or with null when its engine is gone. Attach, detach and ask share
 * one lock, so a request cannot slip in after its engine detached.
 */
private object PendingPassphrases {
    private class Request(
        val channel: MethodChannel,
        val continuation: CancellableContinuation<String?>,
    )

    private val pending = mutableListOf<Request>()

    /** Channels of the attached engines, oldest first. Guarded by [pending]. */
    private val channels = mutableListOf<MethodChannel>()

    fun attach(channel: MethodChannel) {
        synchronized(pending) { channels.add(channel) }
    }

    fun latestChannel(): MethodChannel? = synchronized(pending) { channels.lastOrNull() }

    /** Removes [channel] and resumes every request still waiting on its engine with null. */
    fun detach(channel: MethodChannel) {
        val stale =
            synchronized(pending) {
                channels.remove(channel)
                pending.filter { it.channel === channel }.also { pending.removeAll(it) }
            }
        stale.forEach { it.continuation.resume(null) }
    }

    suspend fun ask(
        channel: MethodChannel,
        args: Map<String, Any?>,
    ): String? =
        suspendCancellableCoroutine { continuation ->
            val request = Request(channel, continuation)
            val attached =
                synchronized(pending) {
                    (channel in channels).also { if (it) pending.add(request) }
                }
            if (!attached) {
                continuation.resume(null)
                return@suspendCancellableCoroutine
            }
            continuation.invokeOnCancellation { synchronized(pending) { pending.remove(request) } }
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod(
                    "requestPassphrase",
                    args,
                    object : MethodChannel.Result {
                        override fun success(result: Any?) = finish(request, result as? String)

                        override fun error(
                            errorCode: String,
                            errorMessage: String?,
                            errorDetails: Any?,
                        ) {
                            Log.w(TAG, "::ask. Dart failed: $errorCode $errorMessage")
                            finish(request, null)
                        }

                        override fun notImplemented() = finish(request, null)
                    },
                )
            }
        }

    private fun finish(
        request: Request,
        value: String?,
    ) {
        if (synchronized(pending) { pending.remove(request) }) request.continuation.resume(value)
    }
}
