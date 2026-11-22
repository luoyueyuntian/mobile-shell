import Foundation

enum RemoteAccessProtocol: String, CaseIterable, Codable, Sendable {
    case ssh
    case mosh
}
