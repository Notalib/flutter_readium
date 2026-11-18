package dk.nota.flutterreadium

import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.commitNow
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.android.controller.ActivityController
import org.robolectric.annotation.Config

/**
 * Covers the fragment commits navigators make in `attachNavigator()` and `dispose()`. Each
 * crash case first shows that a plain `commitNow` throws in that lifecycle state, so the test
 * reproduces the production crash rather than a state where any commit would succeed.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
internal class NavigatorFragmentCommitTest {
    private lateinit var controller: ActivityController<FragmentActivity>
    private lateinit var container: FrameLayout

    private val activity get() = controller.get()
    private val fragmentManager get() = activity.supportFragmentManager

    @Before
    fun setUp() {
        controller = Robolectric.buildActivity(FragmentActivity::class.java)
        controller.create()
        container = FrameLayout(activity).apply { id = View.generateViewId() }
        activity.setContentView(container)
        controller.start().resume().visible()
    }

    private fun saveState() {
        controller.pause().stop().saveInstanceState(Bundle())
    }

    @Test
    fun `addNavigatorFragment adds the fragment to the container`() {
        val navigator = Fragment()

        fragmentManager.addNavigatorFragment(container, navigator, TAG)

        assertSame(navigator, fragmentManager.findFragmentByTag(TAG))
        assertTrue(navigator.isAdded)
    }

    @Test
    fun `addNavigatorFragment adds the fragment after the activity saved its state`() {
        saveState()
        assertThrows(IllegalStateException::class.java) {
            fragmentManager.commitNow { add(container, Fragment(), "plain") }
        }
        val navigator = Fragment()

        fragmentManager.addNavigatorFragment(container, navigator, TAG)

        assertSame(navigator, fragmentManager.findFragmentByTag(TAG))
    }

    @Test
    fun `addNavigatorFragment does nothing once the fragment manager is destroyed`() {
        controller.pause().stop().destroy()
        assertTrue(fragmentManager.isDestroyed)
        val navigator = Fragment()

        fragmentManager.addNavigatorFragment(container, navigator, TAG)

        assertFalse(navigator.isAdded)
    }

    @Test
    fun `removeFromParentFragmentManager removes an added fragment`() {
        val navigator = Fragment()
        fragmentManager.addNavigatorFragment(container, navigator, TAG)

        navigator.removeFromParentFragmentManager()

        assertFalse(navigator.isAdded)
        assertNull(fragmentManager.findFragmentByTag(TAG))
    }

    @Test
    fun `removeFromParentFragmentManager removes the fragment after the activity saved its state`() {
        val navigator = Fragment()
        fragmentManager.addNavigatorFragment(container, navigator, TAG)
        saveState()

        navigator.removeFromParentFragmentManager()

        assertFalse(navigator.isAdded)
    }

    @Test
    fun `removeFromParentFragmentManager does nothing for a fragment that is not added`() {
        val navigator = Fragment()
        assertThrows(IllegalStateException::class.java) { navigator.parentFragmentManager }

        navigator.removeFromParentFragmentManager()

        assertFalse(navigator.isAdded)
    }

    /**
     * Flutter disposes platform views from its own fragment's `onDetach`, which runs inside
     * `FragmentManager.dispatchDestroy` while the navigator fragment is still added.
     */
    @Test
    fun `removeFromParentFragmentManager does nothing while the activity is being destroyed`() {
        val navigator = Fragment()
        var plainCommitError: Throwable? = null
        var helperError: Throwable? = null
        val flutterHost =
            DetachCallbackFragment {
                assertTrue(navigator.isAdded)
                plainCommitError =
                    runCatching { fragmentManager.commitNow { remove(navigator) } }.exceptionOrNull()
                helperError = runCatching { navigator.removeFromParentFragmentManager() }.exceptionOrNull()
            }
        // Added before the navigator, so the manager detaches it first.
        fragmentManager.commitNow { add(flutterHost, "flutter") }
        fragmentManager.addNavigatorFragment(container, navigator, TAG)

        controller.pause().stop().destroy()

        assertTrue(plainCommitError is IllegalStateException)
        assertNull(helperError)
    }

    // FragmentTransaction.add() rejects fragment classes that are not public.
    class DetachCallbackFragment(
        private val onDetachCallback: () -> Unit,
    ) : Fragment() {
        override fun onDetach() {
            onDetachCallback()
            super.onDetach()
        }
    }

    private companion object {
        const val TAG = "navigator"
    }
}
