package dk.nota.flutter_readium.navigators

import android.os.Bundle
import android.util.Log
import dk.nota.flutter_readium.ControlPanelInfoType
import dk.nota.flutter_readium.FlutterAudioPreferences
import dk.nota.flutter_readium.PluginMediaServiceFacade
import dk.nota.flutter_readium.PublicationError
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.cleanHref
import dk.nota.flutter_readium.copyWithTimeFragment
import dk.nota.flutter_readium.copyWithTocHref
import dk.nota.flutter_readium.flattenChildren
import dk.nota.flutter_readium.progression
import dk.nota.flutter_readium.throttleLatest
import dk.nota.flutter_readium.time
import dk.nota.flutter_readium.withScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.adapter.exoplayer.audio.ExoPlayerEngineProvider
import org.readium.adapter.exoplayer.audio.ExoPlayerNavigatorFactory
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.adapter.exoplayer.audio.ExoPlayerSettings
import org.readium.navigator.media.audio.AudioNavigator
import org.readium.r2.navigator.extensions.time
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.getOrElse
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
    private var preferences: FlutterAudioPreferences
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
            Log.e(
                TAG,
                "::initNavigator - doesn't conform to audiobook profile - ${publication.metadata.conformsTo}"
            )
            throw Exception("Publication doesn't conform to audiobook profile")
        }

        if (publication.readingOrder.isEmpty()) {
            Log.e(TAG, "::initNavigator - missing reading order")
            throw Exception("Publication is missing its reading order, cannot be opened as an audiobook")
        }

        if (publication.readingOrder.any { it.duration == 0.0 }) {
            Log.e(TAG, "::initNavigator - has at least one readium order item with duration = 0")
            throw Exception("Publication has at least one readium order item with duration = 0")
        }

        // Create AudioNavigatorFactory
        val navigatorFactory = ExoPlayerNavigatorFactory(
            publication,
            ExoPlayerEngineProvider(ReadiumReader.application, metadataProvider = { pub ->
                DatabaseMediaMetadataFactory(
                    publication = publication,
                    trackCount = pub.readingOrder.size,
                    controlPanelInfoType = preferences.controlPanelInfoType
                        ?: ControlPanelInfoType.STANDARD
                )
            })
        )

        if (navigatorFactory == null) {
            // TODO: Better Error handling, if the book isn't an audiobook the factory is null.
            Log.e(TAG, ":initNavigator - Couldn't create AudioNavigatorFactory")
            throw Exception("Couldn't create AudioNavigatorFactory")
        }

        mainScope.async {
            audioNavigator = navigatorFactory.createNavigator(
                this@AudiobookNavigator.initialLocator,
                preferences.toExoPlayerPreferences()
            ).getOrElse { error ->
                Log.e(TAG, ":initNavigator - $error")
                throw Exception(PublicationError.invoke(error).message)
            }

            mediaServiceFacade = PluginMediaServiceFacade(ReadiumReader.application).apply {
                session
                    .flatMapLatest { it?.navigator?.playback ?: MutableStateFlow(null) }
                    .onEach { playback ->
                        when (val state = (playback?.state as? AudioNavigator.State)) {
                            null, AudioNavigator.State.Ready, AudioNavigator.State.Buffering -> {
                                // Do nothing
                            }

                            is AudioNavigator.State.Ended -> {
                                mediaServiceFacade?.closeSession()
                            }

                            is AudioNavigator.State.Failure<*> -> {
                                Log.e(TAG, "AudioNavigator failure: ${state.error}")
                                //onPlaybackError(state.error)
                            }
                        }
                    }.launchIn(mainScope)
            }

            setupNavigatorListeners()
        }.await()
    }

    override suspend fun play(fromLocator: Locator?) {
        val navigator = audioNavigator ?: run {
            Log.e(TAG, "::play called without an active navigator")
            return
        }

        withScope(mainScope) {
            if (fromLocator != null) {
                goToLocator(fromLocator)
            }

            try {
                Log.d(TAG, "Opening MediaSession")
                mediaServiceFacade?.openSession(audioNavigator!!)
            } catch (e: Exception) {
                Log.e(TAG, "Error opening MediaSession: ${e.message}")
                navigator.close()
                return@withScope
            }

            navigator.play()
        }
    }

    override suspend fun pause() {
        val navigator = audioNavigator ?: run {
            Log.e(TAG, "::pause called without an active navigator")
            return
        }

        withScope(mainScope) {
            navigator.pause()
        }
    }

    override suspend fun resume() {
        val navigator = audioNavigator ?: run {
            Log.e(TAG, "::pause called without an active navigator")
            return
        }

        withScope(mainScope) {
            // TODO: Do we need to check if already playing?
            navigator.play()
        }
    }

    override suspend fun goBackward() {
        val navigator = audioNavigator ?: run {
            Log.e(TAG, "::pause called without an active navigator")
            return
        }

        withScope(mainScope) {
            navigator.skip((-preferences.seekInterval).seconds)
        }
    }

    override suspend fun goForward() {
        val navigator = audioNavigator ?: run {
            Log.e(TAG, "::pause called without an active navigator")
            return
        }

        withScope(mainScope) {
            navigator.skip((preferences.seekInterval).seconds)
        }
    }

    override suspend fun goToLocator(locator: Locator) {
        val navigator = audioNavigator ?: run {
            Log.e(TAG, "::goToLocator called without an active navigator")
            return
        }

        withScope(mainScope) {
            val toLocator = locator.progression?.let { progression ->
                val readingOrderLink =
                    publication.readingOrder.find { link ->
                        link.href.toString() == locator.href.toString()
                    } ?: run {
                        Log.d(TAG, "::goToLocator - ${locator.href} not found in reading order")
                        return@withScope
                    }

                val timeOffset = readingOrderLink.duration?.takeIf { it > 0 }
                    ?.let { duration -> duration * progression } ?: run {
                    Log.d(TAG, "::goToLocator - reading order link is missing a duration")
                    return@withScope
                }

                locator.copyWithTimeFragment(timeOffset)
            } ?: locator

            navigator.go(toLocator)
        }
    }

    override suspend fun seekTo(offset: Double) {
        val navigator = audioNavigator ?: run {
            Log.d(TAG, ":seekTo - called without navigator")
            return
        }

        withScope(mainScope) {
            navigator.skip(offset.seconds)
        }
    }

    override suspend fun seekToProgression(progression: Double): Boolean {
        val navigator = audioNavigator ?: run {
            Log.d(TAG, ":seekToProgression - called without navigator")
            return false
        }

        if (progression !in 0.0..1.0) {
            Log.d(TAG, ":seekToProgression - progression $progression is not between 0.0 and 1.0")
            return false
        }

        return withScope(mainScope) {
            val duration = navigator.asMedia3Player().duration
            val timeOffset = duration * progression / 1000.0

            val toLocator = navigator.currentLocator.value.copyWithTimeFragment(timeOffset)

            goToLocator(toLocator)
            return@withScope true
        }
    }

    /**
     * Updates Audio preferences, does not override current preferences if props are null
     */
    fun updatePreferences(prefs: FlutterAudioPreferences) {
        preferences += prefs

        val navigator = audioNavigator ?: run {
            Log.d(TAG, ":updatePreferences - called without navigator")
            return
        }

        mainScope.launch {
            navigator.submitPreferences(preferences.toExoPlayerPreferences())
        }
    }

    override fun setupNavigatorListeners() {
        val navigator = audioNavigator ?: run {
            Log.e(TAG, ": setupNavigatorListeners - navigator is null")
            return
        }

        // Listen to state changes
        navigator.playback
            .throttleLatest(100.milliseconds)
            .distinctUntilChangedBy { pb ->
                "${pb.state}|${pb.playWhenReady}"
            }
            .onEach { pb ->
                onPlaybackStateChanged(pb)
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        // Handle buffered changes
        navigator.playback
            .throttleLatest(250.milliseconds)
            .distinctUntilChangedBy { pb -> pb.buffered }
            .onEach { pb ->
                timebaseListener.onTimebasedBufferChanged(pb.buffered)
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        // Handle current locator changes
        navigator.currentLocator
            .throttleLatest(100.milliseconds)
            .distinctUntilChanged()
            .onEach { locator ->
                onCurrentLocatorChanges(locator)
                state[currentTimebaseLocatorKey] = locator
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        mainScope.async {
            navigator.settings
                .collect { s ->
                    Log.d(TAG, ": AudioNavigator settings changed: $s")
                }
        }
    }

    @OptIn(InternalReadiumApi::class)
    override fun onCurrentLocatorChanges(locator: Locator) {
        var emittingLocator = locator

        locator.locations.time?.let { time ->
            var matchedTocItem: Link? = null
            val cleanHref = locator.href.cleanHref().path
            for (link in publication.tableOfContents.flattenChildren().filter {
                it.href.resolve().cleanHref().path == cleanHref
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

                Log.e(
                    TAG,
                    ": onPlaybackStateChanged - audio error: Message=${error.message} cause=${error.cause}"
                )

                timebaseListener.onTimebasedPlaybackStateChanged(TimebasedState.Failure)
                timebaseListener.onTimebasedPlaybackFailure(
                    PublicationError.invoke(error)
                )
            }

            else -> {
                super.onPlaybackStateChanged(pb)
            }
        }
    }

    override fun storeState(): Bundle {
        return Bundle().apply {
            putString(
                currentTimebaseLocatorKey,
                (state[currentTimebaseLocatorKey] as? Locator)?.toJSON()?.toString()
            )

            putString(
                audioPreferencesKey,
                FlutterAudioPreferences.toJSON(preferences).toString()
            )
        }
    }

    override fun dispose() {
        super.dispose()

        mainScope.launch {
            mediaServiceFacade?.closeSession()

            audioNavigator?.close()
            audioNavigator = null
        }
    }

    companion object {
        fun restoreState(
            publication: Publication,
            listener: TimebasedListener,
            state: Bundle
        ): AudiobookNavigator {
            val locator = state.getString(currentTimebaseLocatorKey)
                ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            val preferences = state.getString(audioPreferencesKey)
                ?.let { json -> FlutterAudioPreferences.fromJSON(json) }
                ?: FlutterAudioPreferences()

            return AudiobookNavigator(publication, listener, locator, preferences)
        }
    }
}

