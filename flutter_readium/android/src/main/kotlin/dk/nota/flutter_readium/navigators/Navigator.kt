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
abstract class Navigator(
    val publication: Publication,
    val initialLocator: Locator?
) {
    protected val jobs = mutableListOf<Job>()

    protected val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /**
     * Init the navigator
     */
    abstract suspend fun initNavigator()

    open fun dispose() {
        jobs.forEach { it.cancel() }
        jobs.clear()
        mainScope.coroutineContext.cancelChildren()
    }

    abstract fun onCurrentLocatorChanges(locator: Locator)

    /**
     * Setup listeners for the navigator
     */
    protected abstract fun setupNavigatorListeners()

    abstract fun storeState(): Bundle
}

