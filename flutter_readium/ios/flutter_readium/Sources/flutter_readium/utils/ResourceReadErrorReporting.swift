import Foundation
import ReadiumShared

/// Thread-safe, late-bindable sink for publication resource read errors.
///
/// The container wrapper is installed when the publication is opened, but the
/// audio navigator that consumes the errors is created later — hence the
/// settable handler.
public final class ResourceReadErrorObserver: @unchecked Sendable {
  private let lock = NSLock()
  private var handler: ((_ href: AnyURL, _ error: ReadError) -> Void)?

  public init() {}

  public func setHandler(_ handler: ((_ href: AnyURL, _ error: ReadError) -> Void)?) {
    lock.lock()
    defer { lock.unlock() }
    self.handler = handler
  }

  func report(href: AnyURL, error: ReadError) {
    lock.lock()
    let handler = self.handler
    lock.unlock()
    handler?(href, error)
  }
}

/// Wraps a `Container` so every `Resource` read failure is reported to the
/// observer. Needed because upstream AudioNavigator swallows AVPlayer errors.
struct ReadErrorReportingContainer: Container {
  private let wrapped: Container
  private let observer: ResourceReadErrorObserver

  init(wrapping wrapped: Container, observer: ResourceReadErrorObserver) {
    self.wrapped = wrapped
    self.observer = observer
  }

  var sourceURL: AbsoluteURL? { wrapped.sourceURL }
  var entries: Set<AnyURL> { wrapped.entries }

  subscript(url: any URLConvertible) -> Resource? {
    guard let resource = wrapped[url] else {
      return nil
    }
    return ReadErrorReportingResource(wrapping: resource, href: url.anyURL.normalized, observer: observer)
  }
}

/// Forwards reads to the wrapped `Resource`, reporting failures that block audio playback.
///
/// `properties()` is auxiliary and can fail without blocking playback, but
/// `estimatedLength()` is load-bearing for iOS audio: Readium's AVAsset loader
/// uses it to answer AVPlayer's content-information request before a range
/// stream is opened. If that request fails while offline, no `stream(range:)`
/// failure follows, so recovery must be driven from the length failure.
final class ReadErrorReportingResource: Resource {
  private let wrapped: Resource
  private let href: AnyURL
  private let observer: ResourceReadErrorObserver

  init(wrapping wrapped: Resource, href: AnyURL, observer: ResourceReadErrorObserver) {
    self.wrapped = wrapped
    self.href = href
    self.observer = observer
  }

  var sourceURL: AbsoluteURL? { wrapped.sourceURL }

  func properties() async -> ReadResult<ResourceProperties> {
    await wrapped.properties()
  }

  func estimatedLength() async -> ReadResult<UInt64?> {
    let result = await wrapped.estimatedLength()
    if case let .failure(error) = result {
      Log.navigator.debug("Audio resource estimatedLength failed for \(self.href): \(error)")
      observer.report(href: href, error: error)
    }
    return result
  }

  func stream(range: Range<UInt64>?, consume: @escaping (Data) -> Void) async -> ReadResult<Void> {
    reporting(await wrapped.stream(range: range, consume: consume))
  }

  private func reporting<T>(_ result: ReadResult<T>) -> ReadResult<T> {
    if case let .failure(error) = result {
      observer.report(href: href, error: error)
    }
    return result
  }
}
