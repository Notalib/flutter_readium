package dk.nota.flutter_readium.fragments

import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import dk.nota.flutter_readium.models.ReaderViewModel
import org.readium.r2.navigator.Navigator
import org.readium.r2.shared.publication.Locator

private const val TAG: String = "BaseReaderFragment"

/**
 * Base class for reader fragments.
 */
abstract class BaseReaderFragment : Fragment() {
    var vm: ReaderViewModel? = null
    protected open var navigator: Navigator? = null

    val currentLocator get() = navigator?.currentLocator

    open fun go(
        locator: Locator?,
        animated: Boolean,
    ): Boolean {
        if (locator == null) {
            return false
        }

        val n =
            navigator ?: run {
                Log.d(TAG, "::go - navigator not ready.")
                return false
            }

        Log.d(TAG, "::go - to:$locator, animated:$animated")
        return n.go(locator, animated)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        Log.d(TAG, "::onCreateView")
        return super.onCreateView(inflater, container, savedInstanceState)
    }
}
