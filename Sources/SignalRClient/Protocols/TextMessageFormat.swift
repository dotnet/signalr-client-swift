import Foundation

class TextMessageFormat {
    static let recordSeparatorCode: UInt8 = 0x1e
    static let recordSeparator = String(UnicodeScalar(recordSeparatorCode))

    static func write(_ output: String) -> String {
        return "\(output)\(recordSeparator)"
    }

    static func parse(_ input: String) throws -> [String] {
        guard input.last == Character(recordSeparator) else {
            throw SignalRError.incompleteMessage
        }

        var messages = input.split(separator: Character(recordSeparator)).map { String($0) }
        if let last = messages.last, last.isEmpty {
            messages.removeLast()
        }
        return messages
    }
}