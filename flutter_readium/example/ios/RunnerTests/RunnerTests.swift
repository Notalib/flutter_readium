import XCTest
import ReadiumShared

@testable import flutter_readium

// Native unit tests run in this app-hosted target (not the SPM `flutter_readiumTests` target)
// because the plugin's `import Flutter` module is only resolvable inside the app host, not under
// plain `swift test`. See docs / bin/unit_tests for the rationale.

// Regression tests for media-overlay item range matching.
class FlutterMediaOverlayItemTests: XCTestCase {
  private func makeItem(audio: String) -> FlutterMediaOverlayItem {
    FlutterMediaOverlayItem(audio: audio, text: "ch1.html#p1", position: 0)
  }

  // Regression: a reversed `t=start,end` fragment (end < start) used to trap
  // `start...end` with "Range requires lowerBound <= upperBound".
  func testIsAudioInRangeOfTimeDoesNotTrapOnReversedFragment() {
    let item = makeItem(audio: "ch1.mp3#t=10,5")

    // Degrades to the open-ended rule (time >= start): 7 < 10 → false, no crash.
    XCTAssertFalse(item.isAudioInRangeOfTime(7, inHref: "ch1.mp3"))
    // time >= start still selects the item.
    XCTAssertTrue(item.isAudioInRangeOfTime(12, inHref: "ch1.mp3"))
  }

  // Regression: a non-finite bound (Double("nan") parses successfully) must not trap.
  func testIsAudioInRangeOfTimeDoesNotTrapOnNaNFragment() {
    let item = makeItem(audio: "ch1.mp3#t=nan,5")

    XCTAssertFalse(item.isAudioInRangeOfTime(3, inHref: "ch1.mp3"))
  }

  // Happy path unchanged: well-formed range still matches by containment.
  func testIsAudioInRangeOfTimeMatchesWellFormedRange() {
    let item = makeItem(audio: "ch1.mp3#t=5,10")

    XCTAssertFalse(item.isAudioInRangeOfTime(4, inHref: "ch1.mp3"))
    XCTAssertTrue(item.isAudioInRangeOfTime(5, inHref: "ch1.mp3"))
    XCTAssertTrue(item.isAudioInRangeOfTime(10, inHref: "ch1.mp3"))
    XCTAssertFalse(item.isAudioInRangeOfTime(11, inHref: "ch1.mp3"))
  }

  // Open-ended item (start only, no end) matches any time at or after start.
  func testIsAudioInRangeOfTimeOpenEndedFromStart() {
    let item = makeItem(audio: "ch1.mp3#t=5")

    XCTAssertFalse(item.isAudioInRangeOfTime(4, inHref: "ch1.mp3"))
    XCTAssertTrue(item.isAudioInRangeOfTime(5, inHref: "ch1.mp3"))
    XCTAssertTrue(item.isAudioInRangeOfTime(999, inHref: "ch1.mp3"))
  }

  // Non-matching href short-circuits regardless of fragment.
  func testIsAudioInRangeOfTimeRejectsUnknownHref() {
    let item = makeItem(audio: "ch1.mp3#t=5,10")

    XCTAssertFalse(item.isAudioInRangeOfTime(7, inHref: "other.mp3"))
  }
}

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
