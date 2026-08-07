# iOS Audio Streaming Error Detection + Connection Recovery Implementation Plan

> **✅ Implemented.** The iOS streaming-error classification, surfacing, and connection recovery
> work described here has since landed. This file is retained as the execution record.

> **For agentic workers:** Execute task-by-task in order; steps use checkbox (`- [ ]`) syntax for tracking. Commit at the end of each task as specified. **All manual smoke/validation steps are delegated to the user** — prepare the instructions, hand them off, and do not attempt to run the app yourself.

**Goal:** Surface remote-audio streaming failures (bad network, missing bearer token, HTTP errors) on iOS as `TimebasedState.failure` + detailed error events, with automatic connection recovery via exponential backoff.

**Architecture:** Upstream swift-toolkit `AudioNavigator` swallows all AVPlayer/resource errors (no `.failed` state, no delegate error calls). We cannot observe its private `AVPlayer`, so we intercept one layer down: wrap the publication's `Container` at open time (via the `onCreatePublication` transform the plugin already uses) so every `Resource` read failure is reported to an observer. The plugin routes those failures to `FlutterAudioNavigator`, which classifies them (retryable vs terminal), runs a bounded backoff recovery loop (tear down and rebuild the internal `AudioNavigator` at the last known locator — required because upstream never replaces a failed `AVPlayerItem` for the same resource index), and emits `failure` state + error events when recovery is exhausted.

**Tech Stack:** Swift 5.x, swift-toolkit (`ReadiumShared`, `ReadiumNavigator`), XCTest (host: `RunnerTests` in `flutter_readium/example/ios`).

## Global Constraints

- Working dir is the repo root (`flutter_readium/` is the app package inside it). All paths below are repo-relative.
- swift-toolkit pin is current — verify any upstream API against the pinned version, not `develop`.
- Build with `fvm flutter` (respects `.fvmrc`), never bare `flutter`.
- **Do NOT add new files to `flutter_readium/example/ios/RunnerTests/`** — the Xcode target lists files explicitly in `project.pbxproj`. Append new `XCTestCase` classes to the existing `RunnerTests.swift` instead.
- New plugin source files under `flutter_readium/ios/flutter_readium/Sources/flutter_readium/` are picked up automatically (SPM/podspec glob) — no project-file edits needed.
- Commits: Conventional Commits with scope, e.g. `feat(ios): …`.
- Before declaring done: `fvm flutter build ios --no-codesign` in `flutter_readium/example` must pass; `bin/format` + `bin/analyze` from repo root must be clean.
- No Dart/method-channel changes: `TimebasedState.failure` and the `dk.nota.flutter_readium/error` EventChannel already exist in the contract.
- Scope: `FlutterAudioNavigator` only. `FlutterMediaOverlayNavigator` audio errors are explicitly out of scope (note in PR description).

---

### Task 1: Error classification + backoff policy (pure logic)

**Files:**
- Create: `flutter_readium/ios/flutter_readium/Sources/flutter_readium/utils/AudioStreamErrorPolicy.swift`
- Test: `flutter_readium/example/ios/RunnerTests/RunnerTests.swift` (append test classes)

**Interfaces:**
- Produces: `enum AudioStreamErrorAction { case ignore; case retry; case fail(code: String) }`, `ReadError.audioStreamAction: AudioStreamErrorAction`, `struct AudioRecoveryPolicy { var maxAttempts: Int; func delay(forAttempt: Int) -> TimeInterval }`. Task 4 consumes all three.

- [x] **Step 1: Write the failing tests** — append to `RunnerTests.swift`:

