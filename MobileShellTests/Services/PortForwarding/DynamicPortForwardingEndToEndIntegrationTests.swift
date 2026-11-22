import Darwin
import Foundation
import XCTest
@testable import MobileShell

final class DynamicPortForwardingEndToEndIntegrationTests: XCTestCase {
    func testDynamicPortForwardCanReadSSHBannerFromRealHost() async throws {
        let configuration = try DynamicPortForwardEndToEndConfiguration.load()
        let rule = PortForwardRule(
            id: UUID(uuidString: "D1D1D1D1-E2E2-F3F3-A4A4-B5B5B5B5B5B5")!,
            kind: .dynamic,
            name: "E2E SOCKS Proxy",
            sshHostID: configuration.host.id,
            localHost: "127.0.0.1",
            localPort: 0,
            remoteHost: "",
            remotePort: 0,
            isActive: false
        )
        let session = try await CitadelPortForwardingClient().start(rule: rule, using: configuration.request)
        let dynamicSession = try XCTUnwrap(session as? CitadelDynamicPortForwardingSession)
        let localPort = try XCTUnwrap(dynamicSession.boundLocalPort)

        defer {
            Task {
                await session.stop()
            }
        }

        let socket = try DynamicPortForwardSocket(host: "127.0.0.1", port: localPort, receiveTimeoutSeconds: 10)
        defer { socket.close() }

        try socket.write([0x05, 0x01, 0x00])
        let greeting = try socket.read(exactly: 2)
        XCTAssertEqual(greeting, [0x05, 0x00])

        try socket.write(configuration.connectRequestBytes)
        let connectReply = try socket.read(exactly: 10)
        XCTAssertEqual(connectReply[0], 0x05)
        XCTAssertEqual(connectReply[1], 0x00)

        let banner = try socket.readLine(maxBytes: 512)
        XCTAssertTrue(
            banner.hasPrefix("SSH-2.0-"),
            "Expected SSH banner from proxied connection, got: \(banner)"
        )
    }
}

private struct DynamicPortForwardEndToEndConfiguration {
    let host: ShellHost
    let request: SSHConnectionRequest
    let targetHost: String
    let targetPort: Int

    var connectRequestBytes: [UInt8] {
        let octets = targetHost
            .split(separator: ".")
            .compactMap { UInt8($0) }
        let portBytes = [
            UInt8((targetPort >> 8) & 0xFF),
            UInt8(targetPort & 0xFF)
        ]

        if octets.count == 4 {
            return [
                0x05, 0x01, 0x00, 0x01,
                octets[0], octets[1], octets[2], octets[3]
            ] + portBytes
        }

        let domainBytes = Array(targetHost.utf8)
        return [0x05, 0x01, 0x00, 0x03, UInt8(domainBytes.count)] + domainBytes + portBytes
    }

    static func load() throws -> DynamicPortForwardEndToEndConfiguration {
        let env = ProcessInfo.processInfo.environment
        let fileConfiguration = try FileBackedDynamicPortForwardEndToEndConfiguration.loadIfPresent(
            at: env["MOBILESHELL_PORT_FORWARD_E2E_CONFIG_PATH"]
                ?? env["MOBILESHELL_MOSH_E2E_CONFIG_PATH"]
                ?? "/private/tmp/mobile-shell-mosh-e2e-config.json"
        )

        func optional(_ key: String) -> String? {
            let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        func required(_ dedicatedKey: String, fallbackMoshKey: String, fileValue: String?) throws -> String {
            if let value = optional(dedicatedKey) ?? optional(fallbackMoshKey) {
                return value
            }
            if let fileValue, !fileValue.isEmpty {
                return fileValue
            }
            throw DynamicPortForwardEndToEndConfigurationError.missingConfigurationValue(dedicatedKey)
        }

        let hostname = try required(
            "MOBILESHELL_PORT_FORWARD_E2E_HOST",
            fallbackMoshKey: "MOBILESHELL_MOSH_E2E_HOST",
            fileValue: fileConfiguration?.host
        )
        let username = try required(
            "MOBILESHELL_PORT_FORWARD_E2E_USERNAME",
            fallbackMoshKey: "MOBILESHELL_MOSH_E2E_USERNAME",
            fileValue: fileConfiguration?.username
        )
        let password = try required(
            "MOBILESHELL_PORT_FORWARD_E2E_PASSWORD",
            fallbackMoshKey: "MOBILESHELL_MOSH_E2E_PASSWORD",
            fileValue: fileConfiguration?.password
        )
        let port = Int(optional("MOBILESHELL_PORT_FORWARD_E2E_PORT") ?? "")
            ?? Int(optional("MOBILESHELL_MOSH_E2E_PORT") ?? "")
            ?? fileConfiguration?.port
            ?? 22
        let targetHost = optional("MOBILESHELL_PORT_FORWARD_E2E_TARGET_HOST")
            ?? fileConfiguration?.targetHost
            ?? "127.0.0.1"
        let targetPort = Int(optional("MOBILESHELL_PORT_FORWARD_E2E_TARGET_PORT") ?? "")
            ?? fileConfiguration?.targetPort
            ?? 22

        let knownHosts: [KnownHost]
        if let keyType = optional("MOBILESHELL_PORT_FORWARD_E2E_KNOWN_HOST_KEY_TYPE")
            ?? fileConfiguration?.knownHostKeyType,
           let fingerprint = optional("MOBILESHELL_PORT_FORWARD_E2E_KNOWN_HOST_FINGERPRINT")
            ?? fileConfiguration?.knownHostFingerprint {
            knownHosts = [
                KnownHost(
                    host: KnownHost.hostToken(hostname: hostname, port: port),
                    keyType: keyType,
                    fingerprint: fingerprint
                )
            ]
        } else {
            knownHosts = []
        }

        let host = ShellHost(
            id: UUID(uuidString: "E2E2E2E2-A1A1-B2B2-C3C3-D4D4D4D4D4D4")!,
            name: "dynamic-port-forward-e2e",
            address: hostname,
            port: port,
            username: username,
            group: "Integration",
            tags: ["ssh", "dynamic", "e2e"],
            status: .idle
        )
        let request = SSHConnectionRequest(
            hostID: host.id,
            displayName: host.name,
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            knownHosts: knownHosts
        )

        return DynamicPortForwardEndToEndConfiguration(
            host: host,
            request: request,
            targetHost: targetHost,
            targetPort: targetPort
        )
    }
}

private enum DynamicPortForwardEndToEndConfigurationError: Error, LocalizedError {
    case missingConfigurationValue(String)
    case invalidConfigurationFile(String)

