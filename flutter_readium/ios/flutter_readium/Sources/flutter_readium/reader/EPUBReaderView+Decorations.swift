import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit

extension Decoration.Style.Id {
  static let marginMarker: Decoration.Style.Id = "marginMarker"
}

/// Payload of a `marginMarker` decoration style. `side` is "start" or "end"; `anchor` is "page" or "text".
struct MarginMarkerConfig: Hashable {
  var label: String?
  var icon: String?
  var side: String
  var anchor: String
  var tint: UIColor?

  /// SVG path data (24x24 viewBox) by `MarginMarkerIcon` name. Keep in sync with Dart, Android and web.
  static let iconPaths: [String: String] = [
    "bookmark": "M6 2h12a1 1 0 0 1 1 1v19l-7-4-7 4V3a1 1 0 0 1 1-1z",
    "note": "M4 3h16a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H9l-5 4v-4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM7 7v2h10V7zm0 4v2h7v-2z",
    "star": "M12 2l2.9 6.9 7.1.6-5.4 4.7 1.6 7-6.2-3.8-6.2 3.8 1.6-7L2 9.5l7.1-.6z",
  ]
}

/// Decoration application, decoration-interaction observation, the custom
/// "highlight current selection" editing action, and the spotlight and margin
/// marker decoration templates.
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
  /// AGENTS.md); without `!important` the fill would be invisible.
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

  /// Margin marker floated into the page margin, or placed next to the text for the "text" anchor. Keep
  /// the markup identical to the Android and web templates; the design is in docs/plans/margin-marker-decorations.md.
  static func marginMarkerDecorationTemplate() -> HTMLDecorationTemplate {
    HTMLDecorationTemplate(
      layout: .bounds,
      width: .page,
      element: { decoration in
        guard let config = decoration.style.config as? MarginMarkerConfig else {
          Log.reader.error("marginMarkerDecorationTemplate: unexpected style config")
          return "<div/>"
        }
        let content: String
        // Labels are muted like printed margin page numbers; icons keep the full colour.
        var opacity = ""
        if let label = config.label {
          content = Self.escapeHtmlAttr(label)
          opacity = " opacity: 0.8 !important;"
        } else if let path = config.icon.flatMap({ MarginMarkerConfig.iconPaths[$0] }) {
          content = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" width=\"1.3em\" height=\"1.3em\" fill=\"currentColor\" fill-rule=\"evenodd\" style=\"display: block;\"><path d=\"\(path)\"/></svg>"
        } else {
          return "<div/>"
        }
        let end = config.side == "end"
        var css = " font-size: 0.75em !important; line-height: 1.4 !important;" + opacity
        if let tint = config.tint {
          css += " color: \(tint.cssValue()) !important;"
        }
        if config.anchor == "text" {
          // The cell is as wide as the margin, which flutterReadiumTools.js measures. The marker is pushed
          // against the cell's text side; in a too-narrow margin it overflows toward the text, never off the page.
          let cell = "display: flex !important; flex-direction: \(end ? "row-reverse" : "row") !important;"
            + " box-sizing: border-box !important; width: var(--flutter-readium-text-inset-\(end ? "end" : "start"), 0px) !important;"
            + " padding-inline: \(end ? "0.5em 4px" : "4px 0.5em") !important;\(end ? " margin-inline-start: auto !important;" : "")"
          let push = "margin-\(end ? "inline-end" : "inline-start"): auto !important; flex: none !important;"
          return "<div><div style=\"\(cell)\"><span data-activable=\"1\" style=\"\(push)\(css)\">\(content)</span></div></div>"
        }
        let float = "float: \(end ? "right" : "left") !important; float: \(end ? "inline-end" : "inline-start") !important;"
          + " margin: 0 max(4px, 1.5%) !important;"
        return "<div><span data-activable=\"1\" style=\"\(float)\(css)\">\(content)</span></div>"
      }
    )
  }
}
