import ReadiumNavigator
import ReadiumShared

/// Decoration application, decoration-interaction observation, the custom
/// "highlight current selection" editing action, and the spotlight decoration
/// template used for TTS utterance highlighting.
extension EPUBReaderView {

  public func applyDecorations(_ decorations: [Decoration], forGroup groupIdentifier: String) {
    Log.reader.debug("applyDecorations: \(decorations) identifier: \(groupIdentifier)")
    ensureDecorationObservation(forGroup: groupIdentifier)
    self.readiumViewController.apply(decorations: decorations, in: groupIdentifier)
  }

  @objc public func onCustomEditingAction() {
    Log.reader.debug("onCustomEditingAction")
    // NOTE: This method will not actually be hit. It will try to find an "onCustomEditingAction" function in the Responder chain!
    // Because of how Flutter generates its responder chain, we need to implement this func in the client AppDelegate.swift and then call back into the plugin from there.
    // see https://github.com/readium/swift-toolkit/issues/466

    if let selection = readiumViewController.currentSelection {
      let selectionLocator = selection.locator
      readiumViewController.apply(decorations: [Decoration(id: "highlight", locator: selectionLocator, style: .highlight(), userInfo: [:])], in: "user-highlight")
      readiumViewController.clearSelection()
    }
  }

  /// Called when a decoration is tapped/activated by the user.
  func onDecorationActivated(event: OnDecorationActivatedEvent) {
    Log.reader.debug("onDecorationActivated: \(event.decoration.id) in group \(event.group)")
    channel.onDecorationInteraction(
      decorationId: event.decoration.id,
      group: event.group,
      type: "tap",
      locator: event.decoration.locator
    )
  }

  /// Registers decoration interaction observation for a group.
  /// Called when `applyDecorations` is used with a new group identifier.
  private func ensureDecorationObservation(forGroup group: String) {
    guard !observedDecorationGroups.contains(group) else { return }
    observedDecorationGroups.insert(group)
    readiumViewController.observeDecorationInteractions(inGroup: group) { [weak self] event in
      self?.onDecorationActivated(event: event)
    }
  }

  // MARK: – Custom decoration templates

  /// Escape a string for use as an HTML attribute value (double-quoted).
  private static func escapeHtmlAttr(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "\"", with: "&quot;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
  }

  /// Spotlight: semi-transparent tinted box over the active text range, one per
  /// text line.
  ///
  /// Uses `.boxes` layout (one `<div>` per CSS border box / text line) so that
  /// utterances spanning CSS columns are represented by per-line boxes each
  /// contained within their own column. `.bounds` would produce a single rectangle
  /// spanning the bounding box of the whole range, which overflows across the gutter
  /// and into the next column when an utterance crosses a column boundary.
  ///
  /// The class `flutter-readium-spotlight` is a stable marker that
  /// `flutterReadiumTools.js` watches via MutationObserver to:
  ///   1. Toggle `body.flutter-readium-spotlight-active`, which fades all body text
  ///      to low contrast via an injected CSS rule.
  ///   2. Read `data-css-selector` and add `.flutter-readium-spotlit-text` to the
  ///      matching element, so a higher-specificity CSS rule restores its text colour.
  ///
  /// `background-color` MUST be `!important`: Readium CSS forces every element's
  /// background to transparent when a custom theme is active (see Gotcha in
  /// CLAUDE.md); without `!important` the fill would be invisible.
  ///
  /// `z-index: -1` renders the fill behind the text glyphs (same as the upstream
  /// highlight/underline templates). This keeps the text colour
  /// visually unaffected by the tint overlay and matches what `::highlight()` does
  /// on web — the yellow acts purely as a background, not a colour wash.
  static func spotlightDecorationTemplate() -> HTMLDecorationTemplate {
    HTMLDecorationTemplate(
      layout: .boxes,
      width: .bounds,
      element: { decoration in
        let config = decoration.style.config as! Decoration.Style.HighlightConfig
        let bgColor = config.tint.map { "\($0.cssValue(alpha: 0.5))" } ?? "transparent"
        let sel = Self.escapeHtmlAttr(decoration.locator.locations.cssSelector ?? "")
        let hl  = Self.escapeHtmlAttr(decoration.locator.text.highlight ?? "")
        let bef = Self.escapeHtmlAttr(decoration.locator.text.before ?? "")
        return "<div class=\"flutter-readium-spotlight\" data-css-selector=\"\(sel)\" data-text-highlight=\"\(hl)\" data-text-before=\"\(bef)\" data-tint=\"\(bgColor)\" style=\"z-index: -1; box-sizing: border-box;\"/>"
      }
    )
  }
}
