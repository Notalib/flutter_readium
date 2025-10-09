/*
 * Copyright 2022 Readium Foundation. All rights reserved.
 * Use of this source code is governed by the BSD-style license
 * available in the top-level LICENSE file of the project.
 */

package dk.nota.flutter_readium

import android.app.Application
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import org.readium.navigator.media.common.Media3Adapter
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.util.CoroutineQueue

/**
 * Enables to try to close a session without starting the [PluginMediaService] if it is not started.
 */
@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class, InternalReadiumApi::class)
class PluginMediaServiceFacade(
    private val application: Application,
) {
    private val coroutineScope: CoroutineScope =
        MainScope()

    private val coroutineQueue: CoroutineQueue =
        CoroutineQueue()

    private var binder: PluginMediaService.Binder? =
        null

    private var bindingJob: Job? =
        null

    private val sessionMutable: MutableStateFlow<PluginMediaService.Session?> =
        MutableStateFlow(null)

    val session: StateFlow<PluginMediaService.Session?> =
        sessionMutable.asStateFlow()

    /**
     * Throws an IllegalStateException if binding to the MyMediaService fails.
     */
    suspend fun <N> openSession(
        navigator: N,
    ) where N : AnyMediaNavigator, N : Media3Adapter {
        coroutineQueue.await {
            PluginMediaService.start(application)
            binder = try {
                PluginMediaService.bind(application)
            } catch (e: Exception) {
                // Failed to bind to the service.
                PluginMediaService.stop(application)
                throw e
            }

            bindingJob = binder!!.session
                .onEach { sessionMutable.value = it }
                .launchIn(coroutineScope)
            binder!!.openSession(navigator)
        }
    }

    fun closeSession() {
        coroutineQueue.launch {
            bindingJob?.cancelAndJoin()
            binder?.closeSession()
            binder?.stop()
            sessionMutable.value = null
            binder = null
        }
    }
}
