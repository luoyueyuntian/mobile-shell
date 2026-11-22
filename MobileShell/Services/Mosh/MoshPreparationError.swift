import Foundation

enum MoshPreparationError: Error, Equatable {
    case moshServerMissing
    case moshServerLaunchFailed(String)
    case moshHandshakeParseFailed
}
