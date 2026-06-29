import XCTest
@testable import flutter_readium

final class TimebasedProgressCalculatorTests: XCTestCase {
  func testComputePublicationDurationReturnsNilWhenMissingDuration() {
    let result = computePublicationDuration([10.0, nil, 20.0])

    XCTAssertNil(result)
  }

  func testComputePublicationDurationReturnsNilWhenNonPositiveDuration() {
    let result = computePublicationDuration([10.0, 0.0, 20.0])

    XCTAssertNil(result)
  }

  func testComputePublicationDurationSumsValidDurations() {
    let result = computePublicationDuration([10.0, 20.5])

    XCTAssertEqual(result, 30.5)
  }

  func testComputeTotalProgressDurationReturnsNilWhenInputsMissing() {
    XCTAssertNil(computeTotalProgressDuration(totalProgression: nil, publicationDuration: 10.0))
    XCTAssertNil(computeTotalProgressDuration(totalProgression: 0.5, publicationDuration: nil))
  }

  func testComputeTotalProgressDurationClampsProgression() {
    XCTAssertEqual(
      computeTotalProgressDuration(totalProgression: -1.0, publicationDuration: 30.0),
      0.0
    )
    XCTAssertEqual(
      computeTotalProgressDuration(totalProgression: 2.0, publicationDuration: 30.0),
      30.0
    )
    XCTAssertEqual(
      computeTotalProgressDuration(totalProgression: 0.5, publicationDuration: 30.0),
      15.0
    )
  }
}
