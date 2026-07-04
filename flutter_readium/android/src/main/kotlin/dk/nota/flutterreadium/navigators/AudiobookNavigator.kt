package dk.nota.flutterreadium.navigators

import android.os.Bundle
import dk.nota.flutterreadium.ControlPanelInfoType
import dk.nota.flutterreadium.FlutterAudioPreferences
import dk.nota.flutterreadium.PluginLog
import dk.nota.flutterreadium.PluginMediaServiceFacade
import dk.nota.flutterreadium.PublicationError
import dk.nota.flutterreadium.ReadiumReader
import dk.nota.flutterreadium.cleanHref
import dk.nota.flutterreadium.copyWithTimeFragment
import dk.nota.flutterreadium.copyWithTocHref
import dk.nota.flutterreadium.events.ReadiumError
import dk.nota.flutterreadium.events.ReadiumErrorDetails
import dk.nota.flutterreadium.flattenChildren
import dk.nota.flutterreadium.throttleLatest
import dk.nota.flutterreadium.time
import dk.nota.flutterreadium.timeWithDuration
import dk.nota.flutterreadium.withMainContext
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.adapter.exoplayer.audio.ExoPlayerEngineProvider
import org.readium.adapter.exoplayer.audio.ExoPlayerNavigatorFactory
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.adapter.exoplayer.audio.ExoPlayerSettings
import org.readium.navigator.media.audio.AudioNavigator
import org.readium.r2.navigator.extensions.normalizeLocator
import org.readium.r2.navigator.extensions.time
import org.readium.r2.shared.DelicateReadiumApi
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.DebugError
import org.readium.r2.shared.util.Error
import org.readium.r2.shared.util.getOrElse
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

private const val TAG = "AudioNavigator"

const val CURRENT_TIMEBASE_LOCATOR_KEY = "currentTimebaseLocator"

const val AUDIO_PREFERENCES_KEY = "audioPreferencesKey"

/**
 * Navigator for pure Audiobook publications using Readium's AudioNavigator.
 */
