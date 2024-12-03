import Foundation

// Define error types for better error handling
public enum SignalRError: Error, Equatable {
    case incompleteMessage
    case invalidDataType
    case failedToEncodeHandshakeRequest
    case failedToDecodeResponseData
    case expectedHandshakeResponse
    case noHandshakeMessageReceived
    case unsupportedHandshakeVersion
    case handshakeError(String)
    case connectionAborted
    case negotiationError(String)
    case failedToStartConnection(String)
    case invalidOperation(String)
    case unexpectedResponseCode(Int)
    case invalidTextMessageEncoding
    case httpTimeoutError
    case invalidResponseType
    case cannotSentUntilTransportConnected

    var localizedDescription: String {
        switch self {
        case .incompleteMessage:
            return "Message is incomplete."
        case .invalidDataType:
            return "Invalid data type."
        case .failedToEncodeHandshakeRequest:
            return "Failed to encode handshake request to JSON string."
        case .failedToDecodeResponseData:
            return "Failed to decode response data."
        case .expectedHandshakeResponse:
            return "Expected a handshake response from the server."
        case .noHandshakeMessageReceived:
            return "No handshake message received."
        case .unsupportedHandshakeVersion:
            return "Unsupported handshake version"
        case .handshakeError(let message):
            return "Handshake error: \(message)"
        case .connectionAborted:
            return "Connection aborted."
        case .negotiationError(let message):
            return "Negotiation error: \(message)"
        case .failedToStartConnection(let message):
            return "Failed to start connection: \(message)"
        case .invalidOperation(let message):
            return "Invalid operation: \(message)"
        case .unexpectedResponseCode(let responseCode):
            return "Unexpected response code:\(responseCode)"
        case .invalidTextMessageEncoding:
            return "Invalide text messagge"
        case .httpTimeoutError:
            return "Http timeout"
        case .invalidResponseType:
            return "Invalid response type"
        case .cannotSentUntilTransportConnected:
            return "Cannot send until the transport is connected"
        }
    }
}