    var errorDescription: String? {
        switch self {
        case let .missingConfigurationValue(key):
            "Missing required dynamic port forwarding end-to-end configuration value: \(key)"
        case let .invalidConfigurationFile(message):
            "Invalid dynamic port forwarding end-to-end configuration file: \(message)"
        }
    }
}

private struct FileBackedDynamicPortForwardEndToEndConfiguration: Decodable {
    let host: String
    let port: Int?
    let username: String
    let password: String
    let targetHost: String?
    let targetPort: Int?
    let knownHostKeyType: String?
    let knownHostFingerprint: String?

    static func loadIfPresent(at path: String) throws -> FileBackedDynamicPortForwardEndToEndConfiguration? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(FileBackedDynamicPortForwardEndToEndConfiguration.self, from: data)
        } catch {
            throw DynamicPortForwardEndToEndConfigurationError.invalidConfigurationFile(error.localizedDescription)
        }
    }
}

private final class DynamicPortForwardSocket {
    private let descriptor: Int32
    private var isClosed = false

    init(host: String, port: Int, receiveTimeoutSeconds: Int) throws {
        descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw DynamicPortForwardSocketError.systemCallFailed("socket")
        }

        var timeout = timeval(tv_sec: receiveTimeoutSeconds, tv_usec: 0)
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            close()
            throw DynamicPortForwardSocketError.systemCallFailed("setsockopt(SO_RCVTIMEO)")
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            close()
            throw DynamicPortForwardSocketError.invalidIPv4Address(host)
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else {
            let errorCode = errno
            close()
            throw DynamicPortForwardSocketError.connectionFailed(host: host, port: port, code: errorCode)
        }
    }

    func write(_ bytes: [UInt8]) throws {
        var totalSent = 0
        while totalSent < bytes.count {
            let sent = bytes.withUnsafeBytes { rawBuffer in
                Darwin.send(
                    descriptor,
                    rawBuffer.baseAddress?.advanced(by: totalSent),
                    bytes.count - totalSent,
                    0
                )
            }
            guard sent > 0 else {
                throw DynamicPortForwardSocketError.systemCallFailed("send")
            }
            totalSent += sent
        }
    }

    func read(exactly count: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        var totalRead = 0

        while totalRead < count {
            let readCount = Darwin.recv(descriptor, &buffer[totalRead], count - totalRead, 0)
            guard readCount > 0 else {
                throw DynamicPortForwardSocketError.systemCallFailed("recv")
            }
            totalRead += readCount
        }

        return buffer
    }

    func readLine(maxBytes: Int) throws -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(min(maxBytes, 128))

        while bytes.count < maxBytes {
            var byte: UInt8 = 0
            let readCount = Darwin.recv(descriptor, &byte, 1, 0)
            guard readCount > 0 else {
                throw DynamicPortForwardSocketError.systemCallFailed("recv")
            }
            bytes.append(byte)
            if byte == 0x0A {
                break
            }
        }

        return String(decoding: bytes, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func close() {
        if !isClosed, descriptor >= 0 {
            isClosed = true
            Darwin.close(descriptor)
        }
    }

    deinit {
        close()
    }
}

private enum DynamicPortForwardSocketError: Error, LocalizedError {
    case invalidIPv4Address(String)
    case connectionFailed(host: String, port: Int, code: Int32)
    case systemCallFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidIPv4Address(host):
            "Invalid IPv4 address for dynamic port forward probe: \(host)"
        case let .connectionFailed(host, port, code):
            "Failed to connect to \(host):\(port) for dynamic port forward probe (errno \(code))"
        case let .systemCallFailed(name):
            "System call failed during dynamic port forward probe: \(name)"
        }
    }
}
