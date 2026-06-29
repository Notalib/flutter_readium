/**
 * Pure gating logic for audio-driven comic panel pan.
 *
 * Auto-pan follows the narration cue's panel region only when the feature is
 * enabled AND the user has not taken manual control of the current page. A
 * manual zoom/pan gesture sets `manuallyOverridden`; it is reset on each page
 * turn so auto-pan re-engages on the next page. Extracted here (DOM-free) so the
 * rule is unit tested once and ported verbatim to iOS/Android.
 */
export interface ComicAutoPanState {
  /** From the `setNarrationSyncEnabled` toggle. */
  autoPanEnabled: boolean;
  /** Set by any manual gesture; cleared on page change. */
  manuallyOverridden: boolean;
}

/** Whether a narration cue should drive auto-pan in the given state. */
export function shouldAutoPan(state: ComicAutoPanState): boolean {
  return state.autoPanEnabled && !state.manuallyOverridden;
}
