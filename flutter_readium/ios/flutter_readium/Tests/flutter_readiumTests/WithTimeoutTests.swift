import XCTest
@testable import flutter_readium

final class WithTimeoutTests: XCTestCase {
  func testWithTimeoutReturnsNilForOperationThatIgnoresCancellation() async {
    let result = await withTimeout(seconds: 1) {
      while true {
        try? await Task.sleep(nanoseconds: 50_000_000)
      }
    }

    XCTAssertNil(result)
  }
}
