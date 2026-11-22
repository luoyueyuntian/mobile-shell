import XCTest
@testable import MobileShell

final class SOCKS5DynamicPortForwardingTests: XCTestCase {
    func testPendingProxyPayloadDrainsInitialAndConnectingBytesTogether() {
        var payload = SOCKS5PendingProxyPayload()
        payload.beginConnecting(initialBytes: [0x16, 0x03])
        payload.appendDuringConnecting([0x01, 0x02, 0x03])

        let drained = payload.activateProxyingAndDrain()

        XCTAssertEqual(drained, [0x16, 0x03, 0x01, 0x02, 0x03])
    }

    func testPendingProxyPayloadIsEmptyAfterDrain() {
        var payload = SOCKS5PendingProxyPayload()
        payload.beginConnecting(initialBytes: [0x47, 0x45, 0x54])

        _ = payload.activateProxyingAndDrain()
        let drainedAgain = payload.activateProxyingAndDrain()

        XCTAssertTrue(drainedAgain.isEmpty)
    }

    func testGreetingAcceptsNoAuthMethod() throws {
        let result = try SOCKS5ServerHandshake.parseGreeting([0x05, 0x02, 0x00, 0x02])

        XCTAssertEqual(result.selectedMethod, 0x00)
    }

    func testGreetingRejectsWhenNoAuthMethodMissing() {
        XCTAssertThrowsError(try SOCKS5ServerHandshake.parseGreeting([0x05, 0x01, 0x02])) { error in
            XCTAssertEqual(error as? SOCKS5HandshakeError, .unsupportedAuthenticationMethod)
        }
    }

    func testConnectRequestParsesDomainDestination() throws {
        let bytes: [UInt8] = [0x05, 0x01, 0x00, 0x03, 0x0B] + Array("example.com".utf8) + [0x01, 0xBB]

        let request = try SOCKS5ConnectRequest.parse(bytes)

        XCTAssertEqual(request.host, "example.com")
        XCTAssertEqual(request.port, 443)
    }

    func testConnectRequestParsesIPv4Destination() throws {
        let request = try SOCKS5ConnectRequest.parse([0x05, 0x01, 0x00, 0x01, 10, 0, 0, 8, 0x23, 0x28])

        XCTAssertEqual(request.host, "10.0.0.8")
        XCTAssertEqual(request.port, 9000)
    }

    func testConnectRequestParsesIPv6Destination() throws {
        let request = try SOCKS5ConnectRequest.parse([
            0x05, 0x01, 0x00, 0x04,
            0x20, 0x01, 0x0D, 0xB8, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
            0x01, 0xBB
        ])

        XCTAssertEqual(request.host, "2001:0db8:0000:0000:0000:0000:0000:0001")
        XCTAssertEqual(request.port, 443)
    }

    func testConnectRequestRejectsBindCommand() {
        let bytes: [UInt8] = [0x05, 0x02, 0x00, 0x01, 127, 0, 0, 1, 0x00, 0x35]

        XCTAssertThrowsError(try SOCKS5ConnectRequest.parse(bytes)) { error in
            XCTAssertEqual(error as? SOCKS5HandshakeError, .unsupportedCommand(0x02))
        }
    }

    func testConnectRequestRejectsUDPAssociate() {
        let bytes: [UInt8] = [0x05, 0x03, 0x00, 0x01, 127, 0, 0, 1, 0x00, 0x35]

        XCTAssertThrowsError(try SOCKS5ConnectRequest.parse(bytes)) { error in
            XCTAssertEqual(error as? SOCKS5HandshakeError, .unsupportedCommand(0x03))
        }
    }
}
