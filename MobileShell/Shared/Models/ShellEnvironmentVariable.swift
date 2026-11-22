import Foundation

struct ShellEnvironmentVariable: Identifiable, Equatable, Codable, Sendable {
    var key: String
    var value: String

    var id: String { key }

    var exportCommand: String {
        "export \(key)=\(Self.singleQuoted(value))"
    }

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    static func parseLines(_ text: String) -> [ShellEnvironmentVariable] {
        sanitized(
            text
                .split(whereSeparator: \.isNewline)
                .compactMap { line in
                    let rawLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let separator = rawLine.firstIndex(of: "=") else { return nil }
                    let key = rawLine[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = rawLine[rawLine.index(after: separator)...]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return ShellEnvironmentVariable(key: key, value: value)
                }
        )
    }

    static func text(from variables: [ShellEnvironmentVariable]) -> String {
        sanitized(variables)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }

    static func sanitized(_ variables: [ShellEnvironmentVariable]) -> [ShellEnvironmentVariable] {
        var valuesByKey: [String: String] = [:]

        for variable in variables {
            let key = variable.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = variable.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidKey(key), !value.isEmpty else { continue }
            valuesByKey[key] = value
        }

        return valuesByKey.keys
            .sorted()
            .compactMap { key in
                valuesByKey[key].map { ShellEnvironmentVariable(key: key, value: $0) }
            }
    }

    private static func isValidKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first else { return false }
        guard first == "_" || isASCIILetter(first) else { return false }

        return key.unicodeScalars.dropFirst().allSatisfy { scalar in
            scalar == "_" || isASCIILetter(scalar) || isASCIIDigit(scalar)
        }
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
    }

    private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        (48...57).contains(Int(scalar.value))
    }

    private static func singleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
