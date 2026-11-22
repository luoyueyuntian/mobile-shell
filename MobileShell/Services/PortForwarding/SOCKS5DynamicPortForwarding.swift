import Foundation
import Citadel
import NIO
import NIOPosix
import NIOSSH

enum SOCKS5HandshakeError: Error, Equatable, Sendable {
    case unsupportedVersion(UInt8)
    case unsupportedAuthenticationMethod
    case unsupportedCommand(UInt8)
    case unsupportedAddressType(UInt8)
    case malformedRequest
}

struct SOCKS5GreetingResult: Equatable, Sendable {
    let selectedMethod: UInt8
}

enum SOCKS5ServerHandshake {
    static func parseGreeting(_ bytes: [UInt8]) throws -> SOCKS5GreetingResult {
        guard bytes.count >= 3 else { throw SOCKS5HandshakeError.malformedRequest }
        guard bytes[0] == 0x05 else { throw SOCKS5HandshakeError.unsupportedVersion(bytes[0]) }

        let methodCount = Int(bytes[1])
        guard bytes.count == methodCount + 2 else { throw SOCKS5HandshakeError.malformedRequest }
        guard bytes[2...].contains(0x00) else {
            throw SOCKS5HandshakeError.unsupportedAuthenticationMethod
        }

        return SOCKS5GreetingResult(selectedMethod: 0x00)
    }
}

struct SOCKS5ConnectRequest: Equatable, Sendable {
    let host: String
    let port: Int

    static func parse(_ bytes: [UInt8]) throws -> SOCKS5ConnectRequest {
        guard bytes.count >= 7 else { throw SOCKS5HandshakeError.malformedRequest }
        guard bytes[0] == 0x05 else { throw SOCKS5HandshakeError.unsupportedVersion(bytes[0]) }
        guard bytes[1] == 0x01 else { throw SOCKS5HandshakeError.unsupportedCommand(bytes[1]) }
        guard bytes[2] == 0x00 else { throw SOCKS5HandshakeError.malformedRequest }

        switch bytes[3] {
        case 0x01:
            guard bytes.count == 10 else { throw SOCKS5HandshakeError.malformedRequest }
            let host = "\(bytes[4]).\(bytes[5]).\(bytes[6]).\(bytes[7])"
            let port = Int(bytes[8]) << 8 | Int(bytes[9])
            return SOCKS5ConnectRequest(host: host, port: port)
        case 0x03:
            let hostLength = Int(bytes[4])
            guard bytes.count == hostLength + 7 else { throw SOCKS5HandshakeError.malformedRequest }
            let host = String(decoding: bytes[5..<(5 + hostLength)], as: UTF8.self)
            let portIndex = 5 + hostLength
            let port = Int(bytes[portIndex]) << 8 | Int(bytes[portIndex + 1])
            return SOCKS5ConnectRequest(host: host, port: port)
        case 0x04:
            guard bytes.count == 22 else { throw SOCKS5HandshakeError.malformedRequest }
            let groups = stride(from: 4, through: 18, by: 2).map { index in
                String(format: "%02x%02x", bytes[index], bytes[index + 1])
            }
            let port = Int(bytes[20]) << 8 | Int(bytes[21])
            return SOCKS5ConnectRequest(host: groups.joined(separator: ":"), port: port)
        default:
            throw SOCKS5HandshakeError.unsupportedAddressType(bytes[3])
        }
    }
}

struct SOCKS5PendingProxyPayload: Sendable {
    private var bytes: [UInt8] = []

    mutating func beginConnecting(initialBytes: [UInt8]) {
        bytes = initialBytes
    }

    mutating func appendDuringConnecting(_ newBytes: [UInt8]) {
        bytes.append(contentsOf: newBytes)
    }

    mutating func activateProxyingAndDrain() -> [UInt8] {
        let drained = bytes
        bytes.removeAll(keepingCapacity: false)
        return drained
    }

    mutating func reset() {
        bytes.removeAll(keepingCapacity: false)
    }
}

final class CitadelDynamicPortForwardingSession: PortForwardingSession, @unchecked Sendable {
    private let client: SSHClient
    private let serverChannel: Channel

    var boundLocalPort: Int? {
        serverChannel.localAddress?.port
    }

    private init(client: SSHClient, serverChannel: Channel) {
        self.client = client
        self.serverChannel = serverChannel
    }