```swift
final class AudioStreamErrorPolicyTests: XCTestCase {
  private func httpResponse(status: Int) -> HTTPResponse {
    let url = HTTPURL(string: "https://example.com/audio.mp3")!
    return HTTPResponse(
      request: HTTPRequest(url: url),
      url: url,
      status: HTTPStatus(rawValue: status),
      headers: [:],
      mediaType: nil,
      body: nil
    )
  }

  func testCancelledIsIgnored() {
    XCTAssertEqual(ReadError.cancelled.audioStreamAction, .ignore)
  }

  func testTimeoutOfflineUnreachableAreRetryable() {
    XCTAssertEqual(ReadError.access(.http(.timeout(nil))).audioStreamAction, .retry)
    XCTAssertEqual(ReadError.access(.http(.offline(nil))).audioStreamAction, .retry)
    XCTAssertEqual(ReadError.access(.http(.unreachable(nil))).audioStreamAction, .retry)
  }

  func testAuthErrorsAreTerminalWithAuthCode() {
    XCTAssertEqual(
      ReadError.access(.http(.errorResponse(httpResponse(status: 401)))).audioStreamAction,
      .fail(code: "AudioStreamAuthError"))
    XCTAssertEqual(
      ReadError.access(.http(.errorResponse(httpResponse(status: 403)))).audioStreamAction,
      .fail(code: "AudioStreamAuthError"))
  }

  func testServerErrorsAreRetryableClientErrorsAreNot() {
    XCTAssertEqual(
      ReadError.access(.http(.errorResponse(httpResponse(status: 503)))).audioStreamAction,
      .retry)
    XCTAssertEqual(
      ReadError.access(.http(.errorResponse(httpResponse(status: 404)))).audioStreamAction,
      .fail(code: "AudioStreamHTTPError"))
  }

  func testDecodingErrorIsTerminal() {
    XCTAssertEqual(
      ReadError.decoding("bad data").audioStreamAction,
      .fail(code: "AudioStreamError"))
  }
}

final class AudioRecoveryPolicyTests: XCTestCase {
  func testExponentialBackoffDelays() {
    let policy = AudioRecoveryPolicy()
    XCTAssertEqual(policy.maxAttempts, 3)
    XCTAssertEqual(policy.delay(forAttempt: 1), 1.0)
    XCTAssertEqual(policy.delay(forAttempt: 2), 2.0)
    XCTAssertEqual(policy.delay(forAttempt: 3), 4.0)
  }
}
```

Add `import ReadiumShared` to the file's imports if missing.

- [x] **Step 2: Run tests to verify they fail**

Prep once (if pods/fixtures missing, run `bin/install` first):

```bash
cd flutter_readium/example && fvm flutter build ios --no-codesign --config-only
cd ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination "platform=iOS Simulator,name=$(xcrun simctl list devices available | grep -o 'iPhone [0-9]*' | head -1)" \
  -only-testing:RunnerTests 2>&1 | tail -20
```

Expected: compile FAILURE — `audioStreamAction` / `AudioRecoveryPolicy` not defined.

- [x] **Step 3: Implement** — create `AudioStreamErrorPolicy.swift`:

```swift
import Foundation
import ReadiumShared

/// What the audio navigator should do about a resource read error.
enum AudioStreamErrorAction: Equatable {
  /// Not a real failure (e.g. cancelled reads during seeks/dispose).
  case ignore
  /// Transient network-class error: attempt connection recovery.
  case retry
  /// Terminal error: emit failure state + error event with this code.
  case fail(code: String)
}

extension ReadError {
  /// Classifies a resource read error for audio streaming purposes.
  var audioStreamAction: AudioStreamErrorAction {
    switch self {
    case .cancelled:
      return .ignore
    case let .access(access):
      switch access {
      case let .http(httpError):
        switch httpError {
        case .timeout, .unreachable, .offline, .redirection, .malformedResponse:
          return .retry
        case let .errorResponse(response):
          switch response.status.rawValue {
          case 401, 403:
            return .fail(code: "AudioStreamAuthError")
          case 500...:
            return .retry
          default:
            return .fail(code: "AudioStreamHTTPError")
          }
        default:
          return .fail(code: "AudioStreamNetworkError")
        }
      case .fileSystem:
        return .fail(code: "AudioStreamFileError")
      case .other:
        /// Unknown transport-level errors are usually network glue — worth a retry.
        return .retry
      }
    default:
      return .fail(code: "AudioStreamError")
    }
  }
}

/// Exponential backoff policy for audio stream recovery: 1s, 2s, 4s.
struct AudioRecoveryPolicy {
  var maxAttempts: Int = 3

  func delay(forAttempt attempt: Int) -> TimeInterval {
    pow(2.0, Double(max(attempt, 1) - 1))
  }
}
```

