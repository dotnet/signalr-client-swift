import Foundation

/// Specifies a specific HTTP transport type.
public struct HttpTransportType: OptionSet {
    public let rawValue: Int

    static let none = HttpTransportType([])
    static let webSockets = HttpTransportType(rawValue: 1 << 0)
    static let serverSentEvents = HttpTransportType(rawValue: 1 << 1)
    static let longPolling = HttpTransportType(rawValue: 1 << 2)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static func from(_ transportString: String) -> HttpTransportType? {
        switch transportString.lowercased() {
            case "websockets":
                return .webSockets
            case "serversentevents":
                return .serverSentEvents
            case "longpolling":
                return .longPolling
            default:
                return nil
        }
    }
}

/// Specifies the transfer format for a connection.
public enum TransferFormat: Int, Codable, Sendable {
    /// Specifies that only text data will be transmitted over the connection.
    case text = 1
    /// Specifies that binary data will be transmitted over the connection.
    case binary = 2

    init?(_ transferFormatString: String) {
        switch transferFormatString.lowercased() {
            case "text":
                self = .text
            case "binary":
                self = .binary
            default:
                return nil
        }
    }
}
