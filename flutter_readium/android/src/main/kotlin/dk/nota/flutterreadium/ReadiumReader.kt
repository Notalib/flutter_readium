package dk.nota.flutterreadium

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.view.ViewGroup
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.FragmentManager
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryOwner
import dk.nota.flutterreadium.events.NarrationSyncEventChannel
import dk.nota.flutterreadium.events.ReadiumError
import dk.nota.flutterreadium.events.ReadiumErrorEventChannel
import dk.nota.flutterreadium.events.ReadiumExternalPlaybackCommand
import dk.nota.flutterreadium.events.ReadiumExternalPlaybackCommandEventChannel
import dk.nota.flutterreadium.events.ReadiumReaderStatus
import dk.nota.flutterreadium.events.ReadiumReaderStatusEventChannel
import dk.nota.flutterreadium.events.TextLocatorEventChannel
import dk.nota.flutterreadium.events.TimedBasedStateEventChannel
import dk.nota.flutterreadium.models.ReadiumTimebasedState
import dk.nota.flutterreadium.navigators.AudioRecoveryPolicy
import dk.nota.flutterreadium.navigators.AudiobookNavigator
import dk.nota.flutterreadium.navigators.ComicNavigator
import dk.nota.flutterreadium.navigators.EpubNavigator
import dk.nota.flutterreadium.navigators.FlutterVisualNavigator
import dk.nota.flutterreadium.navigators.PageBreakSkippingContentIteratorFactory
import dk.nota.flutterreadium.navigators.PdfNavigator
import dk.nota.flutterreadium.navigators.SyncAudiobookNavigator
import dk.nota.flutterreadium.navigators.TTSNavigator
import dk.nota.flutterreadium.navigators.TimebasedNavigator
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.readium.adapter.pdfium.document.PdfiumDocumentFactory
import org.readium.navigator.media.tts.android.AndroidTtsEngine
import org.readium.navigator.media.tts.android.AndroidTtsPreferences
import org.readium.navigator.media.tts.android.AndroidTtsSettings
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.extensions.normalizeLocator
import org.readium.r2.shared.DelicateReadiumApi
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.LocatorCollection
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.html.cssSelector
import org.readium.r2.shared.publication.services.content.DefaultContentService
import org.readium.r2.shared.publication.services.content.content
import org.readium.r2.shared.publication.services.content.contentServiceFactory
import org.readium.r2.shared.publication.services.search.SearchService
import org.readium.r2.shared.publication.services.search.search
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.DebugError
import org.readium.r2.shared.util.Language
import org.readium.r2.shared.util.ThrowableError
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Try.Companion.failure
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.asset.Asset
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.data.Container
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.http.HttpRequest
import org.readium.r2.shared.util.http.HttpTry
import org.readium.r2.shared.util.mediatype.MediaType
import org.readium.r2.shared.util.resource.Resource
import org.readium.r2.shared.util.resource.TransformingContainer
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.PublicationOpener.OpenError
import org.readium.r2.streamer.parser.DefaultPublicationParser
import java.lang.ref.WeakReference
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

private const val TAG = "ReadiumReader"

/** [DefaultHttpClient] has no timeouts by default - a blocked socket read would hang forever. */
private val HTTP_CONNECT_TIMEOUT = 10.seconds
private val HTTP_READ_TIMEOUT = 30.seconds

private const val stateKey = "dk.nota.flutterreadium.ReadiumReaderState"

private val currentPublicationUrlKey = "currentPublicationUrl"
private val ttsEnabledKey = "ttsEnabled"
private val audioEnabledKey = "audioEnabled"
private val syncAudioEnabledKey = "syncAudioEnabled"

private val epubEnabledKey = "epubEnabled"
private val pdfEnabledKey = "pdfEnabled"
private val comicEnabledKey = "comicEnabled"
private val ttsNavigatorStateKey = "ttsState"
private val audioNavigatorStateKey = "audioState"
private val syncAudioNavigatorStateKey = "syncAudioState"
private val epubNavigatorStateKey = "epubState"
private val decorationStyleKey = "decorationStyle"

internal fun shouldInjectMOColumnBreakCss(
    isMOActive: Boolean,
    preventMOColumnBreaks: Boolean,
): Boolean = isMOActive && preventMOColumnBreaks

