package dk.nota.flutter_readium.fragments

import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import dk.nota.flutter_readium.models.ReaderViewModel
import org.readium.r2.navigator.Navigator
import org.readium.r2.shared.publication.Locator

private const val publicationUrlKeyName: String = "publicationUrl"
private const val currentLocatorKeyName: String = "currentLocator"

private const val TAG: String = "BaseReaderFragment"

private fun Bundle.resetState() {
    this.remove(publicationUrlKeyName)
    this.remove(currentLocatorKeyName)
}

abstract class BaseReaderFragment : Fragment() {
    var vm: ReaderViewModel? = null
    protected open var navigator: Navigator? = null

    val currentLocator get() = navigator?.currentLocator

    open fun go(locator: Locator?, animated: Boolean): Boolean {
        if (locator == null) {
            return false
        }

        navigator?.apply {
            Log.d(TAG, "::go - to:$locator, animated:$animated")
            return go(locator, animated)
        }

        Log.d(TAG, "::go - navigator not ready.")
        return false
    }

    protected open fun restoreViewModelFromState(savedInstanceState: Bundle): ReaderViewModel? {
        val publicationUrl = savedInstanceState.getString(publicationUrlKeyName) ?: return null

        val locator = savedInstanceState.getParcelable(currentLocatorKeyName) as Locator?

        return ReaderViewModel().let {
            it.pubUrl = publicationUrl
            it.locator = locator

            it
        }
    }

    protected open fun storeViewModelInState(outState: Bundle) {
        val model = vm ?: return

        val publication = model.publication
        if (publication == null) {
            outState.resetState()
            return
        }

        val pubUrl = model.pubUrl
        if (pubUrl == null) {
            outState.resetState()
            return
        }

        Log.d(TAG, "pubUrl:${pubUrl}")

        outState.putString(publicationUrlKeyName, pubUrl)
        outState.putParcelable(currentLocatorKeyName, model.locator)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        Log.d(TAG, "::onSaveInstanceState")
        storeViewModelInState(outState)
        super.onSaveInstanceState(outState)
    }

    override fun onDetach() {
        Log.d(TAG, "::onDetach")
        super.onDetach()
    }

    override fun onAttach(context: Context) {
        Log.d(TAG, "::onAttach")
        super.onAttach(context)
    }

    override fun onStart() {
        Log.d(TAG, "::onStart")
        super.onStart()
        Log.d(TAG, "::onStart - ended")
    }

    override fun onStop() {
        Log.d(TAG, "::onStop")
        super.onStop()
    }

    override fun onResume() {
        Log.d(TAG, "::onResume")
        super.onResume()
    }

    override fun onDestroyView() {
        Log.d(TAG, "::onDestroyView")

        super.onDestroyView()
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        Log.d(TAG, "::onCreateView")
        return super.onCreateView(inflater, container, savedInstanceState)
    }
}
