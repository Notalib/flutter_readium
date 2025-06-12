package dk.nota.flutter_readium

import androidx.fragment.app.Fragment
import org.readium.r2.navigator.Navigator
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

abstract class BaseReaderFragment(protected val model: ReaderInitData): Fragment() {
    protected val publication: Publication get() = model.publication

    protected abstract val navigator: Navigator

    open fun go(locator: Locator, animated: Boolean): Boolean {
        return navigator.go(locator, animated)
    }
}