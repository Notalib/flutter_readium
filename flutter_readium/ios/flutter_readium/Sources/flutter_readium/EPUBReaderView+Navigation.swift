import ReadiumNavigator
import ReadiumShared

/// goTo/sync navigation, narration-sync runtime state, and scroll-mode paging
/// (continuous-scroll publications don't have discrete pages, so backward/forward
/// is computed from viewport progression instead of delegated to the navigator).
extension EPUBReaderView {

  public func getFirstVisibleLocator() async -> Locator? {
    return await self.readiumViewController.firstVisibleElementLocator()
  }

  public func getCurrentLocation() -> Locator? {
    return self.readiumViewController.currentLocation
  }

  public func goToLocator(_ locator: Locator, animated: Bool) async -> Bool {
    Log.reader.debug("goToLocator: \(locator)")

    // NOTE: an explicit locator jump (TOC / bookmark / search) during active narration is
    // handled upstream in FlutterReadiumPlugin's "goToLocator" by seeking the timebased
    // navigator (narration follows the jump) — this method is only reached when narration is
    // NOT active, so a jump must not enter manual mode here. Page-turns (goForward/goBackward)
    // do enter manual mode; see those methods.
    isJumpingToLocator = true

    // Promote a `#id` css anchor to `fragments.first` so swift-toolkit positions correctly
    // when jumping to a media-overlay / cssSelector-only locator (e.g. a saved position or
    // bookmark). See docs/parity/locator-field-priority.md.
    let target = locator.promotingTextAnchorForVisualNav()
    return await readiumViewController.go(to: target, options: NavigatorGoOptions(animated: animated))
  }

  public func goToProgression(_ progression: Double, animated: Bool) async -> Bool {
    Log.reader.debug("goToProgression:\(progression)")
    guard let locator = getCurrentLocation() else {
      return false
    }
    let newLocator = locator.copyWithProgressionLocations(progression: progression)
    return await readiumViewController.go(to: newLocator, options: NavigatorGoOptions(animated: animated))
  }

  public func syncToLocator(_ locator: Locator, animated: Bool, segmentDuration: TimeInterval? = nil, isWordRange: Bool = false) async -> Bool {
    if isJumpingToLocator {
      Log.reader.debug("syncToLocator: skipped")
      return false
    }
    if !narrationSyncEnabled {
      lastSyncLocator = locator
      lastSyncSegmentDuration = segmentDuration
      Log.reader.debug("syncToLocator: deferred while narration sync is disabled")
      return false
    }
    // In scroll mode, skip fine-grained word-range syncs. Scrolling to each
    // spoken word re-pins the current paragraph to the top of the viewport
    // ~10×/sec, causing constant snap-to-top jitter. The utterance-level sync
    // and the per-word highlight decoration keep the reader in the right place.
    // In pagination we DO follow the word range, so an utterance spanning a page
    // boundary turns the page to the word currently being spoken.
    if (isWordRange && readiumViewController.presentation.scroll) {
      Log.reader.debug("syncToLocator: skipped word-range sync in scroll mode")
      return false
    }
    // Track the most recent navigated cue so a Re-sync (setNarrationSyncEnabled(true))
    // can snap to the CURRENT cue immediately, even when triggered mid-cue. Previously
    // this was cleared here, so a mid-cue Re-sync had no locator to replay and only
    // corrected once the next cue arrived.
    lastSyncLocator = locator
    lastSyncSegmentDuration = segmentDuration
    return await performSyncNavigation(locator, animated: animated, segmentDuration: segmentDuration)
  }

  private func performSyncNavigation(_ locator: Locator, animated: Bool, segmentDuration: TimeInterval?) async -> Bool {
    Log.reader.debug("syncToLocator: \(locator)")
    if let duration = segmentDuration {
      let segmentDurationMs = duration * 1000.0
      await readiumViewController.evaluateJavaScript("window.flutterReadium.setSegmentDuration(\(segmentDurationMs));");
    }

    // For Nota comics (EPUB + MediaOverlay) the panel pan is driven entirely by the
    // navigator's go(to:) below: the locator carries the panel element id as its
    // fragment/cssSelector, so the toolkit emits `readium.scrollToId(...)`, which the
    // NotaComicBook helper intercepts and animates (using the segment duration set
    // above). No explicit gotoComicFrame call is needed here.
    //
    // Signal the comic helper that narration is now active so it exits explore mode on
    // the first cue and can navigate to the panel normally. No-op on non-comic pages.
    await readiumViewController.evaluateJavaScript("window.comicBookPage?.onNarrationCue?.();")

    // Navigate directly — do NOT call goToLocator, which sets isJumpingToLocator = true.
    // isJumpingToLocator is meant to block TTS syncs while the user/app explicitly navigates
    // (method-channel "go"). Setting it here for a TTS-internal sync causes a cross-page
    // progression stall: the MainActor Task for the next utterance's syncToLocator runs
    // while this Task is suspended awaiting the CSS-column page turn, sees
    // isJumpingToLocator == true, and silently drops the sync. The next utterance then
    // plays audio but the spotlight decoration and page position never advance.
    return await readiumViewController.go(to: locator, options: NavigatorGoOptions(animated: animated))
  }

