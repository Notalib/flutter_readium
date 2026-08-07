# Upstream swift-toolkit AudioNavigator Error Surfacing — PR Implementation Plan

> **For agentic workers:** Execute task-by-task in order; steps use checkbox (`- [ ]`) syntax for tracking. Commit at the end of each task as specified. **All manual smoke/validation steps are delegated to the user** — prepare the instructions, hand them off, and do not attempt to run the app yourself.

**Goal:** Contribute a non-breaking PR to [readium/swift-toolkit](https://github.com/readium/swift-toolkit) so `AudioNavigator` reports streaming/playback failures to its delegate instead of silently swallowing them.

**Architecture:** Today `MediaPlaybackState` is only `{paused, loading, playing}`; `PublicationMediaLoader` correctly fails `AVAssetResourceLoadingRequest`s (putting the `AVPlayerItem` in `.failed`), but `AudioNavigator` observes neither `AVPlayerItem.status` nor `.AVPlayerItemFailedToPlayToEndTime`, and its `go(to:)` catch only logs. The fix: (a) a read-failure callback on `PublicationMediaLoader`, (b) `AVPlayerItem` failure observation in `AudioNavigator`, (c) a new optional `AudioNavigatorDelegate` method `navigator(_:didFailWithError:)` with a default no-op implementation — fully source-compatible.

**Tech Stack:** Swift, AVFoundation, swift-toolkit repo conventions (target branch `develop`), XCTest.

## Global Constraints

- **This plan works in a separate repo** — clone to `~/code/readium/swift-toolkit` (do NOT do this work inside the flutter_readium repo).
- Target branch: `develop` (swift-toolkit's integration branch). Read `CONTRIBUTING.md` in the cloned repo first and follow anything it adds (changelog format, lint, commit style).
- Non-breaking API only: new delegate requirements must have default implementations in a protocol extension.
- Match upstream code style exactly (4-space indent, `log(.error, …)`, doc comments on public API).
- **STOP and confirm with the user before pushing the fork branch or opening the issue/PR** (outward-facing actions).
- Originally written against tag `3.9.0`; rebase mentally onto current `develop` — if the touched code moved, adapt but keep the design.

---

### Task 1: Setup — clone, branch, baseline build

**Files:** none (environment setup)

- [ ] **Step 1: Clone and branch**

```bash
mkdir -p ~/code/readium && cd ~/code/readium
gh repo clone readium/swift-toolkit && cd swift-toolkit
git checkout develop
git checkout -b fix/audio-navigator-error-surfacing
cat CONTRIBUTING.md
```

- [ ] **Step 2: Baseline build + tests.** Check for a `Makefile` (`make help` / `cat Makefile`); if it defines test targets, use those. Otherwise:

```bash
xcodebuild build -scheme ReadiumNavigator -destination "generic/platform=iOS Simulator" 2>&1 | tail -3
xcodebuild test -scheme ReadiumShared -destination "platform=iOS Simulator,name=$(xcrun simctl list devices available | grep -o 'iPhone [0-9]*' | head -1)" 2>&1 | tail -5
```

Expected: baseline build/tests pass before any change. Record the exact commands that worked — reuse them in later tasks.

---

### Task 2: Read-failure callback on PublicationMediaLoader

**Files:**
- Modify: `Sources/Navigator/Audiobook/PublicationMediaLoader.swift`

**Interfaces:**
- Produces: `var onReadFailure: ((_ href: AnyURL, _ error: ReadError) -> Void)?` on `PublicationMediaLoader` (internal type — no public API change). Task 3 consumes it.

- [ ] **Step 1: Add the callback property** near the top of the class:

```swift
/// Called when reading a publication resource failed while serving an
/// AVAsset loading request. The player will end up stalled or its item
/// `.failed`; this callback preserves the underlying `ReadError` cause.
var onReadFailure: ((_ href: AnyURL, _ error: ReadError) -> Void)?
```

- [ ] **Step 2: Invoke it from both failure branches.** In `fillInfo(_:of:using:link:)`:

```swift
case let .failure(error):
    log(.error, error)
    onReadFailure?(link.url().anyURL.normalized, error)
    request.finishLoading(with: error)
```

In `fillData(_:of:using:link:)` (inside the `queue.async` switch):

```swift
case let .failure(error):
    onReadFailure?(link.url().anyURL.normalized, error)
    request.finishLoading(with: error)
```

- [ ] **Step 3: Build** (commands from Task 1). Expected: compiles.

- [ ] **Step 4: Commit**

```bash
git add Sources/Navigator/Audiobook/PublicationMediaLoader.swift
git commit -m "Report resource read failures from PublicationMediaLoader"
```

---

### Task 3: AudioNavigator failure observation + delegate API

**Files:**
- Modify: `Sources/Navigator/Audiobook/AudioNavigator.swift`

**Interfaces:**
- Consumes: `PublicationMediaLoader.onReadFailure` (Task 2).
- Produces (public API):
  - `enum AudioNavigatorError: Error { case readFailed(href: AnyURL, cause: ReadError); case playbackFailed(href: AnyURL?, cause: Error?) }`
  - `AudioNavigatorDelegate.navigator(_:didFailWithError:)` with default no-op.

- [ ] **Step 1: Add the error type** (top of file, near `MediaPlaybackState`):

```swift
/// Error occurring while loading or playing an audio resource.
public enum AudioNavigatorError: Error {
    /// Failed reading a publication resource while streaming it.
    case readFailed(href: AnyURL, cause: ReadError)

    /// The `AVPlayer` item failed with an unrecoverable error.
    case playbackFailed(href: AnyURL?, cause: Error?)
}
```

- [ ] **Step 2: Extend the delegate protocol** (add to `AudioNavigatorDelegate` and its extension):

```swift
/// Called when an error occurred while loading or playing the audio.
func navigator(_ navigator: AudioNavigator, didFailWithError error: AudioNavigatorError)
```

Default implementation in the existing `public extension AudioNavigatorDelegate`:

```swift
func navigator(_ navigator: AudioNavigator, didFailWithError error: AudioNavigatorError) {}
```

- [ ] **Step 3: Wire the media loader.** Change the `mediaLoader` lazy var:

```swift
private lazy var mediaLoader: PublicationMediaLoader = {
    let loader = PublicationMediaLoader(publication: publication)
    loader.onReadFailure = { [weak self] href, error in
        self?.notifyFailure(.readFailed(href: href, cause: error))
    }
    return loader
}()
```

- [ ] **Step 4: Observe AVPlayerItem failures.** Add near the other observers:

```swift
private var itemStatusObserver: NSKeyValueObservation?

/// Ensures a single failure notification per player item.
private var notifiedFailureForCurrentItem = false

private func observeItemStatus(of item: AVPlayerItem?) {
    notifiedFailureForCurrentItem = false
    itemStatusObserver = item?.observe(\.status, options: [.new]) { [weak self] item, _ in
        guard item.status == .failed else {
            return
        }
        self?.notifyItemFailure(item.error)
    }
}

private func notifyItemFailure(_ cause: Error?) {
    guard !notifiedFailureForCurrentItem else {
        return
    }
    notifiedFailureForCurrentItem = true
    let href = publication.readingOrder.getOrNil(resourceIndex)?.url().anyURL.normalized
    notifyFailure(.playbackFailed(href: href, cause: cause))
}

private func notifyFailure(_ error: AudioNavigatorError) {
    log(.error, error)
    Task { @MainActor in
        self.delegate?.navigator(self, didFailWithError: error)
    }
}
```

(If `getOrNil` isn't available from `ReadiumInternal` here, use `publication.readingOrder.indices.contains(resourceIndex) ? publication.readingOrder[resourceIndex] … : nil`.)

Hook it up in the `player` lazy var — extend the existing `currentItemObserver`:

```swift
currentItemObserver = player.observe(\.currentItem, options: [.new, .old]) { [weak self] player, _ in
    self?.observeItemStatus(of: player.currentItem)
    self?.playbackDidChange()
}
```

And add the failed-to-play notification next to the existing `AVPlayerItemDidPlayToEndTime` observer:

```swift
NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
    guard
        let self = self,
        let currentItem = player.currentItem,
        currentItem == (notification.object as? AVPlayerItem)
    else {
        return
    }
    let cause = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
    self.notifyItemFailure(cause ?? currentItem.error)
}
```

- [ ] **Step 5: Report `go(to:)` failures.** In the `catch` of `go(to locator:options:)`:

```swift
} catch {
    log(.error, error)
    notifyFailure(.playbackFailed(href: locator.href.anyURL.normalized, cause: error))
    return false
}
```

- [ ] **Step 6: Build** (commands from Task 1). Expected: `ReadiumNavigator` compiles; existing tests still pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/Navigator/Audiobook/AudioNavigator.swift
git commit -m "Surface playback and resource errors from AudioNavigator to its delegate"
```

---

### Task 4: Tests

**Files:**
- Create or extend under `Tests/NavigatorTests/` (inspect existing layout first: `ls Tests/NavigatorTests/`; follow the closest existing pattern).

**Interfaces:**
- Consumes: `AudioNavigatorError`, `AudioNavigatorDelegate.navigator(_:didFailWithError:)` (Task 3).

- [ ] **Step 1: Compile-time default-implementation test.** A delegate conformer that does NOT implement the new method must compile (proves non-breaking):

```swift
import ReadiumNavigator
import ReadiumShared
import XCTest

class AudioNavigatorDelegateCompatibilityTests: XCTestCase {
    /// Conforms without implementing didFailWithError — compiling is the test.
    @MainActor
    private class MinimalDelegate: AudioNavigatorDelegate {
        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {}
        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}
        func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: RelativeURL, withError error: ReadError) {}
    }

    func testDelegateDefaultImplementationExists() {
        XCTAssertNotNil(MinimalDelegate.self)
    }
}
```

(Adjust `MinimalDelegate` to whatever `NavigatorDelegate` actually requires on `develop` — the point is: it must not need `didFailWithError`.)

- [ ] **Step 2: (best-effort) PublicationMediaLoader callback test.** `AVAssetResourceLoadingRequest` cannot be constructed in tests, so test the observable seam instead: build a `Publication` whose reading-order resource always fails, call `makeAsset(for:)`, and start an `AVPlayer` on it briefly; assert `onReadFailure` fires. If sandboxed AVPlayer in CI makes this flaky, **drop this test and note it in the PR description** — do not ship a flaky test upstream.

- [ ] **Step 3: Run the test suite** (commands recorded in Task 1). Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Tests/
git commit -m "Test AudioNavigatorDelegate source compatibility"
```

---

### Task 5: Changelog + PR

**Files:**
- Modify: `CHANGELOG.md` (repo root; follow its existing format/section for unreleased changes)

- [ ] **Step 1: Changelog entry** under the unreleased "Added" section, Navigator subsection (match surrounding format):

```markdown
* `AudioNavigator` now reports resource read and playback failures to its delegate with the new `navigator(_:didFailWithError:)` callback (see `AudioNavigatorError`). Previously, streaming errors (e.g. failed HTTP requests for remote audiobook resources) were silently swallowed.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "Update CHANGELOG"
```

- [ ] **Step 3: Hand manual verification to the user.** Ask the user to validate with the repo's `TestApp` (or via the flutter_readium plugin pointed at this branch): open a remote audiobook with an unreachable/unauthorized audio URL, press play, and confirm the delegate now receives `didFailWithError`. Record their verdict; **do not claim verification yourself, and do not run the TestApp on their behalf.**
- [ ] **Step 4: STOP — confirm with the user**, then open an issue + PR:
  - Issue on readium/swift-toolkit, title: `AudioNavigator silently swallows streaming errors` (body: remote audiobook + failed fetch → player stuck in loading/paused, no delegate callback; `MediaPlaybackState` has no failed case; `PublicationMediaLoader` failures reach `AVPlayerItem.status == .failed` but nothing observes it).
  - PR from the user's fork → `readium/swift-toolkit:develop`, referencing the issue, describing: motivation, the new delegate method + default impl (non-breaking), the user's manual verification results from Step 3, and any dropped tests from Task 4.
  - Mention as a possible follow-up (maintainer input welcome): making `AVPlayer.automaticallyWaitsToMinimizeStalling` configurable via `AudioNavigator.Configuration` — currently hardcoded `false`, which hurts flaky-network streaming. Do NOT include it in this PR; keep the diff reviewable.

---

## Follow-up (out of scope, do not implement)

- flutter_readium adoption: once a swift-toolkit release ships this, bump the pin and replace the container-wrapper detection from `docs/parity/ios-audio-error-recovery-plan.md` with the delegate callback (keep the recovery loop).
- Separate upstream PR for configurable `automaticallyWaitsToMinimizeStalling`.
- kotlin-toolkit / ts-toolkit already surface player errors; no parity work needed there.
