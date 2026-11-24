import XCTest
@testable import StepTrack

final class SigningStatusTests: XCTestCase {
    func testSharedGroupFollowsSingleResignedGroupWithoutGuessingAmongMultiple() {
        let original = "group.com.personal.steptrack"
        let renamed = "group.com.personal.steptrack.TEAM"
        XCTAssertEqual(ProvisioningProfile.sharedGroup(configured: original, allowed: [renamed]), renamed)
        XCTAssertEqual(ProvisioningProfile.sharedGroup(configured: original, allowed: [original, renamed]), original)
        XCTAssertEqual(ProvisioningProfile.sharedGroup(configured: original, allowed: [renamed, "group.other"]), original)
        XCTAssertEqual(ProvisioningProfile.sharedGroup(configured: original, allowed: []), original)
    }
    func testExtractsHealthKitFromCMSWrappedXML() throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "Entitlements": ["com.apple.developer.healthkit": true]
        ], format: .xml, options: 0)
        var wrapped = Data([0x30, 0x82, 0xFF, 0x00])
        wrapped.append(plist)
        wrapped.append(Data([0xFF, 0x00]))
        XCTAssertEqual(SigningStatus.profileEntitlements(in: wrapped)?["com.apple.developer.healthkit"] as? Bool, true)
    }
    func testMissingCapabilityIsDifferentFromUnreadableProfile() throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "Entitlements": ["application-identifier": "TEAM.app"]
        ], format: .xml, options: 0)
        let entitlements = SigningStatus.profileEntitlements(in: plist)
        XCTAssertNotNil(entitlements)
        XCTAssertNil(entitlements?["com.apple.developer.healthkit"])
        XCTAssertNil(SigningStatus.profileEntitlements(in: Data("not a profile".utf8)))
    }
}
