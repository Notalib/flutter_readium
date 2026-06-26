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
import dk.nota.flutterreadium.flattenChildren
import dk.nota.flutterreadium.throttleLatest
import dk.nota.flutterreadium.time
import dk.nota.flutterreadium.timeWithDuration
import dk.nota.flutterreadium.withMainContext
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.onEach
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
import org.readium.r2.shared.util.getOrElse
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

private const val TAG = "AudioNavigator"

const val currentTimebaseLocatorKey = "currentTimebaseLocator"

const val audioPreferencesKey = "audioPreferencesKey"

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
        val navigatorFactory =
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
                state[currentTimebaseLocatorKey] = locator
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
                val audioState = pb.state as AudioNavigator.State.Failure<*>
                val error = audioState.error

                PluginLog.e(
                    TAG,
                    "::onPlaybackStateChanged - audio error: Message=${error.message} cause=${error.cause}",
                )

                timebaseListener.onTimebasedPlaybackStateChanged(TimebasedState.Failure)
                timebaseListener.onTimebasedPlaybackFailure(
                    PublicationError.invoke(error),
                )
            }

            else -> {
                super.onPlaybackStateChanged(pb)
            }
        }
    }

    override fun storeState(): Bundle =
        Bundle().apply {
            putString(
                currentTimebaseLocatorKey,
                (state[currentTimebaseLocatorKey] as? Locator)?.toJSON()?.toString(),
            )

            putString(
                audioPreferencesKey,
                FlutterAudioPreferences.toJSON(preferences).toString(),
            )
        }

    override fun dispose() {
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
                    .getString(currentTimebaseLocatorKey)
                    ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            val preferences =
                state
                    .getString(audioPreferencesKey)
                    ?.let { json -> FlutterAudioPreferences.fromJSON(json) }
                    ?: FlutterAudioPreferences()

            return AudiobookNavigator(publication, listener, locator, preferences)
        }
    }
}
