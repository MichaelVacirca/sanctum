import XCTest
@testable import Sanctum

final class ZoneTests: XCTestCase {
    func testCenterZoneContainsCenterPoint() {
        let zone = Zone.center(canvasWidth: 3840, canvasHeight: 2160)
        XCTAssertTrue(zone.contains(x: 1920, y: 1080))
    }

    func testEdgeZonesExist() {
        let zones = Zone.allZones(canvasWidth: 3840, canvasHeight: 2160)
        XCTAssertEqual(zones.count, 5)
    }
}
