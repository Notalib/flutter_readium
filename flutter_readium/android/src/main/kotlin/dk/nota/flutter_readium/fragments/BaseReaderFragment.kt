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

private const val TAG: String = "BaseReaderFragment"

abstract class BaseReaderFragment: Fragment() {
    var vm: ReaderViewModel? = null
    protected abstract val navigator: Navigator

    protected val readium: Readium by lazy {
        Readium(requireContext())
    }

    open fun go(locator: Locator, animated: Boolean): Boolean {
        return navigator.go(locator, animated)
    }

    protected suspend fun restorePublicationFromState(savedInstanceState: Bundle): ReaderViewModel? {
        val identifier = savedInstanceState.getString(identifierKeyName) ?: return null
        val publicationUrl = savedInstanceState.getString(publicationUrlKeyName) ?: return null

        val publication = AbsoluteUrl.invoke(publicationUrl)?.let {
            readium.openPublication(it).getOrNull()
        }

        if (publication == null) {
            Log.d(TAG, "failed to restore publication")
        }

        return ReaderViewModel().let {
            it.publication = publication
            it.identifier = identifier

            it
        }
    }

    protected fun storePublicationInState(outState: Bundle) {
        val publication = vm?.publication
        if (publication == null) {
            outState.remove(identifierKeyName)
            outState.remove(publicationUrlKeyName)
            return
        }

        val identifier = vm?.identifier
        if (identifier == null) {
            outState.remove(identifierKeyName)
            outState.remove(publicationUrlKeyName)
            return
        }

        val pubUrl = readium.publicationUrlFromIdentifier(identifier)
        if (pubUrl == null)
        {
            outState.remove(identifierKeyName)
            outState.remove(publicationUrlKeyName)
            return
        }

        Log.d(TAG, "pubUrl:${pubUrl}")

        outState.putString(identifierKeyName, identifier)
        outState.putString(publicationUrlKeyName, pubUrl)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        Log.d(TAG, "::onSaveInstanceState")
        storePublicationInState(outState)
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