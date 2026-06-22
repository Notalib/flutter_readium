import Foundation

/// Single source of truth for the `t=<seconds>` media time fragment carried by
/// audio Locators.
///
/// Building and parsing this fragment used to be duplicated across the
/// media-overlay model, the audio navigator, and the `Locator` extensions —
/// each one re-implementing the `t=` format by hand. A stray character in one
/// of those hand-built strings (`"t=\(start))"`) silently produced an
/// unparseable fragment that round-tripped to `nil` and crashed a downstream
/// force-unwrap. Routing every construction and parse site through this helper
/// collapses that surface to one place, so the format can only ever be wrong
/// here — where a round-trip test and the strict-parse assertion guard it.
enum MediaTimeFragment {
  private static let prefix = "t="

  /// Builds the canonical `t=<seconds>` fragment at full precision.
  static func string(_ seconds: Double) -> String {
    "\(prefix)\(seconds)"
  }

  /// Parses a single fragment into its `(start, end?)` range, tolerating an
  /// optional `npt:` prefix and a `start,end` pair.
  ///
  /// Lenient: returns `nil` for anything that isn't a `t=` fragment or whose
  /// start doesn't parse. Safe to call on arbitrary, externally-sourced
  /// fragments (e.g. from a publication manifest) without asserting.
  static func range(from fragment: String) -> (start: Double, end: Double?)? {
    guard fragment.hasPrefix(prefix) else { return nil }
    let body = fragment.removingPrefix(prefix).removingPrefix("npt:")
    let parts = body.split(separator: ",", maxSplits: 1).map(String.init)
    guard let first = parts.first, let start = Double(first) else { return nil }
    let end = parts.count > 1 ? Double(parts[1]) : nil
    return (start, end)
  }

  /// Returns the start time of the first `t=` fragment in `fragments`, or `nil`
  /// if none is present.
  ///
  /// Strict variant: a `t=` fragment that is *present but unparseable* is a bug
  /// in our own fragment construction (every audio Locator we emit is built via
  /// `string(_:)`), so it trips an `assertionFailure` in debug/test builds —
  /// turning a future malformed-fragment regression into a loud, local failure
  /// at the parse site instead of a silent `nil` that crashes far away. Release
  /// builds degrade gracefully to `nil`.
  static func seconds(from fragments: [String]) -> Double? {
    guard let fragment = fragments.first(where: { $0.hasPrefix(prefix) }) else {
      return nil
    }
    guard let start = range(from: fragment)?.start else {
      assertionFailure("Malformed media time fragment in Locator: \(fragment)")
      return nil
    }
    return start
  }
}