    static func start(rule: PortForwardRule, client: SSHClient) async throws -> CitadelDynamicPortForwardingSession {
        let clientBox = DynamicPortForwardSSHClientBox(client)
        let serverChannel = try await ServerBootstrap(group: client.eventLoop, childGroup: client.eventLoop)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .childChannelInitializer { inboundChannel in
                inboundChannel.pipeline.addHandler(
                    SOCKS5DynamicPortForwardingHandler(clientBox: clientBox)
                )
            }
            .bind(host: rule.localHost, port: rule.localPort)
            .get()

        return CitadelDynamicPortForwardingSession(client: client, serverChannel: serverChannel)
    }

    func stop() async {
        try? await serverChannel.close()
        try? await client.close()
    }
}

private enum SOCKS5ReplyCode: UInt8 {
    case generalFailure = 0x01
    case commandNotSupported = 0x07
    case addressTypeNotSupported = 0x08
}

private enum SOCKS5ServerResponse {
    static let noAuthenticationRequired: [UInt8] = [0x05, 0x00]
    static let noAcceptableMethods: [UInt8] = [0x05, 0xFF]

    static func reply(code: SOCKS5ReplyCode) -> [UInt8] {
        [0x05, code.rawValue, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
    }

    static func success() -> [UInt8] {
        [0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
    }
}

private final class DynamicPortForwardSSHClientBox: @unchecked Sendable {
    let client: SSHClient

    init(_ client: SSHClient) {
        self.client = client
    }
}

private final class DynamicPortForwardChannelBox: @unchecked Sendable {
    let channel: Channel

    init(_ channel: Channel) {
        self.channel = channel
    }
}

private final class SOCKS5DynamicPortForwardingHandler: ChannelDuplexHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private enum State {
        case greeting
        case request
        case connecting
        case proxying
        case closed
    }

    private let clientBox: DynamicPortForwardSSHClientBox
    private var state: State = .greeting
    private var buffer = ByteBuffer()
    private var pendingProxyPayload = SOCKS5PendingProxyPayload()

    init(clientBox: DynamicPortForwardSSHClientBox) {
        self.clientBox = clientBox
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch state {
        case .proxying:
            context.fireChannelRead(data)
        case .closed:
            break
        case .greeting, .request:
            var incoming = unwrapInboundIn(data)
            buffer.writeBuffer(&incoming)
            processBufferedData(context: context)
        case .connecting:
            var incoming = unwrapInboundIn(data)
            let bytes = incoming.readBytes(length: incoming.readableBytes) ?? []
            pendingProxyPayload.appendDuringConnecting(bytes)
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        if state == .proxying {
            context.fireChannelReadComplete()
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    private func processBufferedData(context: ChannelHandlerContext) {
        do {
            switch state {
            case .greeting:
                guard let greetingBytes = readGreetingBytesIfAvailable() else { return }
                _ = try SOCKS5ServerHandshake.parseGreeting(greetingBytes)
                writeAndFlush(
                    SOCKS5ServerResponse.noAuthenticationRequired,
                    closeAfterWrite: false,
                    channel: context.channel
                )
                state = .request
                if buffer.readableBytes > 0 {
                    processBufferedData(context: context)
                }
            case .request:
                guard let requestBytes = readConnectRequestBytesIfAvailable() else { return }
                let request = try SOCKS5ConnectRequest.parse(requestBytes)
                let leftoverBytes = buffer.readBytes(length: buffer.readableBytes) ?? []
                buffer.clear()
                pendingProxyPayload.beginConnecting(initialBytes: leftoverBytes)
                state = .connecting
                openDirectChannel(for: request, context: context)
            case .connecting, .proxying, .closed:
                return
            }
        } catch let error as SOCKS5HandshakeError {
            handleHandshakeError(error, context: context)
        } catch {
            writeAndFlush(
                SOCKS5ServerResponse.reply(code: .generalFailure),
                closeAfterWrite: true,
                channel: context.channel
            )
        }
    }

    private func openDirectChannel(
        for request: SOCKS5ConnectRequest,
        context: ChannelHandlerContext
    ) {
        let channelBox = DynamicPortForwardChannelBox(context.channel)
        let handler = self

        context.eventLoop.makeFutureWithTask { [clientBox, channelBox, handler] in
            let originatorAddress = try channelBox.channel.remoteAddress
                ?? SocketAddress(ipAddress: "127.0.0.1", port: 0)
            let (sshGlue, localGlue) = PortForwardGlueHandler.matchedPair()
            let sshChannel = try await clientBox.client.createDirectTCPIPChannel(
                using: SSHChannelType.DirectTCPIP(
                    targetHost: request.host,
                    targetPort: request.port,
                    originatorAddress: originatorAddress
                )
            ) { sshChannel in
                sshChannel.pipeline.addHandler(sshGlue)
            }

            var responseBuffer = channelBox.channel.allocator.buffer(capacity: 10)
            responseBuffer.writeBytes(SOCKS5ServerResponse.success())
            try await channelBox.channel.writeAndFlush(responseBuffer).get()
            try await channelBox.channel.pipeline.addHandler(localGlue).get()

            handler.state = .proxying
            let pendingBytes = handler.pendingProxyPayload.activateProxyingAndDrain()
            if !pendingBytes.isEmpty {
                var pendingBuffer = sshChannel.allocator.buffer(capacity: pendingBytes.count)
                pendingBuffer.writeBytes(pendingBytes)
                try await sshChannel.writeAndFlush(pendingBuffer).get()
            }

            try await channelBox.channel.pipeline.removeHandler(handler).get()
        }.whenFailure { [weak self] _ in
            self?.state = .closed
            self?.pendingProxyPayload.reset()
            self?.writeAndFlush(
                SOCKS5ServerResponse.reply(code: .generalFailure),
                closeAfterWrite: true,
                channel: channelBox.channel
            )
        }
    }

    private func handleHandshakeError(_ error: SOCKS5HandshakeError, context: ChannelHandlerContext) {
        let currentState = state
        state = .closed
        pendingProxyPayload.reset()

        switch error {
        case .unsupportedAuthenticationMethod where currentState == .greeting:
            writeAndFlush(SOCKS5ServerResponse.noAcceptableMethods, closeAfterWrite: true, channel: context.channel)
        case .unsupportedCommand:
            writeAndFlush(
                SOCKS5ServerResponse.reply(code: .commandNotSupported),
                closeAfterWrite: true,
                channel: context.channel
            )
        case .unsupportedAddressType:
            writeAndFlush(
                SOCKS5ServerResponse.reply(code: .addressTypeNotSupported),
                closeAfterWrite: true,
                channel: context.channel
            )
        case .unsupportedVersion, .unsupportedAuthenticationMethod, .malformedRequest:
            if case .greeting = currentState {
                context.close(promise: nil)
            } else {
                writeAndFlush(
                    SOCKS5ServerResponse.reply(code: .generalFailure),
                    closeAfterWrite: true,
                    channel: context.channel
                )
            }
        }
    }

    private func writeAndFlush(_ bytes: [UInt8], closeAfterWrite: Bool, channel: Channel) {
        var response = channel.allocator.buffer(capacity: bytes.count)
        response.writeBytes(bytes)

        if closeAfterWrite {
            let channelBox = DynamicPortForwardChannelBox(channel)
            channel.writeAndFlush(response).whenComplete { _ in
                channelBox.channel.close(promise: nil)
            }
        } else {
            channel.writeAndFlush(response, promise: nil)
        }
    }

    private func readGreetingBytesIfAvailable() -> [UInt8]? {
        guard buffer.readableBytes >= 2,
              let methodCount = buffer.getInteger(at: buffer.readerIndex + 1, as: UInt8.self)
        else {
            return nil
        }

        let totalLength = 2 + Int(methodCount)
        guard buffer.readableBytes >= totalLength else { return nil }
        return buffer.readBytes(length: totalLength)
    }

    private func readConnectRequestBytesIfAvailable() -> [UInt8]? {
        guard buffer.readableBytes >= 4,
              let addressType = buffer.getInteger(at: buffer.readerIndex + 3, as: UInt8.self)
        else {
            return nil
        }

        let totalLength: Int
        switch addressType {
        case 0x01:
            totalLength = 10
        case 0x03:
            guard buffer.readableBytes >= 5,
                  let hostLength = buffer.getInteger(at: buffer.readerIndex + 4, as: UInt8.self)
            else {
                return nil
            }
            totalLength = 7 + Int(hostLength)
        case 0x04:
            totalLength = 22
        default:
            totalLength = buffer.readableBytes
        }

        guard buffer.readableBytes >= totalLength else { return nil }
        return buffer.readBytes(length: totalLength)
    }
}