- [x] **Step 4: Run tests to verify they pass** (same command as Step 2). Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add flutter_readium/ios/flutter_readium/Sources/flutter_readium/utils/AudioStreamErrorPolicy.swift flutter_readium/example/ios/RunnerTests/RunnerTests.swift
git commit -m "feat(ios): classify audio resource read errors + recovery backoff policy"
```

---

### Task 2: Read-error reporting Container/Resource wrappers

**Files:**
- Create: `flutter_readium/ios/flutter_readium/Sources/flutter_readium/utils/ResourceReadErrorReporting.swift`
- Test: `flutter_readium/example/ios/RunnerTests/RunnerTests.swift` (append)

**Interfaces:**
- Produces: `final class ResourceReadErrorObserver` with `setHandler(((AnyURL, ReadError) -> Void)?)` and internal `report(href:error:)`; `struct ReadErrorReportingContainer: Container` with `init(wrapping: Container, observer: ResourceReadErrorObserver)`. Tasks 3–4 consume these.

- [x] **Step 1: Write the failing tests** — append to `RunnerTests.swift`:

```swift
/// Resource stub whose reads always fail with the given error.
private final class FailingResource: Resource {
  let error: ReadError
  init(error: ReadError) { self.error = error }
  var sourceURL: AbsoluteURL? { nil }
  func properties() async -> ReadResult<ResourceProperties> { .failure(error) }
  func estimatedLength() async -> ReadResult<UInt64?> { .failure(error) }
  func stream(range: Range<UInt64>?, consume: @escaping (Data) -> Void) async -> ReadResult<Void> {
    .failure(error)
  }
}

private struct SingleResourceContainer: Container {
  let href: AnyURL
  let resource: Resource
  var sourceURL: AbsoluteURL? { nil }
  var entries: Set<AnyURL> { [href] }
  subscript(url: any URLConvertible) -> Resource? {
    url.anyURL.normalized == href ? resource : nil
  }
}

final class ResourceReadErrorReportingTests: XCTestCase {
  func testStreamFailureIsReportedWithHref() async {
    let href = AnyURL(string: "https://example.com/ch1.mp3")!
    let observer = ResourceReadErrorObserver()
    var reported: (AnyURL, ReadError)?
    observer.setHandler { reported = ($0, $1) }

    let container = ReadErrorReportingContainer(
      wrapping: SingleResourceContainer(href: href, resource: FailingResource(error: .access(.http(.timeout(nil))))),
      observer: observer)

    let result = await container[href]!.stream(range: nil, consume: { _ in })

    guard case .failure = result else { return XCTFail("expected failure passthrough") }
    XCTAssertEqual(reported?.0, href)
    if case .access(.http(.timeout)) = reported?.1 {} else { XCTFail("wrong error: \(String(describing: reported?.1))") }
  }

  func testSuccessIsNotReported() async {
    let href = AnyURL(string: "https://example.com/ch1.mp3")!
    let observer = ResourceReadErrorObserver()
    var reportCount = 0
    observer.setHandler { _, _ in reportCount += 1 }

    let container = ReadErrorReportingContainer(
      wrapping: SingleResourceContainer(href: href, resource: DataResource(data: Data([1, 2, 3]))),
      observer: observer)

    _ = await container[href]!.read()
    XCTAssertEqual(reportCount, 0)
  }
}
```

(`DataResource` is a `ReadiumShared` in-memory resource; if its initializer differs at 3.9.0, use another trivial always-succeeding `Resource` stub in the same style as `FailingResource`.)

- [x] **Step 2: Run tests to verify they fail** (same xcodebuild command as Task 1). Expected: compile FAILURE — types not defined.

- [x] **Step 3: Implement** — create `ResourceReadErrorReporting.swift`:

```swift
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

