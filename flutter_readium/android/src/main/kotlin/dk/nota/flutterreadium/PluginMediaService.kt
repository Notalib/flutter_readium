package dk.nota.flutterreadium

/*
 * Modified version of kotlin-toolkit's example app MediaService.
 * See https://github.com/search?q=repo%3Areadium%2Fkotlin-toolkit%20mediaServiceFacade&type=code
 * and https://github.com/readium/kotlin-toolkit/blob/develop/docs/guides/navigator/media-navigator.md
 *
 * Copyright 2022 Readium Foundation. All rights reserved.
 * Use of this source code is governed by the BSD-style license
 * available in the top-level LICENSE file of the project.
 */

import android.app.Application
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.media3.common.C
import androidx.media3.common.ForwardingSimpleBasePlayer
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import dk.nota.flutterreadium.events.ExternalPlaybackCommandAction
import dk.nota.flutterreadium.events.ReadiumExternalPlaybackCommand
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.sample
import org.readium.navigator.media.common.Media3Adapter
import org.readium.navigator.media.common.MediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi

@OptIn(ExperimentalReadiumApi::class)
typealias AnyMediaNavigator = MediaNavigator<*, *, *>

private const val TAG = "Flutter_Readium.MediaService"

private const val CUSTOM_COMMAND_REWIND_ACTION_ID = "REWIND_CUSTOM"
private const val CUSTOM_COMMAND_FORWARD_ACTION_ID = "FORWARD_CUSTOM"

