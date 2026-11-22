import Foundation
import XCTest
@testable import MobileShell

final class MoshHostConfigurationTests: XCTestCase {
    func testRemoteAccessProtocolRoundTripsThroughCodable() throws {
        let data = try JSONEncoder().encode(RemoteAccessProtocol.mosh)
        let decoded = try JSONDecoder().decode(RemoteAccessProtocol.self, from: data)

        XCTAssertEqual(decoded, .mosh)
    }

    func testMoshHostConfigurationDefaultValuesMatchProductSpec() {
        let configuration = MoshHostConfiguration.default

        XCTAssertEqual(configuration.udpPort, 60001)
        XCTAssertEqual(configuration.serverCommand, "mosh-server new -s")
        XCTAssertTrue(configuration.predictiveEcho)
        XCTAssertFalse(configuration.useExperimentalConnection)
    }

    func testLegacyShellHostDecodesWithoutProtocolFields() throws {
        let data = Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "api-prod",
          "address": "api.example.com",
          "port": 22,
          "username": "deploy",
          "group": "Production",
          "tags": ["ssh"],
          "status": "idle"
        }
        """.utf8)

        let host = try JSONDecoder().decode(ShellHost.self, from: data)

        XCTAssertEqual(host.protocol, .ssh)
        XCTAssertNil(host.moshConfiguration)
    }

    func testShellHostInitializesSSHWithNilMoshConfigurationWhenGivenValue() {
        let host = ShellHost(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "ssh-host",
            address: "ssh.example.com",
            username: "deploy",
            group: "Lab",
            tags: ["ssh"],
            status: .idle,
            protocol: .ssh,
            moshConfiguration: .default
        )

        XCTAssertEqual(host.protocol, .ssh)
        XCTAssertNil(host.moshConfiguration)
    }

    func testShellHostInitializesMoshWithDefaultConfigurationWhenGivenNil() {
        let host = ShellHost(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            name: "mosh-host",
            address: "mosh.example.com",
            username: "deploy",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: nil
        )

        XCTAssertEqual(host.protocol, .mosh)
        XCTAssertEqual(host.moshConfiguration, .default)
    }

    func testShellHostDecodesSSHWithMoshConfigurationAsNil() throws {
        let data = Data("""
        {
          "id": "55555555-5555-5555-5555-555555555555",
          "name": "ssh-json",
          "address": "ssh-json.example.com",
          "port": 22,
          "username": "deploy",
          "group": "Production",
          "tags": ["ssh"],
          "status": "idle",
          "protocol": "ssh",
          "moshConfiguration": {
            "udpPort": 60010,
            "serverCommand": "mosh-server",
            "predictiveEcho": false,
            "useExperimentalConnection": true
          }
        }
        """.utf8)

        let host = try JSONDecoder().decode(ShellHost.self, from: data)

        XCTAssertEqual(host.protocol, .ssh)
        XCTAssertNil(host.moshConfiguration)
    }

    func testShellHostDecodesMoshWithoutConfigurationAsDefault() throws {
        let data = Data("""
        {
          "id": "66666666-6666-6666-6666-666666666666",
          "name": "mosh-json",
          "address": "mosh-json.example.com",
          "port": 22,
          "username": "deploy",
          "group": "Production",
          "tags": ["mosh"],
          "status": "idle",
          "protocol": "mosh"
        }
        """.utf8)

        let host = try JSONDecoder().decode(ShellHost.self, from: data)

        XCTAssertEqual(host.protocol, .mosh)
        XCTAssertEqual(host.moshConfiguration, .default)
    }

    func testShellHostWithMoshConfigurationRoundTripsThroughJSON() throws {
        let host = ShellHost(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "lab-mosh",
            address: "lab.example.com",
            port: 22,
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: MoshHostConfiguration(
                udpPort: 60010,
                serverCommand: "mosh-server new -s",
                predictiveEcho: false,
                useExperimentalConnection: true
            )
        )

        let data = try JSONEncoder().encode(host)
        let decoded = try JSONDecoder().decode(ShellHost.self, from: data)

        XCTAssertEqual(decoded.protocol, .mosh)
        XCTAssertEqual(decoded.moshConfiguration?.udpPort, 60010)
        XCTAssertEqual(decoded.moshConfiguration?.serverCommand, "mosh-server new -s")
        XCTAssertEqual(decoded.moshConfiguration?.predictiveEcho, false)
        XCTAssertEqual(decoded.moshConfiguration?.useExperimentalConnection, true)
    }
}
