import Foundation
import os

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
    case invalidData(String)
    case eventSourceFailedToConnect
    case eventSourceInvalidTransferFormat
    case invalidUrl(String)
    case invocationError(String)
    case unsupportedTransport
    case messageBiggerThan2GB
    case unexpectedMessageType(String)

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
        case .invalidData(let message):
            return "Invalid data: \(message)"
        case .eventSourceFailedToConnect:
            return """
                    EventSource failed to connect. The connection could not be found on the server,
                    either the connection ID is not present on the server, or a proxy is refusing/buffering the connection.
                    If you have multiple servers check that sticky sessions are enabled.
                    """
        case .eventSourceInvalidTransferFormat:
            return "The Server-Sent Events transport only supports the 'Text' transfer format"
        case .invalidUrl(let url):
            return "Invalid url: \(url)"
        case .invocationError(let errorMessage):
            return "Invocation error: \(errorMessage)"
        case .unsupportedTransport:
            return "The transport is not supported."
        case .messageBiggerThan2GB:
            return "Messages bigger than 2GB are not supported."
        case .unexpectedMessageType(let messageType):
            return "Unexpected message type: \(messageType)."
        }
    }
}