@UnstableApi
enum class NotificationPlayerCustomCommandButton(
    val customAction: String,
    val commandButton: CommandButton,
) {
    REWIND(
        customAction = CUSTOM_COMMAND_REWIND_ACTION_ID,
        commandButton =
            CommandButton
                .Builder(CommandButton.ICON_SKIP_BACK)
                .setDisplayName("Rewind")
                .setSlots(CommandButton.SLOT_BACK)
                .setSessionCommand(SessionCommand(CUSTOM_COMMAND_REWIND_ACTION_ID, Bundle()))
                .setCustomIconResId(androidx.media3.session.R.drawable.media3_icon_skip_back)
                .build(),
    ),
    FORWARD(
        customAction = CUSTOM_COMMAND_FORWARD_ACTION_ID,
        commandButton =
            CommandButton
                .Builder(CommandButton.ICON_SKIP_FORWARD)
                .setDisplayName("Forward")
                .setSlots(CommandButton.SLOT_FORWARD)
                .setSessionCommand(SessionCommand(CUSTOM_COMMAND_FORWARD_ACTION_ID, Bundle()))
                .setCustomIconResId(androidx.media3.session.R.drawable.media3_icon_skip_forward)
                .build(),
    ),
}

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
@androidx.annotation.OptIn(UnstableApi::class)
class PluginMediaService :
    MediaSessionService(),
    MediaSession.Callback {
    class Session(
        val navigator: AnyMediaNavigator,
        val mediaSession: MediaSession,
    ) {
        val coroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    }

    private val notificationPlayerCustomCommandButtons =
        NotificationPlayerCustomCommandButton.entries.map { command -> command.commandButton }

    override fun onConnect(
        session: MediaSession,
        controller: MediaSession.ControllerInfo,
    ): MediaSession.ConnectionResult {
        val connectionResult = super.onConnect(session, controller)
        val availableSessionCommands = connectionResult.availableSessionCommands.buildUpon()

        // Registering custom player command buttons for player notification.
        notificationPlayerCustomCommandButtons.forEach { commandButton ->
            commandButton.sessionCommand?.let(availableSessionCommands::add)
        }

        return MediaSession.ConnectionResult.accept(
            availableSessionCommands.build(),
            connectionResult.availablePlayerCommands,
        )
    }

    override fun onPostConnect(
        session: MediaSession,
        controller: MediaSession.ControllerInfo,
    ) {
        super.onPostConnect(session, controller)
        if (notificationPlayerCustomCommandButtons.isNotEmpty()) {
            // Setting custom player command buttons to mediaLibrarySession for player notification.
            // Set media-button preferences, so that skip buttons are replaces with seek
            session.setCustomLayout(notificationPlayerCustomCommandButtons)
            session.setMediaButtonPreferences(notificationPlayerCustomCommandButtons)
        }
    }

    override fun onCustomCommand(
        session: MediaSession,
        controller: MediaSession.ControllerInfo,
        customCommand: SessionCommand,
        args: Bundle,
    ): ListenableFuture<SessionResult> {
        // Handle custom command buttons from player notification.
        if (customCommand.customAction == NotificationPlayerCustomCommandButton.REWIND.customAction) {
            ReadiumReader.emitExternalPlaybackCommand(
                ReadiumExternalPlaybackCommand(
                    action = ExternalPlaybackCommandAction.SeekBackward,
                ),
            )
            CoroutineScope(Dispatchers.Main).async {
                ReadiumReader.previous()
            }
        }
        if (customCommand.customAction == NotificationPlayerCustomCommandButton.FORWARD.customAction) {
            ReadiumReader.emitExternalPlaybackCommand(
                ReadiumExternalPlaybackCommand(
                    action = ExternalPlaybackCommandAction.SeekForward,
                ),
            )
            CoroutineScope(Dispatchers.Main).async {
                ReadiumReader.next()
            }
        }
        return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
    }

    /**
     * The service interface to be used by the app.
     */
    inner class Binder : android.os.Binder() {
        private val sessionMutable: MutableStateFlow<Session?> =
            MutableStateFlow(null)

        val session: StateFlow<Session?> =
            sessionMutable.asStateFlow()

        fun closeSession() {
            PluginLog.d(TAG, "closeSession")
            session.value?.let { session ->
                session.mediaSession.release()
                session.coroutineScope.cancel()
                sessionMutable.value = null
            }
        }

        @OptIn(FlowPreview::class)
        fun <N> openSession(
            navigator: N,
            onIsPlayingChanged: ((Boolean) -> Unit)? = null,
        ) where N : AnyMediaNavigator, N : Media3Adapter {
            PluginLog.d(TAG, "openSession")

            val activityIntent = createSessionActivityIntent()
            val player = navigator.asMedia3Player()

            // Media3's AudioFocusManager pauses the underlying audio sink for audio-focus
            // losses (e.g. incoming calls) without changing playWhenReady or playbackState,
            // so upstream Readium's playback StateFlow does not emit. Listen on the raw
            // Player and bridge isPlaying changes back to our navigator wrapper.
            onIsPlayingChanged?.let { cb ->
                player.addListener(
                    object : Player.Listener {
                        override fun onIsPlayingChanged(isPlaying: Boolean) {
                            cb(isPlaying)
                        }
                    },
                )
            }

            // Create our SimpleBasePlayer override to override some media-button mapping.
            // Extract publication reading-order durations now (manifest values, always available)
            // so PluginSimpleBasePlayer does not have to rely on the Media3 timeline (which may
            // still be C.TIME_UNSET for unloaded tracks).
            val publicationChapterDurationsMs: List<Long>? =
                ReadiumReader.currentPublication
                    ?.readingOrder
                    ?.mapNotNull { link ->
                        val secs = link.duration
                        if (secs != null && secs.isFinite() && secs > 0) (secs * 1000L).toLong() else null
                    }?.takeIf { it.size == (ReadiumReader.currentPublication?.readingOrder?.size ?: 0) }

            val pluginForwardingPlayer =
                PluginSimpleBasePlayer(
                    player,
                    ReadiumReader.audioPreferences,
                    publicationChapterDurationsMs,
                    ReadiumReader::emitExternalPlaybackCommand,
                )

            val mediaSession =
                MediaSession
                    .Builder(applicationContext, pluginForwardingPlayer)
                    .setSessionActivity(activityIntent)
                    .setCallback(this@PluginMediaService)
                    .setCustomLayout(notificationPlayerCustomCommandButtons)
                    .build()

            addSession(mediaSession)

            val session =
                Session(
                    navigator,
                    mediaSession,
                )

            sessionMutable.value = session

            /*
             * Launch a job for saving progression even when playback is going on in the background
             * with no ReaderActivity opened.
             */
            navigator.currentLocator
                .sample(5000)
                .onEach { locator ->
                    PluginLog.d(TAG, "Progression update: $locator")
                    // TODO: Submit on the plugin audio-locator stream?
                    // app.bookRepository.saveProgression(locator, bookId)
                }.launchIn(session.coroutineScope)
        }

        private fun createSessionActivityIntent(): PendingIntent {
            // This intent will be triggered when the notification is clicked.
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags = flags or PendingIntent.FLAG_IMMUTABLE
            }

            val intent =
                application.packageManager.getLaunchIntentForPackage(
                    application.packageName,
                )

            return PendingIntent.getActivity(applicationContext, 0, intent, flags)
        }

        fun stop() {
            closeSession()
            ServiceCompat.stopForeground(
                this@PluginMediaService,
                ServiceCompat.STOP_FOREGROUND_REMOVE,
            )
            this@PluginMediaService.stopSelf()
        }
    }

    private val binder by lazy {
        Binder()
    }

    override fun onBind(intent: Intent?): IBinder? {
        PluginLog.d(TAG, "onBind called with $intent")

        return if (intent?.action == SERVICE_INTERFACE) {
            super.onBind(intent)
            // Readium-aware client.
            PluginLog.d(TAG, "Returning custom binder.")
            binder
        } else {
            // External controller.
            PluginLog.d(TAG, "Returning MediaSessionService binder.")
            super.onBind(intent)
        }
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        super.onStartCommand(intent, flags, startId)

        // TODO: Handle restoration properly when activated from a stale notification.
        // App and service can be started again from a stale notification using
        // PendingIntent.getForegroundService, so we need to call startForeground and then stop
        // the service.

        /* val readerRepository = (application as org.readium.r2.testapp.Application).readerRepository
        if (readerRepository.isEmpty()) {
            val notification =
                NotificationCompat.Builder(
                    this,
                    DefaultMediaNotificationProvider.DEFAULT_CHANNEL_ID
                )
                    .setContentTitle("Media service")
                    .setContentText("Media service will stop immediately.")
                    .build()

            // Unfortunately, stopSelf does not remove the need for calling startForeground
            // to prevent crashing.
            startForeground(DefaultMediaNotificationProvider.DEFAULT_NOTIFICATION_ID, notification)
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf(startId)
        } */

        // Prevents the service from being automatically restarted after being killed;
        return START_NOT_STICKY
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = binder.session.value?.mediaSession

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        PluginLog.d(TAG, "Task removed. Stopping session and service.")
        // Close the session to allow the service to be stopped.
        binder.closeSession()
        binder.stop()
    }

    override fun onDestroy() {
        PluginLog.d(TAG, "Destroying MediaService.")
        binder.closeSession()
        // Ensure one more time that all notifications are gone and,
        // hopefully, pending intents cancelled.
        NotificationManagerCompat.from(this).cancelAll()
        super.onDestroy()
    }

    companion object {
        const val SERVICE_INTERFACE = "dk.nota.flutterreadium.MediaService"

        fun start(application: Application) {
            val intent = intent(application)
            application.startService(intent)
        }

        fun stop(application: Application) {
            val intent = intent(application)
            application.stopService(intent)
        }

        suspend fun bind(application: Application): Binder {
            val mediaServiceBinder: CompletableDeferred<Binder> =
                CompletableDeferred()

            val mediaServiceConnection =
                object : ServiceConnection {
                    override fun onServiceConnected(
                        name: ComponentName?,
                        service: IBinder,
                    ) {
                        PluginLog.d(TAG, "MediaService bound.")
                        mediaServiceBinder.complete(service as Binder)
                    }

                    override fun onServiceDisconnected(name: ComponentName) {
                        PluginLog.d(TAG, "MediaService disconnected.")
                    }

                    override fun onNullBinding(name: ComponentName) {
                        if (mediaServiceBinder.isCompleted) {
                            // This happens when the service has successfully connected and later
                            // stopped and disconnected.
                            return
                        }
                        val errorMessage = "Failed to bind to MediaService."
                        PluginLog.e(TAG, errorMessage)
                        val exception = IllegalStateException(errorMessage)
                        mediaServiceBinder.completeExceptionally(exception)
                    }
                }

            val intent = intent(application)
            application.bindService(intent, mediaServiceConnection, 0)

            return mediaServiceBinder.await()
        }

        private fun intent(application: Application) =
            Intent(SERVICE_INTERFACE)
                // MediaSessionService.onBind requires the intent to have a non-null action
                .apply { setClass(application, PluginMediaService::class.java) }
    }
}

