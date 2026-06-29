package dk.nota.flutterreadium

import kotlin.math.roundToLong

internal fun computePublicationDurationMs(durationsSeconds: List<Double?>): Double? {
    val validDurations =
        durationsSeconds.mapNotNull { duration ->
            duration?.takeIf { it.isFinite() && it > 0.0 }
        }

    if (validDurations.size != durationsSeconds.size || validDurations.isEmpty()) {
        return null
    }

    return validDurations.sum() * 1000.0
}

internal fun computeTotalProgressDurationMs(
    totalProgression: Double?,
    publicationDurationMs: Double?,
): Double? {
    val durationMs = publicationDurationMs ?: return null
    val progression = totalProgression ?: return null
    if (!progression.isFinite()) {
        return null
    }

    val clampedProgression = progression.coerceIn(0.0, 1.0)
    return (clampedProgression * durationMs).roundToLong().toDouble()
}
