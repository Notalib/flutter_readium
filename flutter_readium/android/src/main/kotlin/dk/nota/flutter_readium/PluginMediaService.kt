package dk.nota.flutter_readium

/*
 * Modified version of kotlin-toolkit's example app MediaService.
 * See https://github.com/search?q=repo%3Areadium%2Fkotlin-toolkit%20mediaServiceFacade&type=code
 * and https://github.com/readium/kotlin-toolkit/blob/develop/docs/guides/navigator/media-navigator.md
 */

/*
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
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import org.readium.navigator.media.common.Media3Adapter
import org.readium.navigator.media.common.MediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi

@OptIn(ExperimentalReadiumApi::class)
typealias AnyMediaNavigator = MediaNavigator<*, *, *>

private const val TAG = "Flutter_Readium.MediaService"

@OptIn(ExperimentalReadiumApi::class)
@androidx.annotation.OptIn(UnstableApi::class)
class PluginMediaService : MediaSessionService() {

    class Session(
        val bookIdentifier: String,
        val navigator: AnyMediaNavigator,
        val mediaSession: MediaSession,
    ) {
        val coroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    }

    /**
     * The service interface to be used by the app.
     */
    inner class Binder : android.os.Binder() {

        //private val app: org.readium.r2.testapp.Application
        //    get() = application as org.readium.r2.testapp.Application

        private val sessionMutable: MutableStateFlow<Session?> =
            MutableStateFlow(null)

        val session: StateFlow<Session?> =
            sessionMutable.asStateFlow()

        fun closeSession() {
            Log.d(TAG, "closeSession")
            session.value?.let { session ->
                session.mediaSession.release()
                session.coroutineScope.cancel()
                session.navigator.close()
                sessionMutable.value = null
            }
        }

        @OptIn(FlowPreview::class)
        fun <N> openSession(
            navigator: N,
            bookIdentifier: String,
        ) where N : AnyMediaNavigator, N : Media3Adapter {
            Log.d(TAG, "openSession")
            val activityIntent = createSessionActivityIntent()
            val mediaSession = MediaSession.Builder(applicationContext, navigator.asMedia3Player())
                .setSessionActivity(activityIntent)
                .setId(bookIdentifier)
                .build()

            addSession(mediaSession)

            val session = Session(
                bookIdentifier,
                navigator,
                mediaSession
            )

            sessionMutable.value = session

            /*
             * Launch a job for saving progression even when playback is going on in the background
             * with no ReaderActivity opened.
             */
            navigator.currentLocator
                .sample(5000)
                .onEach { locator ->
                    Log.d(TAG, "Saving progression $locator")
                    // TODO: Submit on the plugin audio-locator stream?
                    //app.bookRepository.saveProgression(locator, bookId)
                }.launchIn(session.coroutineScope)
        }

        private fun createSessionActivityIntent(): PendingIntent {
            // This intent will be triggered when the notification is clicked.
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags = flags or PendingIntent.FLAG_IMMUTABLE
            }

            val intent = application.packageManager.getLaunchIntentForPackage(
                application.packageName
            )

            return PendingIntent.getActivity(applicationContext, 0, intent, flags)
        }

        fun stop() {
            closeSession()
            ServiceCompat.stopForeground(this@PluginMediaService, ServiceCompat.STOP_FOREGROUND_REMOVE)
            this@PluginMediaService.stopSelf()
        }
    }

    private val binder by lazy {
        Binder()
    }

    override fun onBind(intent: Intent?): IBinder? {
        Log.d(TAG, "onBind called with $intent")

        return if (intent?.action == SERVICE_INTERFACE) {
            super.onBind(intent)
            // Readium-aware client.
            Log.d(TAG, "Returning custom binder.")
            binder
        } else {
            // External controller.
            Log.d(TAG, "Returning MediaSessionService binder.")
            super.onBind(intent)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        //val readerRepository = (application as org.readium.r2.testapp.Application).readerRepository

        // App and service can be started again from a stale notification using
        // PendingIntent.getForegroundService, so we need to call startForeground and then stop
        // the service.
        // TODO: What do we do here?
        /* if (readerRepository.isEmpty()) {
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

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return binder.session.value?.mediaSession
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "Task removed. Stopping session and service.")
        // Close the session to allow the service to be stopped.
        binder.closeSession()
        binder.stop()
    }

    override fun onDestroy() {
        Log.d(TAG, "Destroying MediaService.")
        binder.closeSession()
        // Ensure one more time that all notifications are gone and,
        // hopefully, pending intents cancelled.
        NotificationManagerCompat.from(this).cancelAll()
        super.onDestroy()
    }

    companion object {

        const val SERVICE_INTERFACE = "dk.nota.flutter_readium.MediaService"

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

            val mediaServiceConnection = object : ServiceConnection {

                override fun onServiceConnected(name: ComponentName?, service: IBinder) {
                    Log.d(TAG, "MediaService bound.")
                    mediaServiceBinder.complete(service as Binder)
                }

                override fun onServiceDisconnected(name: ComponentName) {
                    Log.d(TAG, "MediaService disconnected.")
                }

                override fun onNullBinding(name: ComponentName) {
                    if (mediaServiceBinder.isCompleted) {
                        // This happens when the service has successfully connected and later
                        // stopped and disconnected.
                        return
                    }
                    val errorMessage = "Failed to bind to MediaService."
                    Log.e(TAG, errorMessage)
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