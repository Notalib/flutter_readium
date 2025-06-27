package dk.nota.flutter_readium.fragments

import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import dk.nota.flutter_readium.Readium
import dk.nota.flutter_readium.models.ReaderViewModel
import org.readium.r2.navigator.Navigator
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.AbsoluteUrl

private const val publicationUrlKeyName: String = "publicationUrl"
private const val identifierKeyName: String = "publicationIdentifier"
private const val currentLocatorKeyName: String = "currentLocator"

private const val TAG: String = "BaseReaderFragment"

private fun Bundle.resetState() {
    this.remove(identifierKeyName)
    this.remove(publicationUrlKeyName)
    this.remove(currentLocatorKeyName)
}

abstract class BaseReaderFragment : Fragment() {
    var vm: ReaderViewModel? = null
    protected var navigator: Navigator? = null

    val currentLocator get() = navigator?.currentLocator

    protected val readium: Readium by lazy {
        Readium(requireContext())
    }

    open fun go(locator: Locator, animated: Boolean): Boolean {
        if (navigator == null) {
            Log.d(TAG, "::go - navigator not ready.")
            return false
        }

        return navigator!!.go(locator, animated)
    }

    protected open fun restoreViewModelFromState(savedInstanceState: Bundle): ReaderViewModel? {
        val identifier = savedInstanceState.getString(identifierKeyName) ?: return null
        val publicationUrl = savedInstanceState.getString(publicationUrlKeyName) ?: return null

        val locator = savedInstanceState.getParcelable(currentLocatorKeyName) as Locator?

        return ReaderViewModel().let {
            it.pubUrl = publicationUrl
            it.identifier = identifier
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

        val identifier = model.identifier
        if (identifier == null) {
            outState.resetState()
            return
        }

        val pubUrl = model.pubUrl
        if (pubUrl == null) {
            outState.resetState()
            return
        }

        Log.d(TAG, "pubUrl:${pubUrl}")

        outState.putString(identifierKeyName, identifier)
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
        Log.d(TAG, "::onResume - ended")
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