import Foundation

enum MoshRuntimeError: Error, Equatable {
    case connectFailed(String)
}
