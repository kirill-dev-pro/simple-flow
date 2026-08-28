import XCTest
@testable import SimpleFlow

final class BootstrapTests: XCTestCase {
    func testBundleIdentifierIsConfigured() {
        XCTAssertEqual(AppIdentity.bundleIdentifier, "dev.kirill.simpleflow")
    }
}