  /// Sets the runtime narration-sync flag and emits the new state on the
  /// `narration-sync` event channel.
  ///
  /// When enabling sync (true), any deferred sync locator that was held while sync
  /// was disabled is replayed immediately so the visual reader jumps to the current
  /// audio cue.
  ///
  /// Must be called on the MainActor (property access and stream emission are not
  /// thread-safe).
  @MainActor
  internal func setNarrationSyncEnabled(_ enabled: Bool) {
    let wasEnabled = narrationSyncEnabled
    narrationSyncEnabled = enabled
    Log.reader.debug("setNarrationSyncEnabled: \(enabled)")
    FlutterReadiumPlugin.instance?.narrationSyncStreamHandler?.sendEvent(enabled)
    // Replay deferred sync locator when re-enabling, matching the existing
    // wasSyncDisabled catch-up logic that was previously in setPreferences.
    if enabled, !wasEnabled, let deferredLocator = lastSyncLocator {
      let deferredSegmentDuration = lastSyncSegmentDuration
      lastSyncLocator = nil
      lastSyncSegmentDuration = nil
      Task.detached(priority: .high) {
        // Clear the JS-side manual-override flag so the next pinch re-enters manual
        // mode. No-op (optional chaining) on non-comic pages.
        await self.evaluateJavascript("window.comicBookPage?.clearManualOverride?.();")
        _ = await self.performSyncNavigation(
          deferredLocator,
          animated: false,
          segmentDuration: deferredSegmentDuration)
      }
    }
  }

  /// Called when narration stops (not paused — fully stopped). Resets the
  /// runtime sync flag and deferred-locator state, then tells the comic overlay
  /// to animate back to the full-page view so the user can browse freely.
  /// Distinct from setNarrationSyncEnabled(true) which replays the last cue.
  @MainActor
  public func resetForNarrationStop() {
    narrationSyncEnabled = true
    lastSyncLocator = nil
    lastSyncSegmentDuration = nil
    FlutterReadiumPlugin.instance?.narrationSyncStreamHandler?.sendEvent(true)
    Task.detached(priority: .high) {
      await self.evaluateJavascript("window.comicBookPage?.exitNarrationMode?.();")
    }
  }

  /// Enters manual mode (disables narration sync) if narration is actively
  /// playing. Called from explicit user/app navigation entry points.
  ///
  /// Only transitions when sync is currently enabled and a timebased navigator
  /// is present and playing, so normal reading without narration is unaffected.
  @MainActor
  func enterManualModeIfNarrationPlaying() {
    guard narrationSyncEnabled,
          FlutterReadiumPlugin.instance?.timebasedNavigator != nil,
          FlutterReadiumPlugin.instance?.lastTimebasedPlayerState?.state == .playing else {
      return
    }
    Log.reader.debug("enterManualModeIfNarrationPlaying: entering manual mode")
    setNarrationSyncEnabled(false)
  }

  private func emitOnPageChanged() {
    guard let locator = readiumViewController.currentLocation else {
      Log.reader.warn("emitOnPageChanged: currentLocation was nil!")
      return
    }

    navigator(readiumViewController, locationDidChange: locator)
  }

  func goBackwardInScrollMode(options: NavigatorGoOptions) async -> Bool {
    guard var locator = getCurrentLocation(),
          let currentProgression = locator.locations.progression else {
      Log.reader.error("no current location or progression")
      return false
    }
    let jsResult = await self.evaluateJavascript("window.flutterReadium.getViewPortSize();")
    guard case .success(let viewPortResult) = jsResult,
          let viewPortMap = viewPortResult as? Dictionary<String, Any> else {
      Log.reader.error("getViewPortSize JS eval failed – \(jsResult.getOrNil() ?? "nil")")
      return false
    }
    let viewPort = ViewPortSize.fromJson(viewPortMap, scrollMode: true)
    let progression = viewPort.progression
    let prevProgression = viewPort.prevProgression
    if (progression == 0.0 && prevProgression <= 0.0) {
      // Current progress is already at the top and prevProgression is <= 0.0,
      // We need to go to the previous file in the readingOrder.
      Log.reader.debug("at beginning, use default goBackward")
      return await self.readiumViewController.goBackward(options: options)
    }

    Log.reader.debug("goBackward from progression:\(currentProgression) to \(prevProgression)")
    locator.locations.progression = clamp(prevProgression, minValue: 0.0, maxValue: 1.0)
    return await self.readiumViewController.go(to: locator, options: options)
  }

  func goForwardInScrollMode(options: NavigatorGoOptions) async -> Bool {
    guard var locator = getCurrentLocation(),
          let currentProgression = locator.locations.progression else {
      Log.reader.error("no current location or progression")
      return false
    }
    let jsResult = await self.evaluateJavascript("window.flutterReadium.getViewPortSize();")
    guard case .success(let viewPortResult) = jsResult,
          let viewPortMap = viewPortResult as? Dictionary<String, Any> else {
      Log.reader.error("getViewPortSize JS eval failed – \(jsResult.getOrNil() ?? "nil")")
      return false
    }
    let viewPort = ViewPortSize.fromJson(viewPortMap, scrollMode: true)

    let endProgression = viewPort.endProgression
    let nextProgression = viewPort.nextProgression
    if (nextProgression >= 1.0 && endProgression == 1.0) {
      // Current progress is already at the top and prevProgression is <= 0.0,
      // We need to go to the previous file in the readingOrder.
      Log.reader.debug("at end, use default goForward")
      return await self.readiumViewController.goForward(options: options)
    }

    Log.reader.debug("goForward from progression:\(currentProgression) to \(nextProgression)")
    locator.locations.progression = clamp(nextProgression, minValue: 0.0, maxValue: 1.0)
    return await self.readiumViewController.go(to: locator, options: options)
  }
}