/// Forwards all reads to the wrapped `Resource`, reporting failures.
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
    reporting(await wrapped.properties())
  }

  func estimatedLength() async -> ReadResult<UInt64?> {
    reporting(await wrapped.estimatedLength())
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
```

- [x] **Step 4: Run tests to verify they pass.** Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add flutter_readium/ios/flutter_readium/Sources/flutter_readium/utils/ResourceReadErrorReporting.swift flutter_readium/example/ios/RunnerTests/RunnerTests.swift
git commit -m "feat(ios): container wrapper reporting resource read errors"
```

---

### Task 3: Install the wrapper at publication open

**Files:**
- Modify: `flutter_readium/ios/flutter_readium/Sources/flutter_readium/FlutterReadiumPlugin.swift` (module-scope vars ~line 13–43; `openPublication` `onCreatePublication` closure ~line 766)

**Interfaces:**
- Consumes: `ResourceReadErrorObserver`, `ReadErrorReportingContainer` (Task 2).
- Produces: module-scope `internal let resourceReadErrorObserver = ResourceReadErrorObserver()` — Task 4 registers/clears its handler.

- [x] **Step 1: Add the module-scope observer** next to the existing module-scope vars (`currentPublication`, `timebasedNavigator`):

```swift
internal let resourceReadErrorObserver = ResourceReadErrorObserver()
```

- [x] **Step 2: Wrap the container** in `openPublication`'s `onCreatePublication` closure. Current code ignores the container parameter (`{ manifest, _, services in`); change to:

```swift
onCreatePublication: { manifest, container, services in
  /// Report resource read failures (audio streaming errors are otherwise
  /// swallowed inside upstream AudioNavigator — no handler set means no-op).
  container = ReadErrorReportingContainer(wrapping: container, observer: resourceReadErrorObserver)

  if manifest.conforms(to: .epub) {
    let factory = PageBreakSkippingContentIteratorFactory()
    self.pageBreakIteratorFactory = factory
    services.setContentServiceFactory(
      DefaultContentService.makeFactory(
        resourceContentIteratorFactories: [factory]
      )
    )
  }
},
```

- [x] **Step 3: Build to verify**

```bash
cd flutter_readium/example && fvm flutter build ios --no-codesign 2>&1 | tail -5
```

Expected: `✓ Built …` (no Swift errors).

- [x] **Step 4: Commit**

```bash
git add flutter_readium/ios/flutter_readium/Sources/flutter_readium/FlutterReadiumPlugin.swift
git commit -m "feat(ios): wrap publication container to observe resource read errors"
```

---

### Task 4: Failure emission + connection recovery in FlutterAudioNavigator

**Files:**
- Modify: `flutter_readium/ios/flutter_readium/Sources/flutter_readium/navigator/FlutterAudioNavigator.swift`
- Modify: `flutter_readium/ios/flutter_readium/Sources/flutter_readium/FlutterReadiumPlugin.swift` (audio-navigator creation ~line 449; timebased dispose path)

**Interfaces:**
- Consumes: `AudioStreamErrorAction`, `ReadError.audioStreamAction`, `AudioRecoveryPolicy` (Task 1); `resourceReadErrorObserver` (Task 3); existing `FlutterReadiumPlugin.instance?.errorStreamHandler` + `FlutterReadiumError(message:code:data:)` (precedent: `FlutterTTSNavigator.swift:259`); existing `TimebasedListener.timebasedNavigator(_:didChangeState:)`.
- Produces: `@MainActor func handleResourceReadError(href: AnyURL, error: ReadError)` on `FlutterAudioNavigator`.

- [x] **Step 1: Refactor navigator creation for reuse.** In `FlutterAudioNavigator.swift`, replace the body of `initNavigator()` and add `makeAudioNavigator`:

```swift
public func initNavigator() async -> Void {
  _audioNavigator = await makeAudioNavigator(initialLocation: initialLocator)

  self.setupNavigatorStateListeners()

  Task {
    cover = try? await publication.cover().get()
  }
}

@MainActor
private func makeAudioNavigator(initialLocation: Locator?) -> AudioNavigator {
  let navigator = AudioNavigator(
    publication: publication,
    initialLocation: initialLocation,
    config: AudioNavigator.Configuration(
      preferences: AudioPreferences(fromFlutterPrefs: _preferences),
      playbackRefreshInterval: _preferences.updateIntervalSecs,
    )
  )
  navigator.delegate = self
  return navigator
}
```

- [x] **Step 2: Add recovery state + error handling.** Add members and functions to `FlutterAudioNavigator` (near the `// MARK: Internal AudioNavigator API` section):

```swift
internal var _recoveryTask: Task<Void, Never>?
internal let _recoveryPolicy = AudioRecoveryPolicy()

/// Entry point for resource read errors routed from the plugin.
@MainActor
public func handleResourceReadError(href: AnyURL, error: ReadError) {
  /// Only react to failures of this publication's audio resources.
  guard publication.readingOrder.firstWithHREF(href) != nil else {
    return
  }
  /// Already in terminal failure — client must call play() to retry.
  if _lastTimebasedPlayerState?.state == .failure {
    return
  }

  switch error.audioStreamAction {
  case .ignore:
    return
  case let .fail(code):
    enterFailureState(error: error, code: code, description: "Resource read failed: \(href)")
  case .retry:
    startRecovery(href: href, error: error)
  }
}

@MainActor
private func startRecovery(href: AnyURL, error: ReadError) {
  guard _recoveryTask == nil else {
    return  // recovery already in progress
  }
  let resumeLocator = (audioLocator ?? _audioNavigator?.currentLocation)?.copyWithOffset(playback.time)

  _recoveryTask = Task { @MainActor in
    defer { _recoveryTask = nil }

    for attempt in 1..._recoveryPolicy.maxAttempts {
      sendErrorEvent(
        code: "AudioStreamRetry",
        message: error.localizedDescription,
        data: "attempt=\(attempt)/\(_recoveryPolicy.maxAttempts) href=\(href)")
      submitRecoveryState(.loading, locator: resumeLocator)

      try? await Task.sleep(nanoseconds: UInt64(_recoveryPolicy.delay(forAttempt: attempt) * 1_000_000_000))
      if Task.isCancelled { return }

      await rebuildNavigator(at: resumeLocator)

      if await playbackAdvanced(withinSeconds: 5) {
        return  // recovered — regular state emissions resume via delegate
      }
    }

    enterFailureState(
      error: error,
      code: "AudioStreamFailed",
      description: "Recovery failed after \(_recoveryPolicy.maxAttempts) attempts: \(href)")
  }
}

/// Tears down and rebuilds the upstream navigator. Required for recovery:
/// upstream never replaces a failed AVPlayerItem for the same resource index.
@MainActor
private func rebuildNavigator(at locator: Locator?) async {
  _audioNavigator?.pause()
  _audioNavigator?.delegate = nil
  _audioNavigator = makeAudioNavigator(initialLocation: locator ?? initialLocator)
  _audioNavigator?.play()
}

/// True once playback time advances past its pre-check value while playing.
/// (`state == .playing` alone is unreliable: with
/// `automaticallyWaitsToMinimizeStalling = false` a stalled player can report
/// a playing timeControlStatus.)
@MainActor
private func playbackAdvanced(withinSeconds timeout: TimeInterval) async -> Bool {
  let startTime = playback.time
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline, !Task.isCancelled {
    if playback.state == .playing, playback.time > startTime + 0.1 {
      return true
    }
    try? await Task.sleep(nanoseconds: 500_000_000)
  }
  return false
}

@MainActor
internal func enterFailureState(error: Error, code: String, description: String) {
  Log.navigator.error("Audio streaming failure [\(code)]: \(description) — \(error)")
  _audioNavigator?.pause()
  sendErrorEvent(code: code, message: error.localizedDescription, data: description)
  submitRecoveryState(.failure, locator: audioLocator)
}

@MainActor
private func submitRecoveryState(_ state: TimebasedState, locator: Locator?) {
  let timebasedState = ReadiumTimebasedState(state: state, currentLocator: locator?.toClientFriendlyLocator())
  if timebasedState != _lastTimebasedPlayerState {
    _lastTimebasedPlayerState = timebasedState
    listener?.timebasedNavigator(self, didChangeState: timebasedState)
  }
}

private func sendErrorEvent(code: String, message: String, data: String?) {
  FlutterReadiumPlugin.instance?.errorStreamHandler?.sendEvent(
    FlutterReadiumError(message: message, code: code, data: data).toJsonString())
}
```

- [x] **Step 3: Make client-initiated retry work after failure.** In `play(fromLocator:)`, a rebuild is required because the failed `AVPlayerItem` is never replaced by upstream `go(to:)` for the same resource. Replace the body's start:

```swift
public func play(fromLocator: Locator?) async -> Void {
  if _lastTimebasedPlayerState?.state == .failure {
    _recoveryTask?.cancel()
    _recoveryTask = nil
    await rebuildNavigator(at: resolveLocator(fromLocator) ?? audioLocator)
  } else if let locator = resolveLocator(fromLocator) {
    let _ = await seek(toLocator: locator)
  }
  _audioNavigator?.play()
  // … keep existing _nowPlayingUpdater calls unchanged …
}
```

- [x] **Step 4: Clean up in dispose().** Add at the top of `dispose()`:

```swift
_recoveryTask?.cancel()
_recoveryTask = nil
```

- [x] **Step 5: Route observer → navigator in the plugin.** In `FlutterReadiumPlugin.swift`, right after the audio navigator is created and its listener set (`self.timebasedNavigator = await FlutterAudioNavigator(…)` at ~line 449, after `self.timebasedNavigator?.listener = self`):

```swift
resourceReadErrorObserver.setHandler { href, error in
  Task { @MainActor in
    guard let audioNavigator = timebasedNavigator as? FlutterAudioNavigator else { return }
    audioNavigator.handleResourceReadError(href: href, error: error)
  }
}
```

> **Deviation:** the closure above (as written) does not compile — `timebasedNavigator` is an instance property, and a Swift closure that captures it must do so explicitly. Implemented as `resourceReadErrorObserver.setHandler { [weak self] href, error in ... guard let audioNavigator = self?.timebasedNavigator as? FlutterAudioNavigator ... }`, capturing `self` weakly since the module-scope `resourceReadErrorObserver` singleton otherwise outlives (and would retain) the plugin instance.

Then find where the timebased navigator is torn down (grep `timebasedNavigator?.dispose()` / `timebasedNavigator = nil` in the plugin) and add `resourceReadErrorObserver.setHandler(nil)` beside it.

> There are two teardown sites: the `"stop"` method-channel case (tears down the timebased navigator only, publication stays open — handler is deliberately left wired so a later `play` still routes errors) and `closePublication` (full publication-scoped teardown). Added `resourceReadErrorObserver.setHandler(nil)` at `closePublication` only, since that's where the wrapped container's publication itself goes out of scope.

- [x] **Step 6: Build + run all tests**

```bash
cd flutter_readium/example && fvm flutter build ios --no-codesign 2>&1 | tail -5
cd ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination "platform=iOS Simulator,name=$(xcrun simctl list devices available | grep -o 'iPhone [0-9]*' | head -1)" \
  -only-testing:RunnerTests 2>&1 | tail -10
```

Expected: build succeeds, all RunnerTests PASS.

- [x] **Step 7: Commit**

```bash
git add flutter_readium/ios/flutter_readium/Sources/flutter_readium/navigator/FlutterAudioNavigator.swift flutter_readium/ios/flutter_readium/Sources/flutter_readium/FlutterReadiumPlugin.swift
git commit -m "feat(ios): audio streaming failure events + connection recovery with backoff"
```

---

### Task 5: User validation handoff, changelog, final validation

**Files:**
- Modify: `CHANGELOG.md` (Unreleased)
- Test: **manual smoke is delegated to the user** — do NOT run the example app yourself; produce the checklist below and stop for their verdict.

- [ ] **Step 1: Hand the smoke-test checklist to the user.** Present exactly this, then wait for their result before claiming the feature verified:

> **Manual validation checklist (iOS simulator/device, example app):**
>
> 1. **Auth/terminal failure path:** Open a remote audiobook whose audio URLs require a bearer token, with the token omitted/corrupted (or point a webpub's audio at an unreachable host to exercise the network path). Press play. Expected on the error stream / logs:
>    - `AudioStreamRetry` event per attempt (network path), then `AudioStreamFailed` — or immediate `AudioStreamAuthError` on 401/403,
>    - a timebased-state event with `"state":"failure"`,
>    - pressing play again retries from the last position.
> 2. **Recovery path:** Start a working remote audiobook, kill network mid-stream for ~5 s (Network Link Conditioner "100% Loss" or toggle Wi-Fi), restore. Expected: `AudioStreamRetry` event(s), then playback resumes by itself near the same position.

- [ ] **Step 2: Record the user's verdict.** In the final report, state per path: user-confirmed / user-reported-broken / not validated. **Do not claim verification the user has not confirmed.** If the user reports a failure, fix it before proceeding to Step 3.
- [ ] **Step 3: Changelog** — add under `## [Unreleased]`:

```markdown
### Fixed

- iOS: audio streaming failures (network errors, HTTP/auth errors on remote audio resources) are now emitted on the error stream and as `TimebasedState.failure`, instead of being silently swallowed (parity with Android).

### Added

- iOS: automatic connection recovery for transient audio streaming failures (3 attempts, exponential backoff), with `AudioStreamRetry`/`AudioStreamFailed`/`AudioStreamAuthError` error events.
```

- [ ] **Step 4: Final validation**

```bash
bin/format && bin/analyze
cd flutter_readium/example && fvm flutter build ios --no-codesign 2>&1 | tail -3
```

Expected: all clean.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for iOS audio streaming error handling"
```

---

## Out of scope / known limitations (state these in the PR description)

- `FlutterMediaOverlayNavigator` (EPUB media overlays) has the same upstream blindness — not addressed here.
- The container wrapper also observes EPUB resource reads; the handler only reacts to hrefs in the audio reading order, everything else is a no-op.
- Rebuilding the navigator on recovery resets AVPlayer buffering; a brief gap on resume is expected.
- Proper upstream fix (AVPlayerItem status observation in swift-toolkit) is tracked in `docs/parity/upstream-audio-error-surfacing-plan.md`; once released, the detection half of this work can be simplified.
