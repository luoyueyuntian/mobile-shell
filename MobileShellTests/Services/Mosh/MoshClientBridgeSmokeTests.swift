import XCTest
@testable import MobileShell

final class MoshClientBridgeSmokeTests: XCTestCase {
    func testBridgeObjectCanBeConstructed() {
        let bridge = MoshRuntimeClientBridge()
        XCTAssertNotNil(bridge.adapter)
    }

    func testBridgeReportsLinkedMoshBinary() {
        let bridge = MoshRuntimeClientBridge()
        XCTAssertTrue(bridge.isBinaryLinked)
    }

    func testBridgeCanLocateLocalesBundle() {
        let bridge = MoshRuntimeClientBridge()
        XCTAssertNotNil(bridge.localesBundleURL)
    }
}
