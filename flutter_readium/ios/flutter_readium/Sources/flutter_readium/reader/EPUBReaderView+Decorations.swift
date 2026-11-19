import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit

extension Decoration.Style.Id {
  static let marginMarker: Decoration.Style.Id = "marginMarker"
}

/// Payload of a `marginMarker` decoration style. `side` is "start" or "end".
struct MarginMarkerConfig: Hashable {
  var label: String?
  var icon: String?
  var side: String
  var tint: UIColor?

  /// Icon names the template can render. Keep in sync with `MarginMarkerIcon` on the Dart side.
  static let knownIcons: Set<String> = ["bookmark"]
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

  /// Margin marker floated into the page margin. Keep the markup identical to the Android and web
  /// templates; the design is in docs/plans/margin-marker-decorations.md.
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
        if let label = config.label {
          content = Self.escapeHtmlAttr(label)
        } else if config.icon == "bookmark" {
          content = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" width=\"1em\" height=\"1em\" fill=\"currentColor\" style=\"display: block;\"><path d=\"M6 2h12a1 1 0 0 1 1 1v19l-7-4-7 4V3a1 1 0 0 1 1-1z\"/></svg>"
        } else {
          return "<div/>"
        }
        let physical = config.side == "end" ? "right" : "left"
        let logical = config.side == "end" ? "inline-end" : "inline-start"
        var css = "float: \(physical) !important; float: \(logical) !important;"
        css += " margin: 0 2px !important; padding: 0 4px !important;"
        css += " font-size: 0.75em !important; line-height: 1.4 !important;"
        css += " border: 1px solid currentColor !important; border-radius: 3px !important;"
        css += " background-color: var(--USER__backgroundColor, var(--RS__backgroundColor)) !important;"
        css += " opacity: 0.85 !important;"
        if let tint = config.tint {
          css += " color: \(tint.cssValue()) !important;"
        }
        return "<div><span data-activable=\"1\" style=\"\(css)\">\(content)</span></div>"
      }
    )
  }
}