@UnstableApi
class PluginSimpleBasePlayer(
    player: Player,
    val preferences: FlutterAudioPreferences,
    /** Chapter durations from the publication manifest (seconds → ms). Null = chapter mode or durations unavailable. */
    private val manifestChapterDurationsMs: List<Long>? = null,
    private val onExternalPlaybackCommand: ((ReadiumExternalPlaybackCommand) -> Unit)? = null,
) : ForwardingSimpleBasePlayer(player) {
    private data class PublicationSeekTarget(
        val mediaItemIndex: Int,
        val positionMs: Long,
    )

    private fun usesWholeBookTimebase(): Boolean = preferences.controlPanelTimebase == ControlPanelTimebase.WHOLE_BOOK

    /**
     * Returns chapter durations in ms, preferring manifest values over the live Media3 timeline
     * (which may still be C.TIME_UNSET for tracks that haven't loaded yet).
     */
    private fun timelineDurationsMs(): List<Long>? {
        // Use manifest durations if available — they are always present and correct.
        if (manifestChapterDurationsMs != null) {
            return manifestChapterDurationsMs
        }

        // Fallback: try the live Media3 timeline.
        val timeline = player.currentTimeline
        if (timeline.windowCount == 0) {
            return null
        }

        val window = Timeline.Window()
        return buildList(timeline.windowCount) {
            for (index in 0 until timeline.windowCount) {
                val durationMs = timeline.getWindow(index, window).durationMs
                if (durationMs == C.TIME_UNSET || durationMs <= 0) {
                    return null
                }
                add(durationMs)
            }
        }
    }

    private fun publicationDurationMs(): Long? = timelineDurationsMs()?.sum()

    /**
     * A synthetic single-window [Timeline] that wraps the multi-chapter real timeline but exposes
     * the total publication duration as one seekable window. Used in whole-book mode so the
     * system control-panel slider max shows the total book length instead of the current chapter.
     */
    private inner class WholeBookTimeline(
        private val originalTimeline: Timeline,
        private val totalDurationMs: Long,
    ) : Timeline() {
        private val periodUid = Any()

        override fun getWindowCount(): Int = 1

        override fun getWindow(
            windowIndex: Int,
            window: Window,
            defaultPositionProjectionUs: Long,
        ): Window {
            if (originalTimeline.windowCount > 0) {
                originalTimeline.getWindow(0, window, defaultPositionProjectionUs)
            } else {
                window.isSeekable = true
                window.isDynamic = false
                window.isPlaceholder = false
                window.liveConfiguration = null
            }
            window.uid = Window.SINGLE_WINDOW_UID
            window.durationUs = totalDurationMs * 1000L
            window.defaultPositionUs = 0L
            window.firstPeriodIndex = 0
            window.lastPeriodIndex = 0
            window.positionInFirstPeriodUs = 0L
            return window
        }

        override fun getPeriodCount(): Int = 1

        override fun getPeriod(
            periodIndex: Int,
            period: Period,
            setIds: Boolean,
        ): Period {
            period.windowIndex = 0
            period.durationUs = totalDurationMs * 1000L
            period.positionInWindowUs = 0L
            if (setIds) {
                period.id = periodUid
                period.uid = periodUid
            }
            return period
        }

        override fun getIndexOfPeriod(uid: Any): Int = if (uid === periodUid) 0 else C.INDEX_UNSET

        override fun getUidOfPeriod(periodIndex: Int): Any = periodUid
    }

    private fun publicationMediaMetadata(): MediaMetadata? {
        if (!usesWholeBookTimebase()) {
            return if (player.isCommandAvailable(COMMAND_GET_METADATA)) player.mediaMetadata else null
        }

        val publicationDurationMs =
            publicationDurationMs() ?: return if (player.isCommandAvailable(COMMAND_GET_METADATA)) player.mediaMetadata else null

        val mediaMetadata =
            if (player.isCommandAvailable(COMMAND_GET_METADATA)) {
                player.mediaMetadata
            } else {
                MediaMetadata.EMPTY
            }

        return mediaMetadata.buildUpon().setDurationMs(publicationDurationMs).build()
    }

    private fun publicationPositionMs(): Long? {
        val durations = timelineDurationsMs() ?: return null
        val currentIndex = player.currentMediaItemIndex
        if (currentIndex !in durations.indices) {
            return null
        }

        return durations.take(currentIndex).sum() + player.contentPosition
    }

    private fun publicationBufferedPositionMs(): Long? {
        val durations = timelineDurationsMs() ?: return null
        val currentIndex = player.currentMediaItemIndex
        if (currentIndex !in durations.indices) {
            return null
        }

        return durations.take(currentIndex).sum() + player.contentBufferedPosition
    }

    private fun resolvePublicationSeekTarget(positionMs: Long): PublicationSeekTarget? {
        val durations = timelineDurationsMs() ?: return null
        if (durations.isEmpty()) {
            return null
        }

        val publicationDuration = durations.sum()
        var remaining = positionMs.coerceIn(0L, publicationDuration)

        durations.forEachIndexed { index, durationMs ->
            if (remaining <= durationMs || index == durations.lastIndex) {
                return PublicationSeekTarget(index, remaining.coerceAtMost(durationMs))
            }
            remaining -= durationMs
        }

        return null
    }

    private fun emitExternalPlaybackCommand(
        action: ExternalPlaybackCommandAction,
        positionMs: Long? = null,
    ) {
        onExternalPlaybackCommand?.invoke(
            ReadiumExternalPlaybackCommand(
                action = action,
                position = positionMs,
            ),
        )
    }

    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> {
        emitExternalPlaybackCommand(
            if (playWhenReady) {
                ExternalPlaybackCommandAction.Play
            } else {
                ExternalPlaybackCommandAction.Pause
            },
        )
        return super.handleSetPlayWhenReady(playWhenReady)
    }

    override fun handleSeek(
        mediaItemIndex: Int,
        positionMs: Long,
        seekCommand: Int,
    ): ListenableFuture<*> {
        // NOTE: Maps seek to next/previous track, to seek forward/backward in current track.
        if (seekCommand == COMMAND_SEEK_TO_NEXT) {
            emitExternalPlaybackCommand(ExternalPlaybackCommandAction.SeekForward)
            return super.handleSeek(mediaItemIndex, positionMs, COMMAND_SEEK_FORWARD)
        } else if (seekCommand == COMMAND_SEEK_TO_PREVIOUS) {
            emitExternalPlaybackCommand(ExternalPlaybackCommandAction.SeekBackward)
            return super.handleSeek(mediaItemIndex, positionMs, COMMAND_SEEK_BACK)
        }

        when (seekCommand) {
            COMMAND_SEEK_FORWARD -> emitExternalPlaybackCommand(ExternalPlaybackCommandAction.SeekForward)
            COMMAND_SEEK_BACK -> emitExternalPlaybackCommand(ExternalPlaybackCommandAction.SeekBackward)
            else -> emitExternalPlaybackCommand(ExternalPlaybackCommandAction.SeekTo, positionMs)
        }

        if (usesWholeBookTimebase() &&
            seekCommand != COMMAND_SEEK_FORWARD &&
            seekCommand != COMMAND_SEEK_BACK
        ) {
            resolvePublicationSeekTarget(positionMs)?.let { target ->
                return super.handleSeek(
                    target.mediaItemIndex,
                    target.positionMs,
                    COMMAND_SEEK_TO_MEDIA_ITEM,
                )
            }
        }

        return super.handleSeek(mediaItemIndex, positionMs, seekCommand)
    }

    // FIX: Hacky way to fix missing COMMAND_GET_TIMELINE from TtsSessionAdapter
    override fun getState(): State {
        // This is a copy & override of the super implementation, due to assert on empty playlist,
        // which Readium TTSPlayer sometimes provides during active states.
        // See https://github.com/readium/kotlin-toolkit/pull/716

        // In whole-book mode we report a single synthetic window, so the item index must be 0.
        // Compute once here so it can be used both for setCurrentMediaItemIndex and setPlaylist.
        val wholeBookTotalMs = if (usesWholeBookTimebase()) publicationDurationMs() else null

        // Ordered alphabetically by State.Builder setters.
        val state = State.Builder()
//      val positionSuppliers = livePositionSuppliers
        if (player.isCommandAvailable(COMMAND_GET_AUDIO_ATTRIBUTES)) {
            state.setAudioAttributes(player.audioAttributes)
        }

        if (preferences.allowExternalSeeking) {
            state.setAvailableCommands(player.availableCommands)
        } else {
            val commandsWithoutSeeking =
                player.availableCommands
                    .buildUpon()
                    .remove(COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM)
                    .build()
            state.setAvailableCommands(commandsWithoutSeeking)
        }

        PluginLog.d(
            TAG,
            "Command available: $COMMAND_GET_CURRENT_MEDIA_ITEM? - ${player.isCommandAvailable(
                COMMAND_GET_CURRENT_MEDIA_ITEM,
            )} - whole book? ${usesWholeBookTimebase()}",
        )

        if (player.isCommandAvailable(COMMAND_GET_CURRENT_MEDIA_ITEM)) {
            PluginLog.d(TAG, "Command available: $COMMAND_GET_CURRENT_MEDIA_ITEM - whole book? ${usesWholeBookTimebase()}")
            if (usesWholeBookTimebase()) {
                state.setContentPositionMs {
                    publicationPositionMs() ?: player.contentPosition
                }
                state.setContentBufferedPositionMs {
                    publicationBufferedPositionMs() ?: player.contentBufferedPosition
                }
            } else {
                state.setContentPositionMs { player.contentPosition }
                state.setContentBufferedPositionMs { player.contentBufferedPosition }
            }
//          state.setContentBufferedPositionMs(positionSuppliers.contentBufferedPositionSupplier)
//          state.setContentPositionMs(positionSuppliers.contentPositionSupplier)
        }
        if (player.isCommandAvailable(COMMAND_GET_TEXT)) {
            state.setCurrentCues(player.currentCues)
        }
        // if (player.isCommandAvailable(COMMAND_GET_TIMELINE)) {
        // In whole-book mode we report a single synthetic window, so the item index must be 0.
        state.setCurrentMediaItemIndex(if (wholeBookTotalMs != null) 0 else player.currentMediaItemIndex)
        // }
        if (player.isCommandAvailable(COMMAND_GET_DEVICE_VOLUME)) {
            state.setDeviceVolume(player.deviceVolume)
            state.setIsDeviceMuted(player.isDeviceMuted)
        }
        state.setIsLoading(player.isLoading)
        state.setMaxSeekToPreviousPositionMs(player.maxSeekToPreviousPosition)
        state.setPlaybackParameters(player.playbackParameters)
        state.setPlaybackState(player.playbackState)
        state.setPlaybackSuppressionReason(player.playbackSuppressionReason)
        state.setPlayerError(player.playerError)
        // if (player.isCommandAvailable(COMMAND_GET_TIMELINE)) {
        val tracks =
            if (player.isCommandAvailable(COMMAND_GET_TRACKS)) {
                player.currentTracks
            } else {
                Tracks.EMPTY
            }
        val mediaMetadata = publicationMediaMetadata()
        val timeline =
            if (wholeBookTotalMs != null) {
                WholeBookTimeline(player.currentTimeline, wholeBookTotalMs)
            } else {
                player.currentTimeline
            }
        state.setPlaylist(timeline, tracks, mediaMetadata)
        // }
        if (player.isCommandAvailable(COMMAND_GET_METADATA)) {
            state.setPlaylistMetadata(player.playlistMetadata)
        }
        state.setPlayWhenReady(player.playWhenReady, PLAY_WHEN_READY_CHANGE_REASON_END_OF_MEDIA_ITEM)
        state.setRepeatMode(player.repeatMode)
        state.setSeekBackIncrementMs(player.seekBackIncrement)
        state.setSeekForwardIncrementMs(player.seekForwardIncrement)
        state.setShuffleModeEnabled(player.shuffleModeEnabled)
        state.setSurfaceSize(player.surfaceSize)
        // state.setTimedMetadata(lastTimedMetadata)
        if (player.isCommandAvailable(COMMAND_GET_CURRENT_MEDIA_ITEM)) {
            state.setTotalBufferedDurationMs { player.totalBufferedDuration }
        }
        state.setTrackSelectionParameters(player.trackSelectionParameters)
        state.setVideoSize(player.videoSize)
        if (player.isCommandAvailable(COMMAND_GET_VOLUME)) {
            state.setVolume(player.volume)
        }
        return state.build()
    }
}