@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
open class AudiobookNavigator(
    publication: Publication,
    timebasedListener: TimebasedListener,
    initialLocator: Locator?,
    private var preferences: FlutterAudioPreferences,
) : TimebasedNavigator<AudioNavigator.Playback>(publication, timebasedListener, initialLocator) {
    /**
     * The AudioNavigator provided by Readium..
     */
    protected var audioNavigator: AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences>? = null

    /**
     * The MediaServiceFacade to manage MediaSession interactions, notifications, etc.
     */
    protected var mediaServiceFacade: PluginMediaServiceFacade? = null

    /**
     * Recovery loop for retryable audio streaming failures. Non-null while a recovery
     * attempt sequence is in flight.
     */
    private var recoveryJob: Job? = null

    /**
     * Snapshotted at construction time from [ReadiumReader.audioRecoveryPolicy] — per the
     * plugin's "no mid-stream reconfiguration" contract, a policy change via
     * `setAudioRecoveryPolicy` only takes effect for the next-opened publication.
     */
    private val recoveryPolicy = ReadiumReader.audioRecoveryPolicy

    /**
     * Stall watchdog: fires when playback intent is on but the offset hasn't advanced
     * within [AudioRecoveryPolicy.stallTimeoutSeconds]. Non-null whenever a navigator is
     * active; cancelled/restarted on rebuild.
     */
    private var stallWatchdogJob: Job? = null

    /**
     * Explicit terminal-failure latch. Must not be inferred from the last emitted
     * TimebasedState: state churn during a rebuild can otherwise cause a stale
     * "not failed" read right after a terminal failure was emitted.
     */
    private var isTerminallyFailed: Boolean = false

    /**
     * While a recovery attempt is in flight, the rebuilt navigator's own Buffering/Ready
     * state churn is suppressed - only the pinned Loading state (already emitted when the
     * attempt started) is visible to clients.
     */
    private var isRecovering: Boolean = false

    private fun buildNavigatorFactory(): ExoPlayerNavigatorFactory? =
        ExoPlayerNavigatorFactory(
            publication,
            ExoPlayerEngineProvider(ReadiumReader.application, metadataProvider = { pub ->
                DatabaseMediaMetadataFactory(
                    publication = publication,
                    trackCount = pub.readingOrder.size,
                    controlPanelInfoType =
                        preferences.controlPanelInfoType
                            ?: ControlPanelInfoType.STANDARD,
                )
            }),
        )

    override suspend fun initNavigator() {
        if (!publication.conformsTo(Publication.Profile.AUDIOBOOK)) {
            PluginLog.e(
                TAG,
                "::initNavigator - doesn't conform to audiobook profile - ${publication.metadata.conformsTo}",
            )
            throw Exception("Publication doesn't conform to audiobook profile")
        }

        if (publication.readingOrder.isEmpty()) {
            PluginLog.e(TAG, "::initNavigator - missing reading order")
            throw Exception("Publication is missing its reading order, cannot be opened as an audiobook")
        }

        if (publication.readingOrder.any { it.duration == 0.0 }) {
            PluginLog.e(
                TAG,
                "::initNavigator - has at least one readium order item with duration = 0",
            )
            throw Exception("Publication has at least one readium order item with duration = 0")
        }

        // Create AudioNavigatorFactory
        val navigatorFactory = buildNavigatorFactory()

        if (navigatorFactory == null) {
            // TODO: Better Error handling, if the book isn't an audiobook the factory is null.
            PluginLog.e(TAG, "::initNavigator - Couldn't create AudioNavigatorFactory")
            throw Exception("Couldn't create AudioNavigatorFactory")
        }

        withMainContext {
            audioNavigator =
                navigatorFactory
                    .createNavigator(
                        this@AudiobookNavigator.initialLocator,
                        preferences.toExoPlayerPreferences(),
                    ).getOrElse { error ->
                        PluginLog.e(TAG, "::initNavigator - $error")
                        throw Exception(PublicationError.invoke(error).message)
                    }

            setupNavigatorListeners()
        }
    }

    /**
     * Tears down and rebuilds the underlying [AudioNavigator] at [locator]. Required for
     * recovery: upstream never replaces a failed player item for the same resource index
     * (`AudioEngine`/`AudioNavigator` expose no re-prepare API, only `close()`), so the only
     * way to retry playback is a fresh navigator instance, per `AudioNavigatorFactory`.
     *
     * Returns the new navigator, or null if the factory / rebuild step failed.
     */
    private suspend fun rebuildNavigator(locator: Locator?): AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences>? {
        val navigatorFactory =
            buildNavigatorFactory() ?: run {
                PluginLog.e(TAG, "::rebuildNavigator - Couldn't create AudioNavigatorFactory")
                return null
            }

        return withMainContext {
            audioNavigator?.close()
            mediaServiceFacade?.closeSession()

            val newNavigator =
                navigatorFactory
                    .createNavigator(locator, preferences.toExoPlayerPreferences())
                    .getOrElse { error ->
                        PluginLog.e(TAG, "::rebuildNavigator - $error")
                        null
                    } ?: return@withMainContext null

            audioNavigator = newNavigator
            setupNavigatorListeners()

            try {
                val mediaSession =
                    mediaServiceFacade ?: PluginMediaServiceFacade(ReadiumReader.application).also { mediaServiceFacade = it }
                mediaSession.openSession(newNavigator) { isPlaying -> onIsPlayingFromPlayer(isPlaying) }
            } catch (e: Exception) {
                PluginLog.e(TAG, "::rebuildNavigator - failed to reopen MediaSession: ${e.message}")
            }

            newNavigator
        }
    }

    private fun initMediaServiceFacade() {
        mediaServiceFacade =
            PluginMediaServiceFacade(ReadiumReader.application).apply {
                session
                    .flatMapLatest { it?.navigator?.playback ?: MutableStateFlow(null) }
                    .mapNotNull { playback -> playback?.state as? AudioNavigator.State }
                    .distinctUntilChanged()
                    .onEach { state ->
                        when (state) {
                            AudioNavigator.State.Ready, AudioNavigator.State.Buffering -> {
                                // Do nothing
                            }

                            is AudioNavigator.State.Ended -> {
                                PluginLog.d(
                                    TAG,
                                    "::initNavigator - playback ended, stopping navigator.",
                                )
                                stopMediaServiceFacade()
                            }

                            is AudioNavigator.State.Failure<*> -> {
                                PluginLog.e(TAG, "::initNavigator - failure: ${state.error}")
                                // onPlaybackError(state.error)
                            }
                        }
                    }.launchIn(this@AudiobookNavigator)
            }
    }

    override suspend fun play(fromLocator: Locator?) {
        // A client-initiated retry after terminal failure: the failed player is never
        // reusable (no re-prepare API), so rebuild fresh at the requested/last locator.
        if (isTerminallyFailed) {
            PluginLog.d(TAG, "::play - retrying after terminal failure")
            isTerminallyFailed = false
            recoveryJob?.cancel()
            recoveryJob = null

            val resumeLocator = fromLocator ?: state[CURRENT_TIMEBASE_LOCATOR_KEY] as? Locator
            val navigator =
                rebuildNavigator(resumeLocator) ?: run {
                    PluginLog.e(TAG, "::play - rebuild failed, cannot retry")
                    return
                }
            withMainContext { navigator.play() }
            return
        }

        withMainContext {
            if (fromLocator != null) {
                goToLocator(fromLocator)
            }

            try {
                val navigator = ensureNavigatorWithOpenMediaSession()
                navigator.play()
            } catch (e: Exception) {
                PluginLog.e(TAG, "::play - error opening MediaSession: ${e.message}")
                return@withMainContext
            }
        }
    }

    override suspend fun pause() {
        val navigator = ensureNavigator()

        withMainContext {
            navigator.pause()
        }
    }

    override suspend fun resume() {
        val navigator = ensureNavigator()

        withMainContext {
            // TODO: Do we need to check if already playing?
            navigator.play()
        }
    }

    override suspend fun goBackward() {
        val navigator = ensureNavigator()

        withMainContext {
            navigator.skip((-preferences.seekInterval).seconds)
        }
    }

    override suspend fun goForward() {
        val navigator = ensureNavigator()

        withMainContext {
            navigator.skip((preferences.seekInterval).seconds)
        }
    }

    @OptIn(InternalReadiumApi::class)
    override suspend fun goToLocator(locator: Locator) {
        val navigator = ensureNavigator()

        withMainContext {
            val itemIndex =
                navigator.readingOrder.items
                    .indexOfFirst { it.href == locator.href }
                    .takeIf { it > -1 }

            if (itemIndex == null) {
                PluginLog.e(
                    TAG,
                    "::goToLocator - ${locator.href} not found in navigator's readingOrder",
                )
                return@withMainContext
            }

            val item = navigator.readingOrder.items[itemIndex]
            val timeOffset = locator.locations.timeWithDuration(item.duration)
            if (timeOffset == null) {
                PluginLog.w(
                    TAG,
                    "::goToLocator - couldn't find timeOffset from starting file over.",
                )
            }
            navigator.skipTo(itemIndex, timeOffset ?: Duration.ZERO)
            return@withMainContext
        }
    }

    override suspend fun seekTo(offset: Double) {
        val navigator = ensureNavigator()

        withMainContext {
            navigator.skip(offset.seconds)
        }
    }

    @OptIn(DelicateReadiumApi::class, InternalReadiumApi::class)
    override suspend fun seekToProgression(progression: Double): Boolean {
        if (progression !in 0.0..1.0) {
            PluginLog.d(
                TAG,
                "::seekToProgression - progression $progression is not between 0.0 and 1.0",
            )
            return false
        }

        return withMainContext {
            val navigator = ensureNavigator()
            val player = navigator.asMedia3Player()

            val currentLocator = navigator.currentLocator.value

            // Find duration of the current item.
            // First try to get it from the player, because it is more precise, if that fails, get it from the navigator's reading order.
            val duration =
                player.duration.milliseconds.inWholeSeconds.takeIf {
                    // player.duration is -9223372036854775 when the duration is unknown, so we check if it's a positive number before using
                    it > 0
                }
                    ?: navigator.readingOrder.items
                        .firstOrNull { it.href == currentLocator.href }
                        ?.duration
                        ?.inWholeSeconds
                    ?: 0

            PluginLog.w(TAG, "::seekToProgression - couldn't find duration of current item, defaulting to 0")

            val timeOffset = duration * progression

            val locator =
                publication
                    .normalizeLocator(currentLocator)
                    .copyWithTimeFragment(timeOffset)

            PluginLog.d(
                TAG,
                "::seekToProgression - navigate to ${locator.href} @ ${locator.locations.time}",
            )

            navigator.go(locator)

            return@withMainContext true
        }
    }

    private suspend fun ensureNavigator(): AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences> {
        if (audioNavigator == null) initNavigator()
        return audioNavigator!!
    }

    private suspend fun ensureNavigatorWithOpenMediaSession(): AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences> {
        return withMainContext {
            val navigator = ensureNavigator()
            try {
                if (mediaServiceFacade == null) {
                    PluginLog.d(TAG, "::navigatorWithOpenMediaSession - init MediaServiceFacade")
                    initMediaServiceFacade()
                }

                val mediaSession = mediaServiceFacade!!
                if (mediaSession.session.value == null) {
                    PluginLog.d(TAG, "::navigatorWithOpenMediaSession - open session")
                    mediaSession.openSession(navigator) { isPlaying ->
                        onIsPlayingFromPlayer(isPlaying)
                    }
                }
            } catch (e: Exception) {
                PluginLog.e(
                    TAG,
                    "::navigatorWithOpenMediaSession - failed to open MediaSession: $e",
                )
            }

            return@withMainContext navigator
        }
    }

    /**
     * Stop the current audioNavigator. This is needed because we have to restart it when navigating.
     */
    private suspend fun stopAudioNavigator() {
        withMainContext {
            audioNavigator?.let { navigator ->
                // Save currentLocator.
                initialLocator = navigator.currentLocator.value
            }

            stopMediaServiceFacade()

            audioNavigator?.close()
            audioNavigator = null
        }
    }

    private suspend fun stopMediaServiceFacade() {
        withMainContext {
            mediaServiceFacade?.closeSession()
            mediaServiceFacade = null
        }
    }

    /**
     * Updates Audio preferences, does not override current preferences if props are null
     */
    suspend fun updatePreferences(prefs: FlutterAudioPreferences) {
        preferences += prefs

        val navigator =
            audioNavigator ?: run {
                PluginLog.d(TAG, "::updatePreferences - called without navigator")
                return
            }

        withMainContext {
            navigator.submitPreferences(preferences.toExoPlayerPreferences())
        }
    }

    override fun setupNavigatorListeners() {
        val navigator =
            audioNavigator ?: run {
                PluginLog.e(TAG, "::setupNavigatorListeners - navigator is null")
                return
            }

        startStallWatchdog(navigator)

        // Listen to state changes
        navigator.playback
            .throttleLatest(100.milliseconds)
            .distinctUntilChangedBy { pb ->
                "${pb.state}|${pb.playWhenReady}"
            }.onEach { pb ->
                onPlaybackStateChanged(pb)
            }.launchIn(this)
            .let { jobs.add(it) }

        // Handle buffered changes
        navigator.playback
            .throttleLatest(250.milliseconds)
            .distinctUntilChangedBy { pb -> pb.buffered }
            .onEach { pb ->
                timebaseListener.onTimebasedBufferChanged(pb.buffered)
            }.launchIn(this)
            .let { jobs.add(it) }

        // Handle current locator changes
        navigator.currentLocator
            .throttleLatest(100.milliseconds)
            .distinctUntilChanged()
            .onEach { locator ->
                onCurrentLocatorChanges(locator)
                state[CURRENT_TIMEBASE_LOCATOR_KEY] = locator
            }.launchIn(this)
            .let { jobs.add(it) }

        navigator.settings
            .onEach { s ->
                PluginLog.d(TAG, "::setupNavigatorListeners - AudioNavigator settings changed: $s")
            }.launchIn(this)
            .let { jobs.add(it) }
    }

    @OptIn(InternalReadiumApi::class)
    override fun onCurrentLocatorChanges(locator: Locator) {
        var emittingLocator = locator

        locator.locations.time?.let { time ->
            var matchedTocItem: Link? = null
            val cleanHref = locator.href.cleanHref().path
            for (link in publication.tableOfContents.flattenChildren().filter {
                it.href
                    .resolve()
                    .cleanHref()
                    .path == cleanHref
            }) {
                val tocTime = link.href.time ?: continue
                if (tocTime > time) {
                    break
                }
                matchedTocItem = link
            }

            matchedTocItem?.href?.resolve()?.let {
                emittingLocator = emittingLocator.copyWithTocHref(it)
            }
        }

        super.onCurrentLocatorChanges(emittingLocator)
    }

    override fun onPlaybackStateChanged(pb: AudioNavigator.Playback) {
        when (pb.state) {
            is AudioNavigator.State.Failure<*> -> {
                // Latched terminal failure: once emitted, further failures are noise
                // from the (already torn down) navigator - ignore until play() retries.
                if (isTerminallyFailed) return

                val audioState = pb.state as AudioNavigator.State.Failure<*>
                val error = audioState.error

                PluginLog.e(
                    TAG,
                    "::onPlaybackStateChanged - audio error: Message=${error.message} cause=${error.cause}",
                )

                when (val action = error.audioStreamAction()) {
                    AudioStreamErrorAction.Ignore -> {
                        PluginLog.d(TAG, "::onPlaybackStateChanged - ignoring non-fatal audio error")
                    }

                    AudioStreamErrorAction.Retry -> {
                        startRecovery(error, terminalCode = "AudioStreamNetworkError")
                    }

                    is AudioStreamErrorAction.Fail -> {
                        val href = (state[CURRENT_TIMEBASE_LOCATOR_KEY] as? Locator ?: initialLocator)?.href?.toString()
                        enterTerminalFailure(error, code = action.code, href = href, httpStatus = error.audioStreamHttpStatus())
                    }
                }
            }

            else -> {
                // Suppress the rebuilt navigator's own Buffering/Ready churn while a
                // recovery attempt is in flight - only the pinned Loading state (already
                // emitted by startRecovery) should reach clients.
                if (isRecovering) return
                super.onPlaybackStateChanged(pb)
            }
        }
    }

    /**
     * Bounded exponential-backoff recovery loop for a retryable audio streaming failure.
     * Mirrors iOS's `FlutterAudioNavigator._recoveryTask`: per attempt, emits an
     * informational `AudioStreamRetry` error event and pins the timebased state to Loading,
     * then rebuilds the navigator at the last known locator and verifies playback time
     * actually advances (state alone is not a reliable recovery signal). Exhausting all
     * attempts enters the terminal failure state.
     *
     * @param terminalCode Code to use if recovery exhausts its attempts, carried through
     * from how [error] was originally classified (e.g. `AudioStreamNetworkError` for a
     * classified network error, or a stall-specific code) - not the generic
     * `AudioStreamFailed` fallback.
     */
    private fun startRecovery(
        error: Error,
        terminalCode: String,
    ) {
        if (recoveryJob != null) return // recovery already in progress

        val resumeLocator = state[CURRENT_TIMEBASE_LOCATOR_KEY] as? Locator ?: initialLocator
        val href = resumeLocator?.href?.toString() ?: "unknown"

        recoveryJob =
            launch {
                isRecovering = true
                try {
                    for (attempt in 1..recoveryPolicy.maxAttempts) {
                        ReadiumReader.emitError(
                            ReadiumError(
                                message = error.message,
                                code = "AudioStreamRetry",
                                data =
                                    ReadiumErrorDetails(
                                        href = href,
                                        attempt = attempt,
                                        maxAttempts = recoveryPolicy.maxAttempts,
                                    ),
                            ),
                        )
                        timebaseListener.onTimebasedPlaybackStateChanged(TimebasedState.Loading)

                        delay(recoveryPolicy.delayMillis(forAttempt = attempt))
                        if (!isActive) return@launch

                        val navigator = rebuildNavigator(resumeLocator)
                        if (navigator != null) {
                            withMainContext { navigator.play() }

                            if (playbackAdvanced(navigator, withinMillis = 5_000)) {
                                return@launch // recovered - regular state emissions resume
                            }
                        }
                    }

                    enterTerminalFailure(error, code = terminalCode, href = href)
                } finally {
                    isRecovering = false
                    recoveryJob = null
                }
            }
    }

    /**
     * True once [offsetAdvanced] within [withinMillis]. Being in a Ready/playing state
     * alone is not a reliable recovery signal.
     */
    private suspend fun playbackAdvanced(
        navigator: AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences>,
        withinMillis: Long,
    ): Boolean {
        val startOffset = navigator.playback.value.offset
        val deadline = System.currentTimeMillis() + withinMillis

        while (System.currentTimeMillis() < deadline && isActive) {
            if (offsetAdvanced(navigator, startOffset)) return true
            if (navigator.playback.value.state is AudioNavigator.State.Failure<*>) {
                return false
            }
            delay(500)
        }
        return false
    }

    /**
     * True when [navigator] is `Ready`, playback is intended (`playWhenReady`), and its
     * offset has moved past `sinceOffset` by more than 100ms. Shared by [playbackAdvanced]
     * (post-rebuild recovery verification) and [startStallWatchdog] (stall detection) so
     * both agree on what "playback is actually progressing" means.
     */
    private fun offsetAdvanced(
        navigator: AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences>,
        sinceOffset: Duration,
    ): Boolean {
        val playback = navigator.playback.value
        return playback.state is AudioNavigator.State.Ready &&
            playback.playWhenReady &&
            playback.offset > sinceOffset + 100.milliseconds
    }

    /**
     * Stall watchdog: today's recovery is error-driven only, so a *throttled* (not
     * dropped) connection that keeps bytes trickling in never errors and playback sits in
     * Buffering/Loading forever. This polls the offset once a second and, if playback
     * intent is on (`playWhenReady`) but the offset hasn't advanced within
     * [AudioRecoveryPolicy.stallTimeoutSeconds], synthesizes a retryable error into the
     * same [startRecovery] path a real playback error would take.
     *
     * Skips while already recovering/terminally failed, or while playback isn't intended
     * (paused/ended) - those aren't stalls. Cancelled and restarted whenever the navigator
     * is rebuilt (called from [setupNavigatorListeners]).
     */
    private fun startStallWatchdog(navigator: AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences>) {
        stallWatchdogJob?.cancel()
        stallWatchdogJob =
            launch {
                var lastAdvanceOffset = navigator.playback.value.offset
                var deadline = System.currentTimeMillis() + (recoveryPolicy.stallTimeoutSeconds * 1000).toLong()

                while (isActive) {
                    delay(1_000)

                    if (isRecovering || isTerminallyFailed) {
                        lastAdvanceOffset = navigator.playback.value.offset
                        deadline = System.currentTimeMillis() + (recoveryPolicy.stallTimeoutSeconds * 1000).toLong()
                        continue
                    }

                    val playback = navigator.playback.value
                    if (!playback.playWhenReady || playback.state !is AudioNavigator.State.Ready) {
                        // Not intending to play right now (paused/ended/buffering-but-not-ready
                        // in a way already handled elsewhere) - not a stall, reset the window.
                        lastAdvanceOffset = playback.offset
                        deadline = System.currentTimeMillis() + (recoveryPolicy.stallTimeoutSeconds * 1000).toLong()
                        continue
                    }

                    if (offsetAdvanced(navigator, lastAdvanceOffset)) {
                        lastAdvanceOffset = playback.offset
                        deadline = System.currentTimeMillis() + (recoveryPolicy.stallTimeoutSeconds * 1000).toLong()
                        continue
                    }

                    if (System.currentTimeMillis() >= deadline) {
                        PluginLog.w(
                            TAG,
                            "::startStallWatchdog - offset hasn't advanced in ${recoveryPolicy.stallTimeoutSeconds}s, synthesizing retryable error",
                        )
                        startRecovery(
                            DebugError("Playback stalled: offset didn't advance within ${recoveryPolicy.stallTimeoutSeconds}s"),
                            terminalCode = "AudioStreamNetworkError",
                        )
                        return@launch // startRecovery owns the retry loop; a fresh watchdog starts on rebuild
                    }
                }
            }
    }

    /**
     * Terminal failure: stop playback, emit the terminal error event + Failure state once,
     * then latch. `isTerminallyFailed` is an explicit flag (not inferred from the last
     * emitted state) so that state churn from a torn-down navigator can't un-latch it.
     */
    private fun enterTerminalFailure(
        error: Error,
        code: String,
        href: String? = null,
        httpStatus: Int? = null,
    ) {
        if (isTerminallyFailed) return
        isTerminallyFailed = true
        stallWatchdogJob?.cancel()
        stallWatchdogJob = null

        PluginLog.e(TAG, "::enterTerminalFailure - [$code] ${error.message}")

        launch { withMainContext { audioNavigator?.close() } }

        ReadiumReader.emitError(
            ReadiumError(
                message = error.message,
                code = code,
                data = ReadiumErrorDetails(href = href, httpStatus = httpStatus),
            ),
        )
        timebaseListener.onTimebasedPlaybackStateChanged(TimebasedState.Failure)
    }

    override fun storeState(): Bundle =
        Bundle().apply {
            putString(
                CURRENT_TIMEBASE_LOCATOR_KEY,
                (state[CURRENT_TIMEBASE_LOCATOR_KEY] as? Locator)?.toJSON()?.toString(),
            )

            putString(
                AUDIO_PREFERENCES_KEY,
                FlutterAudioPreferences.toJSON(preferences).toString(),
            )
        }

    override fun dispose() {
        recoveryJob?.cancel()
        recoveryJob = null
        stallWatchdogJob?.cancel()
        stallWatchdogJob = null

        super.dispose()

        launch {
            stopAudioNavigator()
        }
    }

    companion object {
        fun restoreState(
            publication: Publication,
            listener: TimebasedListener,
            state: Bundle,
        ): AudiobookNavigator {
            val locator =
                state
                    .getString(CURRENT_TIMEBASE_LOCATOR_KEY)
                    ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            val preferences =
                state
                    .getString(AUDIO_PREFERENCES_KEY)
                    ?.let { json -> FlutterAudioPreferences.fromJSON(json) }
                    ?: FlutterAudioPreferences()

            return AudiobookNavigator(publication, listener, locator, preferences)
        }
    }
}
