import Foundation
import ReadiumNavigator
import ReadiumShared

private let jsonEncoder = JSONEncoder()

/// Applying reader preferences (custom CSS variables, DiViNa iframe propagation)
/// and the media-overlay column-break-prevention CSS that's gated by them.
extension EPUBReaderView {

  func setUserPreferences(preferences: FlutterEPUBPreferences) {
    self.preferences = preferences
    self.readiumViewController.submitPreferences(preferences.readium)
    self.updateCustomPreferences(preferences)
    applyColumnBreakPrevention()
  }

  /// Resolves preferences against the publication's layout. The first-element top
  /// margin is a reflowable-text affordance, so it's dropped for every non-reflowable
  /// publication — FXL EPUBs and paginated DiViNa report `.fixed`, scrolled DiViNa
  /// reports `.scrolled`, and image publications (CBZ via ImageParser) report no
  /// layout at all — where it would otherwise shift the full-page content down.
  func effectivePreferences(_ preferences: FlutterEPUBPreferences) -> FlutterEPUBPreferences {
    guard publication.metadata.layout != .reflowable else { return preferences }
    var resolved = preferences
    resolved.firstElementTopMargin = nil
    return resolved
  }

  func updateCustomPreferences(_ preferences: FlutterEPUBPreferences) {
    let cssVariables = effectivePreferences(preferences).toCustomCssVariables()

    guard cssVariables.isEmpty == false,
          let jsonData = try? jsonEncoder.encode(cssVariables),
          let jsonString = String(data: jsonData, encoding: .utf8) else { return }

    Task.detached(priority: .high) { [jsonString] in
      let result = await self.readiumViewController.evaluateJavaScript("readium.setCSSProperties(\(jsonString));")
      Log.reader.info("updated custom preferences: \(result)")
    }

    // For CBZ/DiViNa FXL publications, also propagate CSS vars to the inner
    // iframe. The FXL wrapper (fxl-spread-one.html) exposes window.spread.eval("", code)
    // which runs JS in the iframe's context. This ensures dynamic preference
    // updates (e.g. toggling B&W mode mid-read) reach the image iframe.
    if publication.conforms(to: Publication.Profile.divina) {
      let innerScript = cssVariables.map { k, v in
        if let v { "document.documentElement.style.setProperty('\(k)','\(v)','important');" }
        else { "document.documentElement.style.removeProperty('\(k)');" }
      }.joined()
      if let scriptData = try? jsonEncoder.encode(innerScript),
         let scriptJson = String(data: scriptData, encoding: .utf8) {
        Task.detached(priority: .high) { [scriptJson] in
          await self.readiumViewController.evaluateJavaScript("window.spread?.eval?.('',\(scriptJson));")
        }
      }
    }
  }

  /// MO-only: prevents CSS columns from splitting a paragraph during sync playback.
  /// Not related to `PageBreakSkippingContentIteratorFactory` (TTS-only, content-iteration).
  public func setMOActive(_ active: Bool) {
    isMOActive = active
    applyColumnBreakPrevention()
  }

  private func applyColumnBreakPrevention() {
    if shouldPreventColumnBreaks {
      injectColumnBreakCSS()
    } else {
      removeColumnBreakCSS()
    }
  }

  func injectColumnBreakCSS() {
    Task.detached(priority: .high) {
      // Delegates to the helper bundle (window.flutterReadium), matching Android.
      // Optional-chained: no-op if called before the helper finishes initializing.
      await self.readiumViewController.evaluateJavaScript("window.flutterReadium?.injectMOBreakCSS();")
    }
  }

  private func removeColumnBreakCSS() {
    Task.detached(priority: .high) {
      await self.readiumViewController.evaluateJavaScript("window.flutterReadium?.removeMOBreakCSS();")
    }
  }
}