// TODO: Support custom headers and authentication header for content files.

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class, DelicateReadiumApi::class)
object ReadiumReader :
    TimebasedNavigator.TimebasedListener,
    EpubNavigator.VisualListener,
    CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) {
    private var appRef: WeakReference<Application>? = null

    private var activityRef: WeakReference<Activity>? = null

    /**
     * The host [FragmentActivity], if available. Sourced from the plugin's ActivityAware
     * binding rather than a PlatformView's view context, which is only the Activity under
     * Texture-Layer Hybrid Composition — under Hybrid Composition it is a non-Activity context.
     */
    val fragmentActivity: FragmentActivity?
        get() = activityRef?.get() as? FragmentActivity

    private var timedBasedStateEventChannel: TimedBasedStateEventChannel? = null

    private var externalPlaybackCommandEventChannel: ReadiumExternalPlaybackCommandEventChannel? = null

    private var textLocatorEventChannel: TextLocatorEventChannel? = null

    private var readiumReaderStatusEventChannel: ReadiumReaderStatusEventChannel? = null

    private var errorChannel: ReadiumErrorEventChannel? = null

    private var narrationSyncEventChannel: NarrationSyncEventChannel? = null

    /**
     * Runtime narration-sync flag. `true` means the visual reader follows the audio cue
     * automatically; `false` means the user has entered manual mode (visual stays, audio plays).
     * Seeded from [FlutterEpubPreferences.disableSynchronization]: enabled == !disableSynchronization.
     */
    private var narrationSyncEnabled: Boolean = true

    private var readerViewRef: WeakReference<ReadiumReaderWidget>? = null

    private var savedStateRef: WeakReference<SavedStateRegistry>? = null

    // in-memory cached state
    private val state = mutableMapOf<String, Any?>()

    private val currentReadiumTimebasedState =
        MutableStateFlow(ReadiumTimebasedState.none())

    private val currentTextLocator = MutableStateFlow<Locator?>(null)

    private var defaultHttpHeaders = mutableMapOf<String, String>()

    var decorationStyle: FlutterDecorationPreferences
        get() =
            state[decorationStyleKey] as? FlutterDecorationPreferences
                ?: FlutterDecorationPreferences()
        set(value) {
            state[decorationStyleKey] = value
        }

    private val httpClient by lazy {
        DefaultHttpClient(
            connectTimeout = HTTP_CONNECT_TIMEOUT,
            readTimeout = HTTP_READ_TIMEOUT,
            callback =
                object : DefaultHttpClient.Callback {
                    override suspend fun onStartRequest(request: HttpRequest): HttpTry<HttpRequest> {
                        val requestWithHeaders =
                            request.copy {
                                defaultHttpHeaders.toMap().forEach { (key, value) ->
                                    setHeader(key, value)
                                }
                            }
                        return Try.success(requestWithHeaders)
                    }
                },
        )
    }

    private var assetRetrieverCache: AssetRetriever? = null

    private val assetRetriever: AssetRetriever
        get() {
            if (assetRetrieverCache == null) {
                assetRetrieverCache = AssetRetriever(context.contentResolver, httpClient)
            }

            return assetRetrieverCache!!
        }

    private var publicationOpenerCache: PublicationOpener? = null

    private var ttsNavigator: TTSNavigator? = null

    private var audiobookNavigator: AudiobookNavigator? = null
    private var syncAudiobookNavigator: SyncAudiobookNavigator? = null

    /** TTS-only: handles page-break elements during content iteration. Not [preventMOColumnBreaksActive] (MO-only). */
    private var pageBreakIteratorFactory: PageBreakSkippingContentIteratorFactory? = null

    /**
     * Mirrors `EPUBPreferences.preventMOColumnBreaks`. Defaults to `true`.
     * Consumer can opt out via preferences.
     */
    private var preventMOColumnBreaksActive: Boolean = true

    /** True when a Media Overlay (sync-narration) navigator is active. */
    val isMOActive: Boolean
        get() = syncAudiobookNavigator != null

    /** Whether MO page-change reinjection should run for the current reader state. */
    internal val shouldInjectMOColumnBreakCssOnPageChange: Boolean
        get() = shouldInjectMOColumnBreakCss(isMOActive, preventMOColumnBreaksActive)

    private val timebasedNavigator: TimebasedNavigator<*>?
        get() = audiobookNavigator ?: syncAudiobookNavigator ?: ttsNavigator

    private var visualNavigator: FlutterVisualNavigator? = null

    /** True when the current visual navigator is a PDF navigator. */
    val isPdf: Boolean
        get() = visualNavigator is PdfNavigator

    /** True when the current visual navigator is a comic (CBZ / DiViNa) navigator. */
    val isComic: Boolean
        get() = visualNavigator is ComicNavigator

    /** Typed accessor for EPUB-specific operations. */
    private val epubNavigator: EpubNavigator?
        get() = visualNavigator as? EpubNavigator

    /** Typed accessor for PDF-specific operations. */
    private val pdfNavigator: PdfNavigator?
        get() = visualNavigator as? PdfNavigator

    /** Typed accessor for comic (CBZ / DiViNa) navigator. */
    private val comicNavigator: ComicNavigator?
        get() = visualNavigator as? ComicNavigator

    private var _audioPreferences: FlutterAudioPreferences = FlutterAudioPreferences()

    private var currentTimebasedPublicationDurationMs: Double? = null

    /** Current audio preferences (defaults if audio hasn't been enabled yet). */
    val audioPreferences: FlutterAudioPreferences
        get() = _audioPreferences

    /**
     * The PublicationFactory is used to open publications.
     */
    private val publicationOpener: PublicationOpener
        get() {
            if (publicationOpenerCache == null) {
                publicationOpenerCache =
                    PublicationOpener(
                        publicationParser =
                            DefaultPublicationParser(
                                context,
                                assetRetriever = assetRetriever,
                                httpClient = httpClient,
                                pdfFactory = PdfiumDocumentFactory(context),
                            ),
                    )
            }

            return publicationOpenerCache!!
        }

    // Initialize from plugin or anywhere you have an Application or Context.
    fun attach(
        activity: Activity,
        messenger: BinaryMessenger,
    ) {
        unwrapToApplication(activity)?.let { appRef = WeakReference(it) }
        activityRef = WeakReference(activity)

        timedBasedStateEventChannel?.dispose()
        timedBasedStateEventChannel = TimedBasedStateEventChannel(messenger)

        externalPlaybackCommandEventChannel?.dispose()
        externalPlaybackCommandEventChannel = ReadiumExternalPlaybackCommandEventChannel(messenger)

        textLocatorEventChannel?.dispose()
        textLocatorEventChannel = TextLocatorEventChannel(messenger)

        readiumReaderStatusEventChannel?.dispose()
        readiumReaderStatusEventChannel = ReadiumReaderStatusEventChannel(messenger)

        errorChannel?.dispose()
        errorChannel = ReadiumErrorEventChannel(messenger)

        narrationSyncEventChannel?.dispose()
        narrationSyncEventChannel = NarrationSyncEventChannel(messenger)

        // store weak ref only
        (activity as? SavedStateRegistryOwner)?.savedStateRegistry?.let {
            savedStateRef = WeakReference(it)
            it.registerSavedStateProvider(stateKey) {
                storeState()
            }

            restoreState(it.consumeRestoredStateForKey(stateKey))
        }

        currentReadiumTimebasedState
            .onEach {
                PluginLog.d(
                    TAG,
                    "currentTimebasedReaderState: ${
                        jsonEncode(
                            it.toJSON(),
                        )
                    }",
                )

                timedBasedStateEventChannel?.sendEvent(it)
            }.launchIn(this)
    }

    private fun storeState(): Bundle {
        if (currentPublicationUrl == null) {
            // No current publication, no state.
            return Bundle()
        }

        return Bundle().apply {
            putString(currentPublicationUrlKey, currentPublicationUrl)
            putBoolean(epubEnabledKey, epubNavigator != null)
            putBundle(epubNavigatorStateKey, epubNavigator?.storeState())
            // PdfNavigatorFragment in kotlin-toolkit does not support
            // process-death restoration (`RestorationNotSupportedException` from
            // its onResume). We record the boolean for symmetry but skip the
            // serialised state bundle — the widget reopens fresh on restore.
            putBoolean(pdfEnabledKey, pdfNavigator != null)
            // ImageNavigatorFragment also throws RestorationNotSupportedException on
            // process-death restore — same treatment as PDF: record the flag only.
            putBoolean(comicEnabledKey, comicNavigator != null)
            putBoolean(ttsEnabledKey, ttsNavigator != null)
            putBundle(ttsNavigatorStateKey, ttsNavigator?.storeState())
            putBoolean(audioEnabledKey, audiobookNavigator != null)
            putBundle(audioNavigatorStateKey, audiobookNavigator?.storeState())
            putBoolean(syncAudioEnabledKey, syncAudiobookNavigator != null)
            putBundle(syncAudioNavigatorStateKey, syncAudiobookNavigator?.storeState())
            putParcelable(decorationStyleKey, decorationStyle)
        }
    }

    private fun restoreState(bundle: Bundle?) {
        if (bundle == null) {
            PluginLog.d(TAG, "::restoreState nothing to restore")
            return
        }

        PluginLog.d(TAG, "::restoreState $bundle")
        val pubUrl = bundle.getString(currentPublicationUrlKey)
        if (pubUrl == null) {
            PluginLog.d(TAG, "::storeState - currentPublicationUrl - not restored")
            return
        }

        PluginLog.d(TAG, "::restoreState - currentPublicationUrl - $pubUrl")
        launch {
            val pub =
                openPublication(pubUrl).getOrElse {
                    PluginLog.d(TAG, "::restoreState - failed to restore publication")
                    // TODO: Handle this somehow
                    return@launch
                }

            decorationStyle =
                bundle.getParcelable(decorationStyleKey) as? FlutterDecorationPreferences
                    ?: FlutterDecorationPreferences()

            if (bundle.getBoolean(epubEnabledKey)) {
                PluginLog.d(TAG, "::storeState - restore epub navigator")
                bundle.getBundle(epubNavigatorStateKey)?.let { state ->
                    visualNavigator =
                        EpubNavigator.restoreState(pub, this@ReadiumReader, state).apply {
                            initNavigator()
                            PluginLog.d(TAG, "::storeState - epubNavigator restored")
                            setDecorationStyle(decorationStyle)
                        }
                }
            }

            // We deliberately do not restore the PDF navigator across process
            // death — upstream PdfNavigatorFragment doesn't support it. The
            // widget will re-enable PDF on next attach using the locator that
            // Dart re-supplies via creation params.
            if (bundle.getBoolean(pdfEnabledKey)) {
                PluginLog.d(TAG, ":storeState - PDF was active; skipping restore (unsupported by PdfNavigatorFragment)")
            }

            // ImageNavigatorFragment also throws RestorationNotSupportedException on
            // process-death restore — same treatment as PDF: skip and let the widget
            // re-enable on next attach.
            if (bundle.getBoolean(comicEnabledKey)) {
                PluginLog.d(TAG, "::storeState - comic was active; skipping restore (unsupported by ImageNavigatorFragment)")
            }

            if (bundle.getBoolean(ttsEnabledKey)) {
                // Restore TTS navigator
                PluginLog.d(TAG, "::storeState - restore tts navigator")
                bundle.getBundle(ttsNavigatorStateKey)?.let { state ->
                    ttsNavigator =
                        TTSNavigator.restoreState(pub, this@ReadiumReader, state).apply {
                            initNavigator()
                            PluginLog.d(TAG, "::storeState - ttsNavigator restored")
                        }
                }
            }

            if (bundle.getBoolean(audioEnabledKey)) {
                // Restore Audio navigator
                PluginLog.d(TAG, "::storeState - restore audio navigator")
                bundle.getBundle(audioNavigatorStateKey)?.let { state ->
                    audiobookNavigator =
                        AudiobookNavigator.restoreState(pub, this@ReadiumReader, state).apply {
                            initNavigator()
                            PluginLog.d(TAG, "::storeState - audioNavigator restored")
                        }
                    currentTimebasedPublicationDurationMs = computePublicationDurationMs(pub.readingOrder.map { it.duration })
                }
            } else if (bundle.getBoolean(syncAudioEnabledKey)) {
                // Restore Sync Audio navigator
                PluginLog.d(TAG, "::storeState - restore sync audio navigator")
                val (ap, mediaOverlays) = pub.makeSyncAudiobook()
                if (mediaOverlays != null) {
                    bundle.getBundle(syncAudioNavigatorStateKey)?.let { state ->
                        syncAudiobookNavigator =
                            SyncAudiobookNavigator
                                .restoreState(
                                    ap,
                                    mediaOverlays,
                                    this@ReadiumReader,
                                    state,
                                ).apply {
                                    initNavigator()
                                    PluginLog.d(TAG, "::storeState - syncAudioNavigator restored")
                                }
                        currentTimebasedPublicationDurationMs = computePublicationDurationMs(ap.readingOrder.map { it.duration })
                    }
                } else {
                    PluginLog.e(TAG, "::storeState - no media overlays for sync audio navigator")
                }
            }

            PluginLog.d(TAG, "consumeRestoredStateForKey - 2 - $currentPublication")
        }
    }

    fun detach() {
        // `detach()` runs twice on shutdown: once from `onDetachedFromActivity` and once
        // from `onDetachedFromEngine`. The first call clears `appRef`, so the second one
        // crashes the app in `closePublication() -> ResourceFileCache.purgeAll()`, which
        // reads `application` and throws IllegalStateException. Nothing is left to release
        // at that point, so return early.
        if (appRef?.get() == null && activityRef?.get() == null) {
            PluginLog.d(TAG, "::detach - already detached, nothing to do")
            return
        }

        closePublication()

        appRef?.clear()
        appRef = null

        activityRef?.clear()
        activityRef = null

        savedStateRef?.clear()
        savedStateRef = null

        assetRetrieverCache = null
        publicationOpenerCache = null

        readerViewRef?.clear()
        readerViewRef = null

        timedBasedStateEventChannel?.dispose()
        timedBasedStateEventChannel = null

        externalPlaybackCommandEventChannel?.dispose()
        externalPlaybackCommandEventChannel = null

        textLocatorEventChannel?.dispose()
        textLocatorEventChannel = null

        readiumReaderStatusEventChannel?.dispose()
        readiumReaderStatusEventChannel = null

        errorChannel?.dispose()
        errorChannel = null

        narrationSyncEventChannel?.dispose()
        narrationSyncEventChannel = null

        coroutineContext.cancelChildren()
    }

    // Safe getter — returns applicationContext or throws if not available.
    val application: Application
        get() =
            appRef?.get()
                ?: throw IllegalStateException("Application not initialized. Call ReadiumReader.attach(...) first.")

    var currentReaderWidget: ReadiumReaderWidget?
        get() = readerViewRef?.get()
        set(value) {
            readerViewRef = value?.let { WeakReference(it) }
        }

    /** Selection actions configured from Dart. Used by EpubReaderFragment to build ActionMode menu. */
    var selectionActions: List<SelectionActionConfig> = emptyList()

    /** Extra CSS assets injected alongside the built-in helpers. */
    var cssInjections: List<InjectionAsset> = emptyList()

    /** Extra JavaScript assets injected alongside the built-in helpers. */
    var javaScriptInjections: List<InjectionAsset> = emptyList()

    private val context: Context
        get() = application.applicationContext

    private var _currentPublication: Publication? = null
    val currentPublication: Publication?
        get() = _currentPublication
    var currentPublicationUrl
        get() = state[currentPublicationUrlKey] as String?
        set(value) {
            state[currentPublicationUrlKey] = value
        }

    /***
     * For EPUB profile, maps document [Url] to a list of all the cssSelectors in the document.
     *
     * This is used to find the current toc item.
     */
    private var currentPublicationCssSelectorMap: MutableMap<Url, List<String>>? = null

    /**
     * Sets the headers used in the HTTP requests for fetching publication resources, including
     * resources in already created `Publication` objects.
     *
     * @param headers a map of HTTP header key value pairs.
     */
    fun setDefaultHttpHeaders(headers: Map<String, String>) {
        defaultHttpHeaders.clear()
        defaultHttpHeaders.putAll(headers)
    }

    /**
     * Policy for the audio-stream error recovery loop (retry attempts, backoff, stall
     * detection). Read by [dk.nota.flutterreadium.navigators.AudiobookNavigator] at
     * construction time — applies to the next-opened publication and to any in-flight
     * recovery loop, not to an already-running attempt sequence.
     */
    var audioRecoveryPolicy: AudioRecoveryPolicy = AudioRecoveryPolicy()

    private suspend fun assetToPublication(
        asset: Asset,
        transformingContainerFactory: ((Container<Resource>) -> Container<Resource>)? = null,
    ): Try<Publication, OpenError> {
        val publication: Publication =
            publicationOpener
                .open(asset, allowUserInteraction = true, onCreatePublication = {
                    container = transformingContainerFactory?.let { it(container) } ?: container
                    if (manifest.conformsTo(Publication.Profile.EPUB)) {
                        val factory = PageBreakSkippingContentIteratorFactory()
                        pageBreakIteratorFactory = factory
                        servicesBuilder.contentServiceFactory =
                            DefaultContentService.createFactory(
                                listOf(factory),
                            )
                    }
                })
                .getOrElse { err: OpenError ->
                    fun unwrapCause(e: org.readium.r2.shared.util.Error?): String =
                        when (e) {
                            null -> "null"
                            is ThrowableError<*> -> "${e.message} | throwable: ${e.throwable}"
                            else -> "${e.message} | cause: ${unwrapCause(e.cause)}"
                        }
                    val detail =
                        when (err) {
                            is OpenError.Reading -> "Reading error: ${unwrapCause(err.cause)}"
                            is OpenError.FormatNotSupported -> "FormatNotSupported: ${unwrapCause(err.cause)}"
                            else -> err.toString()
                        }
                    PluginLog.e(TAG, "Error opening publication: $detail")
                    asset.close()
                    return failure(err)
                }
        PluginLog.d(TAG, "Open publication success: $publication")
        return Try.success(publication)
    }

    /**
     * Load a publication from a String url.
     * Note: Remember to close the publication to avoid leaks.
     */
    suspend fun loadPublication(pubUrl: String?): Try<Publication, PublicationError> {
        if (pubUrl == null) {
            return failure(
                PublicationError.Unexpected(
                    DebugError("missing argument"),
                ),
            )
        }

        return AbsoluteUrl.invoke(pubUrl)?.let { pubUrl -> loadPublication(pubUrl) } ?: failure(
            PublicationError.Unexpected(
                DebugError("Invalid Url"),
            ),
        )
    }

    /**
     * Load a publication from an AbsoluteUrl
     *
     * Note: Remember to close the publication to avoid leaks.
     */
    suspend fun loadPublication(
        pubUrl: AbsoluteUrl,
        transformingContainerFactory: ((Container<Resource>) -> Container<Resource>)? = null,
    ): Try<Publication, PublicationError> {
        if (currentPublicationUrl == pubUrl.toString()) {
            // Current publication is the same as the one we are trying to load, return it.
            currentPublication?.let {
                return Try.success(it)
            }
        }

        return withContext(Dispatchers.IO) {
            try {
                // TODO: should client provide mediaType to assetRetriever?
                val asset: Asset =
                    assetRetriever
                        .retrieve(pubUrl)
                        .getOrElse { error: AssetRetriever.RetrieveUrlError ->
                            PluginLog.e(TAG, "Error retrieving asset: $error from url:$pubUrl")
                            return@withContext failure(PublicationError.invoke(error))
                        }
                val pub =
                    assetToPublication(
                        asset,
                        transformingContainerFactory,
                    ).getOrElse { error: OpenError ->
                        PluginLog.e(
                            TAG,
                            "Error loading asset to Publication object: $error from url:$pubUrl",
                        )
                        return@withContext failure(PublicationError.invoke(error))
                    }
                PluginLog.d(TAG, "Opened publication = ${pub.metadata.identifier} from url:$pubUrl")
                return@withContext Try.success(pub)
            } catch (e: Throwable) {
                return@withContext failure(PublicationError.Unexpected(ThrowableError(e)))
            }
        }
    }

    /**
     * Open a publication and set it as the current publication.
     */
    suspend fun openPublication(pubUrl: String?): Try<Publication, PublicationError> {
        if (pubUrl == null) {
            return failure(
                PublicationError.Unexpected(
                    DebugError("missing argument"),
                ),
            )
        }

        return AbsoluteUrl.invoke(pubUrl)?.let { pubUrl -> openPublication(pubUrl) } ?: failure(
            PublicationError.Unexpected(
                DebugError("Invalid Url"),
            ),
        )
    }

    /**
     * Open a publication and set it as the current publication.
     */
    suspend fun openPublication(pubUrl: AbsoluteUrl): Try<Publication, PublicationError> {
        if (currentPublicationUrl == pubUrl.toString()) {
            // Current publication is the same as the one we are trying to open, return it.
            // If you need to reload the publication, you need to close it first.
            currentPublication?.let {
                return Try.success(it)
            }
        }

        // Close previously opened publication to avoid leaks.
        closePublication()

        val transformingContainerFactory =
            fun(container: Container<Resource>): Container<Resource> {
                return TransformingContainer(container) { url: Url, resource: Resource ->
                    val publication = currentPublication ?: return@TransformingContainer resource
                    val navigator = epubNavigator ?: return@TransformingContainer resource

                    val tocIds =
                        publication.tableOfContents
                            .flattenChildren()
                            .mapNotNull { it.href.resolve().fragment }
                    val epubPreferences =
                        navigator.preferences?.effectiveForLayout(publication.metadata.layout)
                    if (url.extension?.value?.endsWith("html", ignoreCase = true) == true) {
                        resource.injectScriptsAndStyles(
                            tocIds,
                            epubPreferences,
                            javaScriptInjections + cssInjections,
                        )
                    } else {
                        resource
                    }
                }
            }

        val pub =
            loadPublication(
                pubUrl,
                transformingContainerFactory,
            ).getOrElse { e -> return failure(e) }

        _currentPublication = pub
        currentPublicationUrl = pubUrl.toString()

        return Try.success(pub)
    }

    /**
     * Load a publication from a URL
     * Note: Remember to close the publication to avoid leaks.
     */
    suspend fun loadPublicationFromUrl(urlStr: String): Try<Publication, PublicationError> {
        val pubUrl =
            resolvePubUrl(urlStr).getOrElse {
                return failure(PublicationError.InvalidPublicationUrl(urlStr))
            }

        PluginLog.d(TAG, "loadPublicationFromUrl: $pubUrl")

        return loadPublication(pubUrl)
    }

    /**
     * Open a publication from a URL.
     *
     * Note: This sets the publication as the current publication.
     */
    suspend fun openPublicationFromUrl(urlStr: String): Try<Publication, PublicationError> {
        val pubUrl =
            resolvePubUrl(urlStr).getOrElse {
                return failure(PublicationError.InvalidPublicationUrl(urlStr))
            }

        PluginLog.d(TAG, "openPublicationFromUrl: $pubUrl")

        return openPublication(pubUrl)
    }

    /**
     * Helper function for resolving a URL and make sure a file path is turned into a URL.
     */
    private fun resolvePubUrl(urlStr: String): Try<AbsoluteUrl, PublicationError> {
        var pubUrlStr = urlStr
        // If URL is neither http nor file, assume it is a local file reference.
        if (!pubUrlStr.startsWith("http") && !pubUrlStr.startsWith("file")) {
            pubUrlStr = "file://$pubUrlStr"
        }
        // Create AbsoluteUrl, return PublicationError.InvalidPublicationUrl if null
        val pubUrl =
            AbsoluteUrl(pubUrlStr) ?: return failure(
                PublicationError.InvalidPublicationUrl(pubUrlStr),
            )

        return Try.success(pubUrl)
    }

    fun closePublication() {
        ttsNavigator?.dispose()
        ttsNavigator = null
        audiobookNavigator?.dispose()
        audiobookNavigator = null
        syncAudiobookNavigator?.dispose()
        syncAudiobookNavigator = null

        _audioPreferences = FlutterAudioPreferences()
        currentTimebasedPublicationDurationMs = null

        currentReadiumTimebasedState.value = ReadiumTimebasedState()
        currentTextLocator.value = null

        _currentPublication?.close()
        _currentPublication = null
        pageBreakIteratorFactory = null
        currentPublicationCssSelectorMap = null
        ResourceFileCache.purgeAll()

        state.clear()
    }

    override fun onTimebasedPlaybackStateChanged(timebasedState: TimebasedNavigator.TimebasedState) {
        PluginLog.d(TAG, "::onTimebasedPlaybackStateChanged $timebasedState")
        currentReadiumTimebasedState.value = currentReadiumTimebasedState.value.copyWith(state = timebasedState)
    }

    override fun onTimebasedBufferChanged(buffer: Duration?) {
        PluginLog.d(TAG, "::onTimebasedBufferChanged $buffer")
        currentReadiumTimebasedState.value = currentReadiumTimebasedState.value.copyWith(currentBuffered = buffer?.inWholeMilliseconds)
    }

    override fun onTimebasedPlaybackFailure(error: PublicationError) {
        PluginLog.e(TAG, "::onTimebasedPlaybackFailure $error")

        errorChannel?.sendEvent(ReadiumError.invoke(error))
    }

    @OptIn(InternalReadiumApi::class)
    override fun onTimebasedCurrentLocatorChanges(
        locator: Locator,
        currentReadingOrderLink: Link?,
    ) {
        val duration = currentReadingOrderLink?.duration
        val timeOffset = locator.locations.timeWithDuration(duration)

        PluginLog.d(TAG, "::onTimebasedCurrentLocatorChanges $locator, timeOffset=$timeOffset")

        currentReadiumTimebasedState.value =
            currentReadiumTimebasedState.value.copyWith(
                currentOffset = timeOffset?.inWholeMilliseconds?.toDouble(),
                currentDuration = duration?.let { it * 1000 },
                totalProgressDuration =
                    computeTotalProgressDurationMs(
                        locator.locations.totalProgression,
                        currentTimebasedPublicationDurationMs,
                    ),
                totalDuration = currentTimebasedPublicationDurationMs,
                currentLocator = locator,
            )
    }

    override fun onTimebasedLocationChanged(
        locator: Locator,
        isWordRange: Boolean,
    ) {
        PluginLog.d(TAG, "::onTimebasedLocationChanged $locator")

        // In scroll mode, skip fine-grained word-range syncs. Scrolling to each
        // spoken word re-pins the current paragraph to the top of the viewport,
        // causing constant snap-to-top jitter. The utterance-level sync and the
        // per-word highlight decoration keep the reader in the right place.
        // In pagination we DO follow the word range, so an utterance spanning a
        // page boundary turns the page to the word currently being spoken.
        if (isWordRange && epubNavigator?.preferences?.scroll == true) {
            PluginLog.d(TAG, "::onTimebasedLocationChanged skipped word-range sync in scroll mode")
            return
        }

        launch {
            syncVisualToLocator(locator, true)
        }
    }

    /**
     * Find the current table of content item from a locator.
     */
    suspend fun epubEnrichLocatorWithTocHref(locator: Locator): Locator {
        val publication =
            currentPublication ?: run {
                PluginLog.e(TAG, "::epubEnrichLocatorWithTocHref - no currentPublication")
                return locator
            }

        if (!publication.conformsTo(Publication.Profile.EPUB)) {
            PluginLog.w(TAG, "::epubEnrichLocatorWithTocHref - not an EPUB profile")
            return locator
        }

        // This locator already has a tocHref, add title and return it.
        locator.locations.tocHref?.let { tocHref ->
            return locator.copy(title = publication.getTitleFromTocHref(tocHref))
        }

        val cssSelector =
            locator.locations.cssSelector ?: run {
                PluginLog.w(TAG, "::epubEnrichLocatorWithTocHref - missing cssSelector in locator")
                return locator
            }

        val resultLocator = locator.copy()

        val cleanHref = resultLocator.href.cleanHref()
        val tocLinks =
            publication.tableOfContents.flattenChildren().filter {
                it.href
                    .resolve()
                    .cleanHref()
                    .path == cleanHref.path
            }

        val documentCssSelectors = epubGetAllDocumentCssSelectors(resultLocator.href)
        val idx =
            documentCssSelectors.indexOf(cssSelector).takeIf { it > -1 } ?: run {
                // cssSelector wasn't found in the list of document cssSelectors, best effort is to assume first
                PluginLog.d(
                    TAG,
                    "::epubEnrichLocatorWithTocHref - cssSelector:$cssSelector not found in contentIds, assume idx = 0",
                )
                0
            }

        val toc =
            tocLinks.associateBy { documentCssSelectors.indexOf("#${it.href.resolve().fragment}") }

        val tocItem =
            toc.entries.lastOrNull { it.key <= idx }?.value ?: toc.entries.firstOrNull()?.value
                ?: run {
                    PluginLog.d(TAG, "::epubEnrichLocatorWithTocHref - no tocItem found")
                    return resultLocator
                }

        return resultLocator
            .copy(
                title = tocItem.title,
            ).copyWithTocHref(tocItem)
    }

    @OptIn(InternalReadiumApi::class)
    suspend fun epubEnable(
        initialLocator: Locator?,
        initialPreferences: FlutterEpubPreferences,
        fontFamilyDeclarations: List<ReaderFontFamily>,
        fragmentManager: FragmentManager,
        viewGroup: ViewGroup,
        readerWidget: ReadiumReaderWidget,
    ) {
        val pub = currentPublication ?: throw Exception("Publication not opened cannot enable epub")

        currentReaderWidget = readerWidget

        val isEpub = pub.conformsTo(Publication.Profile.EPUB)
        if (!isEpub) {
            throw Exception("Publication is not an EPUB, cannot enable epub navigator")
        }

        // Seed the runtime sync flag from the initial preference. If the preference
        // already disables synchronization, start in manual mode.
        narrationSyncEnabled = initialPreferences.disableSynchronization != true

        withMainContext {
            epubNavigator?.let {
                attachEpubNavigator(fragmentManager, viewGroup)
                return@withMainContext
            } // Already enabled - assume from restored state.

            EpubNavigator(
                pub,
                initialLocator,
                this@ReadiumReader,
                initialPreferences,
                fontFamilyDeclarations = fontFamilyDeclarations,
            ).apply {
                initNavigator()
                visualNavigator = this
                attachEpubNavigator(fragmentManager, viewGroup)
                setDecorationStyle(decorationStyle)
                return@withMainContext
            }
        }
    }

    suspend fun attachEpubNavigator(
        fragmentManager: FragmentManager?,
        viewGroup: ViewGroup?,
    ) {
        if (fragmentManager == null || viewGroup == null) {
            PluginLog.w(TAG, "::attachEpubNavigator: Missing fragmentManager or viewGroup")
            return
        }

        val navigator =
            visualNavigator ?: run {
                PluginLog.d(TAG, "::attachEpubNavigator: Tried to attach a non-existing epub navigator?")
                return
            }

        withMainContext {
            // Queue decorations to be applied when the epubNavigator is attached.
            decorationsUpdated()

            navigator.attachNavigator(fragmentManager, viewGroup)
        }
    }

    @OptIn(InternalReadiumApi::class)
    suspend fun pdfEnable(
        initialLocator: Locator?,
        fragmentManager: FragmentManager,
        viewGroup: ViewGroup,
        readerWidget: ReadiumReaderWidget,
    ) {
        val pub = currentPublication ?: throw Exception("Publication not opened cannot enable pdf")

        currentReaderWidget = readerWidget

        val isPdf =
            pub.conformsTo(Publication.Profile.PDF) ||
                pub.readingOrder
                    .firstOrNull()
                    ?.mediaType
                    ?.matches(MediaType.PDF) == true
        if (!isPdf) {
            throw Exception("Publication is not a PDF, cannot enable pdf navigator")
        }

        withMainContext {
            pdfNavigator?.let {
                attachPdfNavigator(fragmentManager, viewGroup)
                return@withMainContext
            }

            PdfNavigator(pub, initialLocator, this@ReadiumReader).apply {
                initNavigator()
                visualNavigator = this
                attachPdfNavigator(fragmentManager, viewGroup)
                return@withMainContext
            }
        }
    }

    suspend fun attachPdfNavigator(
        fragmentManager: FragmentManager?,
        viewGroup: ViewGroup?,
    ) {
        if (fragmentManager == null || viewGroup == null) {
            PluginLog.d(TAG, "::attachPdfNavigator: Missing fragmentManager or viewGroup")
            return
        }

        val navigator =
            pdfNavigator ?: run {
                PluginLog.d(TAG, "::attachPdfNavigator: Tried to attach a non-existing pdf navigator?")
                return
            }

        withMainContext {
            navigator.attachNavigator(fragmentManager, viewGroup)
        }
    }

    fun pdfClose() {
        currentReaderWidget = null
        visualNavigator?.dispose()
        visualNavigator = null
    }

    suspend fun pdfUpdatePreferences(preferences: FlutterPdfPreferences) {
        val navigator =
            pdfNavigator ?: run {
                PluginLog.e(TAG, "::pdfUpdatePreferences called without a pdfNavigator")
                return
            }
        navigator.updatePreferences(preferences)
    }

    fun pdfEnrichLocatorWithTocHref(locator: Locator): Locator {
        val publication = currentPublication ?: return locator
        val page = locator.locations.position ?: return locator

        // Find the last TOC entry whose "#page=N" fragment is ≤ the current page.
        val tocEntry =
            publication.tableOfContents
                .flattenChildren()
                .asSequence()
                .mapNotNull { link ->
                    val href = link.href.toString()
                    val fragment = href.substringAfterLast("#", "")
                    if (!fragment.startsWith("page=")) return@mapNotNull null
                    val tocPage = fragment.removePrefix("page=").toIntOrNull() ?: return@mapNotNull null
                    Pair(tocPage, link)
                }.filter { it.first <= page }
                .maxByOrNull { it.first }
                ?.second ?: return locator

        return locator
            .copy(title = tocEntry.title)
            .copyWithTocHref(tocEntry)
    }

    @OptIn(InternalReadiumApi::class)
    suspend fun comicEnable(
        initialLocator: Locator?,
        fragmentManager: FragmentManager,
        viewGroup: ViewGroup,
        readerWidget: ReadiumReaderWidget,
    ) {
        val pub = currentPublication ?: throw Exception("Publication not opened cannot enable comic")

        currentReaderWidget = readerWidget

        val isComic =
            pub.conformsTo(Publication.Profile.DIVINA) ||
                pub.readingOrder
                    .firstOrNull()
                    ?.mediaType
                    ?.matches(MediaType.CBZ) == true

        if (!isComic) {
            throw Exception("Publication is not a comic (CBZ/DiViNa), cannot enable comic navigator")
        }

        withMainContext {
            comicNavigator?.let {
                attachComicNavigator(fragmentManager, viewGroup)
                return@withMainContext
            }

            ComicNavigator(pub, initialLocator, this@ReadiumReader).apply {
                initNavigator()
                visualNavigator = this
                attachComicNavigator(fragmentManager, viewGroup)
                return@withMainContext
            }
        }
    }

    suspend fun attachComicNavigator(
        fragmentManager: FragmentManager?,
        viewGroup: ViewGroup?,
    ) {
        if (fragmentManager == null || viewGroup == null) {
            PluginLog.d(TAG, "::attachComicNavigator: Missing fragmentManager or viewGroup")
            return
        }

        val navigator =
            comicNavigator ?: run {
                PluginLog.d(TAG, "::attachComicNavigator: Tried to attach a non-existing comic navigator?")
                return
            }

        withMainContext {
            navigator.attachNavigator(fragmentManager, viewGroup)
        }
    }

    fun comicClose() {
        currentReaderWidget = null
        visualNavigator?.dispose()
        visualNavigator = null
    }

    fun epubClose() {
        currentReaderWidget = null
        visualNavigator?.dispose()
        visualNavigator = null
    }

    /** Close the active visual navigator, regardless of type (EPUB or PDF). */
    fun visualClose() {
        currentReaderWidget = null
        visualNavigator?.dispose()
        visualNavigator = null
    }

    /**
     * Enable the appropriate visual navigator (EPUB or PDF) based on the
     * current publication type. This replaces the separate `epubEnable` /
     * `pdfEnable` call sites in the widget so callers don't need to branch.
     */
    @OptIn(InternalReadiumApi::class)
    suspend fun visualEnable(
        initialLocator: Locator?,
        initialPreferences: FlutterEpubPreferences,
        fontFamilyDeclarations: List<ReaderFontFamily>,
        fragmentManager: FragmentManager,
        viewGroup: ViewGroup,
        readerWidget: ReadiumReaderWidget,
    ) {
        val pub =
            currentPublication ?: throw Exception("Publication not opened cannot enable visual navigator")

        // Route to the appropriate navigator. Comic check comes first: CBZ publications may
        // lack the EPUB profile even though the streamer parsed them successfully, so we must
        // not let them fall through to epubEnable (which throws for non-EPUB).
        val isPdf =
            pub.conformsTo(Publication.Profile.PDF) ||
                pub.readingOrder
                    .firstOrNull()
                    ?.mediaType
                    ?.matches(MediaType.PDF) == true

        val isComic =
            pub.conformsTo(Publication.Profile.DIVINA) ||
                pub.readingOrder
                    .firstOrNull()
                    ?.mediaType
                    ?.matches(MediaType.CBZ) == true

        when {
            isPdf -> {
                pdfEnable(initialLocator, fragmentManager, viewGroup, readerWidget)
            }

            isComic -> {
                comicEnable(initialLocator, fragmentManager, viewGroup, readerWidget)
            }

            else -> {
                epubEnable(
                    initialLocator,
                    initialPreferences,
                    fontFamilyDeclarations,
                    fragmentManager,
                    viewGroup,
                    readerWidget,
                )
            }
        }
    }

    /** Navigate backward in the active visual navigator. */
    suspend fun visualGoBackward(animated: Boolean) {
        val navigator =
            visualNavigator ?: run {
                PluginLog.d(TAG, "::visualGoBackward. Navigator not ready.")
                return
            }
        navigator.goBackward(animated)
    }

    /** Navigate forward in the active visual navigator. */
    suspend fun visualGoForward(animated: Boolean) {
        val navigator =
            visualNavigator ?: run {
                PluginLog.d(TAG, "::visualGoForward. Navigator not ready.")
                return
            }
        navigator.goForward(animated)
    }

    /** Go to the given locator in the active visual navigator. */
    suspend fun visualGoToLocator(
        locator: Locator,
        animated: Boolean,
    ) {
        val publication =
            currentPublication ?: run {
                PluginLog.e(TAG, "::visualGoToLocator called without an open publication")
                return
            }
        val toLocator = publication.normalizeLocator(locator)
        val navigator =
            visualNavigator ?: run {
                PluginLog.d(TAG, "::visualGoToLocator. Navigator not ready.")
                return
            }
        navigator.goToLocator(toLocator, animated)
    }

    suspend fun ttsEnable(ttsPrefs: FlutterTtsPreferences) {
        // Destroy any previous TTS session to prevent double playback if the
        // old navigator's engine survived a background interruption.
        ttsNavigator?.dispose()
        ttsNavigator = null

        currentPublication?.let {
            applyPageBreakBehavior(ttsPrefs)
            ttsNavigator =
                TTSNavigator(it, this@ReadiumReader, currentTextLocator.value, ttsPrefs).apply {
                    initNavigator()
                }
        } ?: throw Exception("Publication not opened cannot enable tts")
        currentTimebasedPublicationDurationMs = null
    }

    suspend fun ttsSetPreferences(ttsPrefs: FlutterTtsPreferences) {
        applyPageBreakBehavior(ttsPrefs)
        ttsNavigator?.updatePreferences(ttsPrefs)
            ?: throw Exception("TTS is not enabled, can't set preferences")
    }

    suspend fun setDecorationStyle(style: FlutterDecorationPreferences) {
        decorationStyle = style

        decorationsUpdated()
    }

    suspend fun decorationsUpdated() {
        ttsNavigator?.decorationsUpdated()
        syncAudiobookNavigator?.decorationsUpdated()
    }

    /**
     * Cached list of android tts voices.
     */
    private var availableTtsVoices: Set<AndroidTtsEngine.Voice>? = null

    /**
     * Get available tts voices
     */
    suspend fun ttsGetAvailableVoices(): Set<AndroidTtsEngine.Voice> {
        // Already loaded, return existing list.
        availableTtsVoices?.takeIf { it.isNotEmpty() }?.let { return it }

        // Get the available voices from the TTS navigator.
        // If the TTS navigator hasn't been initialized, create a dummy AndroidTtsEngine.
        availableTtsVoices = ttsNavigator?.voices ?: AndroidTtsEngine
            .invoke(
                context,
                {
                    AndroidTtsSettings(
                        Language("C"),
                        false,
                        0.0,
                        0.0,
                        mapOf(),
                    )
                },
                { language, availableVoices -> null },
                AndroidTtsPreferences(),
            )?.voices

        return availableTtsVoices ?: setOf()
    }

    fun ttsGetPreferences(): FlutterTtsPreferences? = ttsNavigator?.preferences

    suspend fun ttsSetPreferredVoice(
        voiceId: String?,
        language: String?,
    ) {
        if (voiceId == null) {
            PluginLog.w(TAG, "::ttsSetPreferredVoice - missing voiceId")
            return
        }

        if (language == null) {
            PluginLog.w(TAG, "::ttsSetPreferredVoice - missing language")
            return
        }

        ttsNavigator?.setPreferredVoice(voiceId, language)
    }

    suspend fun play(locator: Locator?) {
        val fromLocator =
            locator ?: currentReadiumTimebasedState.value.currentLocator ?: currentTextLocator.value
                ?: epubFirstVisibleElementLocator()

        PluginLog.d(TAG, "::play($locator) - fromLocator:$fromLocator")

        timebasedNavigator?.play(fromLocator)
    }

    suspend fun pause() {
        timebasedNavigator?.pause()
    }

    suspend fun resume() {
        timebasedNavigator?.resume()
    }

    suspend fun stop() {
        audiobookNavigator?.apply {
            pause()
            dispose()

            audiobookNavigator = null
        }

        val wasMOActive = isMOActive
        syncAudiobookNavigator?.apply {
            pause()
            dispose()

            syncAudiobookNavigator = null
        }
        if (wasMOActive) {
            epubEvaluateJavascript("window.flutterReadium.removeMOBreakCSS()")
        }

        ttsNavigator?.apply {
            pause()
            dispose()

            ttsNavigator = null
        }

        currentReadiumTimebasedState.value = ReadiumTimebasedState.none()
        exitNarrationMode()
    }

    /**
     * Resets narration-sync state and returns the comic overlay to its full-page view.
     * Called on stop (not pause). Distinct from [setNarrationSyncEnabled] which re-pans
     * to the last narrated panel.
     */
    fun exitNarrationMode() {
        PluginLog.d(TAG, "::exitNarrationMode")
        narrationSyncEnabled = true
        emitNarrationSyncChanged(true)
        launch {
            epubNavigator?.exitNarrationMode()
            comicNavigator?.exitNarrationMode()
        }
    }

    /**
     * Skip backwards.
     */
    suspend fun previous() {
        timebasedNavigator?.goBackward()
    }

    /**
     * Skip forwards.
     */
    suspend fun next() {
        timebasedNavigator?.goForward()
    }

    /**
     * Go to a specific locator.
     */
    suspend fun goToLocator(locator: Locator) {
        val publication =
            currentPublication ?: run {
                PluginLog.e(TAG, "::goToLocator called without a current publication")
                return
            }
        val toLocator = publication.normalizeLocator(locator)
        timebasedNavigator?.let { navigator ->
            PluginLog.d(TAG, "::goToLocator - timebased $toLocator")
            val narrationLocator =
                toLocator.copy(
                    text = Locator.Text(),
                )
            navigator.goToLocator(narrationLocator)
            // navigator.goToLocator blocks until the seek lands (see AudiobookNavigator),
            // so reflect the confirmed position in state before returning. This is what a
            // subsequent play(null) reads to resume from, closing the seek→play race.
            currentReadiumTimebasedState.value =
                currentReadiumTimebasedState.value.copyWith(currentLocator = narrationLocator)

            return
        }

        // An explicit locator jump (TOC / bookmark / search) during active narration is
        // handled by the timebasedNavigator.goToLocator branch above (narration follows the
        // jump). This branch is only reached when narration is NOT active, so a jump must not
        // enter manual mode. Page-turns (epubGoForward/epubGoBackward) do enter manual mode.
        epubGoToLocator(toLocator, true)
    }

    /**
     * Go to a progression value between 0.0 and 1.0
     */
    suspend fun goToProgression(progression: Double) {
        timebasedNavigator?.let { timebasedNavigator ->
            PluginLog.d(TAG, "::goToProgression - timebased $progression")
            timebasedNavigator.seekToProgression(progression)

            return
        }

        epubGoToProgression(progression)
    }

    suspend fun searchInPublication(query: String): Try<List<LocatorCollection>, Error> {
        val pub =
            currentPublication ?: return failure(
                Error("no publication"),
            )
        val isPdf =
            pub.conformsTo(Publication.Profile.PDF) ||
                pub.readingOrder
                    .firstOrNull()
                    ?.mediaType
                    ?.matches(MediaType.PDF) == true
        if (isPdf) {
            return failure(
                Error("PDF search is not supported on Android: kotlin-toolkit does not ship a SearchService for PDF publications."),
            )
        }
        val resultIterator =
            pub.search(query, SearchService.Options()) ?: return failure(
                Error("SearchService unavailable"),
            )
        val results = mutableListOf<LocatorCollection>()
        while (true) {
            val result = resultIterator.next()
            if (result.isFailure) break
            val collection = result.getOrNull() ?: break
            results.add(collection)
        }
        return Try.success(results.toList())
    }

    /**
     * Seek to a specific [offset] in seconds from the current position. Can be negative or positive.
     */
    suspend fun audioSeek(offset: Double) {
        val navigator =
            timebasedNavigator ?: run {
                PluginLog.w(TAG, "::audioSeek - called without an active timebase navigator")
                return
            }

        navigator.seekTo(offset)
    }

    @OptIn(InternalReadiumApi::class)
    suspend fun audioEnable(
        locator: Locator?,
        preferences: FlutterAudioPreferences,
    ) {
        _audioPreferences = preferences

        val publication =
            currentPublication ?: run {
                throw Exception("Publication not opened")
            }

        val initialLocator = locator?.let { publication.normalizeLocator(it) }

        // Handle karaoke books - by creating a pseudo audio publication from the media overlays.
        val (ap, overlays) = publication.makeSyncAudiobook()

        audiobookNavigator?.dispose()
        syncAudiobookNavigator?.dispose()
        audiobookNavigator = null
        syncAudiobookNavigator = null

        if (overlays == null) {
            PluginLog.d(TAG, "::audioEnable - plain audiobook")

            audiobookNavigator =
                AudiobookNavigator(
                    ap,
                    this@ReadiumReader,
                    initialLocator,
                    preferences,
                ).apply {
                    initNavigator()
                }
            currentTimebasedPublicationDurationMs = computePublicationDurationMs(ap.readingOrder.map { it.duration })
        } else {
            PluginLog.d(TAG, "::audioEnable - media-overlay book")
            val ail = initialLocator ?: epubNavigator?.currentLocator?.value
            syncAudiobookNavigator =
                SyncAudiobookNavigator(
                    ap,
                    overlays,
                    this@ReadiumReader,
                    ail,
                    preferences,
                ).apply {
                    initNavigator()
                }
            if (preventMOColumnBreaksActive) {
                epubEvaluateJavascript("window.flutterReadium.injectMOBreakCSS()")
            }
            currentTimebasedPublicationDurationMs = computePublicationDurationMs(ap.readingOrder.map { it.duration })
        }
    }

    suspend fun audioUpdatePreferences(preferences: FlutterAudioPreferences) {
        _audioPreferences = preferences

        val navigator =
            audiobookNavigator ?: syncAudiobookNavigator ?: run {
                PluginLog.e(TAG, "::audioUpdatePreferences called without an active audiobook navigator")
                throw Exception("Audio not enabled, cannot update preferences")
            }

        navigator.updatePreferences(preferences)
    }

    suspend fun applyDecorations(
        decorations: List<Decoration>,
        group: String,
    ) {
        val navigator = epubNavigator ?: return

        navigator.applyDecorations(decorations, group)
    }

    override fun onPageLoaded() {
        currentReaderWidget?.onPageLoaded()
    }

    override fun onPageChanged(
        pageIndex: Int,
        totalPages: Int,
        locator: Locator,
    ) {
        currentReaderWidget?.onPageChanged(pageIndex, totalPages, locator)
    }

    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        currentReaderWidget?.onExternalLinkActivated(url)
    }

    override fun onVisualCurrentLocationChanged(locator: Locator) {
        currentReaderWidget?.onVisualCurrentLocationChanged(locator)
    }

    override fun onVisualReaderIsReady() {
        currentReaderWidget?.onVisualReaderIsReady()
    }

    suspend fun epubFirstVisibleElementLocator(): Locator? {
        val navigator =
            epubNavigator ?: run {
                PluginLog.d(TAG, "::epubFirstVisibleElementLocator called without a epubNavigator")
                return null
            }

        return navigator.firstVisibleElementLocator()
    }

    suspend fun epubEvaluateJavascript(script: String): String? {
        val navigator =
            epubNavigator ?: run {
                PluginLog.d(TAG, "::epubEvaluateJavascript called without a epubNavigator")
                return null
            }

        return navigator.evaluateJavascript(script)
    }

    /**
     * Update EPUB navigator preferences.
     */
    suspend fun epubUpdatePreferences(preferences: FlutterEpubPreferences) {
        val navigator =
            epubNavigator ?: run {
                PluginLog.d(TAG, "::epubUpdatePreferences called without a epubNavigator")
                return
            }

        val newPreventBreaks = preferences.preventMOColumnBreaks ?: true
        if (isMOActive && newPreventBreaks != preventMOColumnBreaksActive) {
            if (newPreventBreaks) {
                epubEvaluateJavascript("window.flutterReadium.injectMOBreakCSS()")
            } else {
                epubEvaluateJavascript("window.flutterReadium.removeMOBreakCSS()")
            }
        }
        preventMOColumnBreaksActive = newPreventBreaks

        navigator.updatePreferences(preferences)
    }

    /**
     * Navigate backward in the EPUB navigator.
     */
    suspend fun epubGoBackward(animated: Boolean) {
        val navigator =
            visualNavigator ?: run {
                PluginLog.d(TAG, "::epubGoBackward called without a visualNavigator")
                return
            }

        enterManualModeIfNarrating("epubGoBackward")
        navigator.goBackward(animated)
    }

    /**
     * Navigate forward in the EPUB navigator.
     */
    suspend fun epubGoForward(animated: Boolean) {
        val navigator =
            visualNavigator ?: run {
                PluginLog.d(TAG, "::epubGoForward called without a visualNavigator")
                return
            }

        enterManualModeIfNarrating("epubGoForward")
        navigator.goForward(animated)
    }

    /**
     * Go to a specific locator in the EPUB navigator, this scrolls to the locator position if needed.
     */
    suspend fun epubGoToLocator(
        locator: Locator,
        animated: Boolean,
    ) {
        val publication =
            currentPublication ?: run {
                PluginLog.e(TAG, "::epubGoToLocator called without an open publication")
                return
            }

        val toLocator = publication.normalizeLocator(locator)

        val navigator =
            visualNavigator ?: run {
                PluginLog.d(TAG, "::epubGoToLocator called without a visualNavigator")
                return
            }

        navigator.goToLocator(toLocator, animated)
    }

    suspend fun epubGoToProgression(progression: Double) {
        val navigator =
            visualNavigator ?: run {
                PluginLog.d(TAG, "::epubGoToProgression called without a visualNavigator")
                return
            }

        navigator.scrollToProgression(progression)
    }

    /**
     * Sync epub to [SyncAudiobookNavigator] or [TTSNavigator].
     * Delegates to [syncVisualToLocator] for EPUB; kept for call-site compatibility.
     */
    suspend fun epubSyncToLocator(
        locator: Locator,
        animated: Boolean,
        segmentDuration: Double? = null,
    ) {
        syncVisualToLocator(locator, animated, segmentDuration)
    }

    /**
     * Routes an audio-cue sync to the active visual navigator, respecting the manual-mode gate.
     *
     * For EPUB: delegates to [EpubNavigator.syncToLocator] which also tracks [lastSyncLocator]
     * so re-enabling sync can catch up immediately.
     * For comic (CBZ / DiViNa): calls [ComicNavigator.goToLocator] directly since comics have
     * no per-word scroll logic. Highlight decorations are applied regardless of the sync flag
     * (matching the existing [disableSynchronization] behaviour for EPUB).
     *
     * Note: this only fires when the comic publication actually carries narration cues mapped
     * through [mediaOverlays]. DiViNa guided-navigation cues are parsed on Android only when
     * [Publication.hasGuidedNavigationMediaOverlays] is true and [makeSyncAudiobook] succeeds;
     * if that prerequisite is not met the [SyncAudiobookNavigator] will not be active and this
     * path is never reached.
     */
    private suspend fun syncVisualToLocator(
        locator: Locator,
        animated: Boolean,
        segmentDuration: Double? = null,
    ) {
        val epub = epubNavigator
        if (epub != null) {
            if (!narrationSyncEnabled) {
                // Manual mode: remember the cue so a later Re-sync can catch up, but don't
                // move the view. (Highlight decorations are still applied by the caller.)
                PluginLog.d(TAG, "::syncVisualToLocator - manual mode: deferring epub sync")
                epub.recordDeferredSync(locator, segmentDuration)
                return
            }
            withMainContext {
                epub.syncToLocator(locator, animated, segmentDuration)
            }
            return
        }

        val comic = comicNavigator
        if (comic != null) {
            if (!narrationSyncEnabled) {
                // Manual mode: record the cue so a later Re-sync can catch up to the
                // current page, but don't move the view.
                PluginLog.d(TAG, "::syncVisualToLocator - manual mode: deferring comic sync")
                comic.recordDeferredSync(locator)
                return
            }
            withMainContext {
                comic.syncToLocator(locator, animated, segmentDuration)
            }
        }
    }

    /** Shared by [ttsEnable] and [ttsSetPreferences] — both can set this. */
    private fun applyPageBreakBehavior(ttsPrefs: FlutterTtsPreferences) {
        pageBreakIteratorFactory?.pageBreakBehavior = ttsPrefs.pageBreakBehavior ?: PageBreakBehavior.READ_AS_IS
    }

    /**
     * Get all cssSelectors for an EPUB file.
     * Note: These only includes text elements, so body, page breaks etc are not included.
     */
    suspend fun epubGetAllDocumentCssSelectors(href: Url): List<String> {
        val cssSelectorMap = currentPublicationCssSelectorMap ?: mutableMapOf()
        currentPublicationCssSelectorMap = cssSelectorMap

        val cleanHref = href.cleanHref()
        return cssSelectorMap.getOrPut(cleanHref) {
            currentPublication?.findAllCssSelectors(
                cleanHref,
            ) ?: listOf()
        }
    }

    /**
     * Emit reader status update to the flutter layer.
     */
    fun emitReaderStatusUpdate(statusUpdate: ReadiumReaderStatus) {
        readiumReaderStatusEventChannel?.sendEvent(statusUpdate)
    }

    /**
     * Emit an error event to the flutter layer.
     */
    fun emitError(error: ReadiumError) {
        errorChannel?.sendEvent(error)
    }

    /**
     * Emit an external playback command received from system media controls.
     */
    fun emitExternalPlaybackCommand(command: ReadiumExternalPlaybackCommand) {
        externalPlaybackCommandEventChannel?.sendEvent(command)
    }

    /**
     * Emit text locator to the flutter layer
     */
    fun emitTextLocatorUpdate(locator: Locator) {
        textLocatorEventChannel?.sendEvent(locator)

        currentTextLocator.value = locator
    }

    /**
     * Emit narration-sync state change to the Flutter layer.
     */
    fun emitNarrationSyncChanged(enabled: Boolean) {
        narrationSyncEventChannel?.sendEvent(enabled)
    }

    /**
     * Returns `true` when a timed-based (narrating) navigator is active and playing.
     * Used to decide whether explicit user navigation should trigger manual mode.
     */
    private fun isNarrationActive(): Boolean = timebasedNavigator != null

    /**
     * If narration is active, enters manual mode and emits the state change.
     *
     * Called from explicit page navigation (`goForward`/`goBackward`) and from in-reader user
     * gestures: the Flutter `reader_widget.dart` `Listener` detects a swipe / edge-tap and calls
     * the reader-view channel `"notifyUserNavigation"`, which routes here. Those pointer events
     * fire only for genuine user interaction (audio-driven page turns are programmatic and never
     * reach the Listener), so they are a clean "user took control" signal.
     */
    fun enterManualModeIfNarrating(callSite: String) {
        if (!isNarrationActive()) return
        if (!narrationSyncEnabled) return
        PluginLog.d(TAG, "::$callSite - user navigation detected while narrating; entering manual mode")
        narrationSyncEnabled = false
        emitNarrationSyncChanged(false)
    }

    /**
     * Enable or disable narration sync at runtime.
     *
     * When `true`: clears manual mode and immediately re-positions the visual reader to
     * the current audio cue (catch-up). When `false`: enters manual mode — the visual
     * reader stops following audio cues, but audio keeps playing.
     *
     * This is the single unified runtime sync gate. [FlutterEpubPreferences.disableSynchronization]
     * only seeds it at [epubEnable] and flips it on a preference transition (see
     * [EpubNavigator.updatePreferences]); all gating for both EPUB and comic cue sync goes through
     * [narrationSyncEnabled] in [syncVisualToLocator].
     */
    fun setNarrationSyncEnabled(enabled: Boolean) {
        PluginLog.d(TAG, "::setNarrationSyncEnabled enabled=$enabled")
        narrationSyncEnabled = enabled
        if (enabled) {
            // Re-sync to the last known audio cue immediately.
            launch {
                val epub = epubNavigator
                if (epub != null) {
                    epub.resyncAfterManualMode()
                    return@launch
                }
                val comic = comicNavigator
                if (comic != null) {
                    // Page-level catch-up: jump to the last audio-cue page immediately.
                    // Panel-level framing is Phase 2 (no panel pan/zoom API on Android yet —
                    // see docs/parity/native-divina-sync-handoff.md).
                    comic.resyncAfterManualMode()
                    return@launch
                }
            }
        }
        emitNarrationSyncChanged(enabled)
    }
}
