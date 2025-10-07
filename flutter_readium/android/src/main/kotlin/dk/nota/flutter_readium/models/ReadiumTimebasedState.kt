package dk.nota.flutter_readium.models

import dk.nota.flutter_readium.navigators.TimebasedNavigator
import org.readium.r2.shared.publication.Locator

class ReadiumTimebasedState(
    val locator: Locator?,
    val state: TimebasedNavigator.TimebasedState,
    val currentOffset: Double?,
    val currentBuffer: Long?,
    val currentDuration: Double
)
