package dk.nota.flutter_readium.navigators

import android.os.Bundle
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

private const val TAG = "Navigator"

@OptIn(ExperimentalReadiumApi::class)
abstract class BaseNavigator(
    /**
     * The publication to navigate.
     */
    protected var publication: Publication,
    /**
     * The initial locator to open the publication at.
     */
    protected var initialLocator: Locator?,
) : CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) {
    /**
     * List of active jobs, to be canceled on dispose
     */
    protected val jobs = mutableListOf<Job>()

    /**
     * The state map for storing navigator-specific state
     */
    protected val state = mutableMapOf<String, Any?>()

    /**
     * The IO coroutine scope.
     */
    protected val ioScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Init the navigator
     */
    abstract suspend fun initNavigator()

    /**
     * Dispose the navigator and cancel all active jobs
     */
    open fun dispose() {
        jobs.forEach { it.cancel() }
        jobs.clear()
        coroutineContext.cancelChildren()
        ioScope.coroutineContext.cancelChildren()
    }

    /**
     * Called when the current locator changes.
     */
    abstract fun onCurrentLocatorChanges(locator: Locator)

    /**
     * Setup listeners for the navigator
     */
    protected abstract fun setupNavigatorListeners()

    /**
     * store the current state of the navigator
     */
    abstract fun storeState(): Bundle
}
