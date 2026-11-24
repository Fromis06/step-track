import XCTest
@testable import StepTrack

final class ContributorsTests: XCTestCase {
    func testAttributionMetadataPreservesMITLicense() {
        XCTAssertEqual(AppAttribution.appName, "Step Track")
        XCTAssertEqual(AppAttribution.upstreamAuthor, "Brittany Rima")
        XCTAssertEqual(AppAttribution.license, "MIT")
    }
}
