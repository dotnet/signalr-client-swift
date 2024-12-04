import Foundation

protocol HubProtocol: Sendable {
    /// The name of the protocol. This is used by SignalR to resolve the protocol between the client and server.
    var name: String { get }
    /// The version of the protocol.
    var version: Int { get }
    /// The transfer format of the protocol.
    var transferFormat: TransferFormat { get }

    /**
     Creates an array of `HubMessage` objects from the specified serialized representation.
     
     If `transferFormat` is 'Text', the `input` parameter must be a String, otherwise it must be Data.
     
     - Parameters:
       - input: A Data containing the serialized representation.
     - Returns: An array of `HubMessage` objects.
     */
    func parseMessages(input: StringOrData, binder: InvocationBinder) throws -> [HubMessage]

    /**
     Writes the specified `HubMessage` to a String or Data and returns it.
     
     If `transferFormat` is 'Text', the result of this method will be a String, otherwise it will be Data.
     
     - Parameter message: The message to write.
     - Returns: A Data containing the serialized representation of the message.
     */
    func writeMessage(message: HubMessage) throws -> StringOrData
}

public enum StringOrData: Sendable, Equatable {
    case string(String)
    case data(Data)
}
