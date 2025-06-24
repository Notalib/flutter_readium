package dk.nota.flutter_readium.fragments

import androidx.fragment.app.Fragment
import dk.nota.flutter_readium.models.ReaderInitData
import org.readium.r2.navigator.Navigator
import org.readium.r2.shared.publication.Locator

abstract class BaseReaderFragment: Fragment() {
    protected abstract val navigator: Navigator

    var model: ReaderInitData? = null

    open fun go(locator: Locator, animated: Boolean): Boolean {
        return navigator.go(locator, animated)
    }
}