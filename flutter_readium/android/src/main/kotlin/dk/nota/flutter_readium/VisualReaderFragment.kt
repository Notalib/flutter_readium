package dk.nota.flutter_readium

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import dk.nota.flutter_readium.databinding.FragmentReaderBinding
import org.readium.r2.shared.ExperimentalReadiumApi

@OptIn(ExperimentalReadiumApi::class)
abstract class VisualReaderFragment(model: ReaderInitData) : BaseReaderFragment(model) {
    private lateinit var navigatorFragment: Fragment

    protected var binding: FragmentReaderBinding by viewLifecycle()

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        binding = FragmentReaderBinding.inflate(inflater, container, false)

        return binding.root
    }
}