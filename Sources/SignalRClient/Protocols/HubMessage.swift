/// Defines properties common to all Hub messages.
public protocol HubMessage: Encodable {
    /// A value indicating the type of this message.
    var type: MessageType { get }
}

/// Defines properties common to all Hub messages relating to a specific invocation.
protocol HubInvocationMessage: HubMessage {
    /// A dictionary containing headers attached to the message.
    var headers: [String: String]? { get }
    /// The ID of the invocation relating to this message.
    var invocationId: String? { get }
}

/// A hub message representing a non-streaming invocation.
struct InvocationMessage: HubInvocationMessage {
    /// The type of this message.
    let type: MessageType = .invocation
    /// The target method name.
    let target: String
    /// The target method arguments.
    let arguments: [Encodable]
    /// The target methods stream IDs.
    let streamIds: [String]?
    /// Headers attached to the message.
    let headers: [String: String]?
    /// The ID of the invocation relating to this message.
    let invocationId: String?

     func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(type, forKey: .type)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(streamIds, forKey: .streamIds)
        try container.encodeIfPresent(headers, forKey: .headers)
        try container.encodeIfPresent(invocationId, forKey: .invocationId)

        var argumentsContainer = container.nestedUnkeyedContainer(forKey: .arguments)
        for argument in arguments {
            try argumentsContainer.encode(argument)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case target
        case arguments
        case streamIds
        case headers
        case invocationId
    }
}

/// A hub message representing a streaming invocation.
struct StreamInvocationMessage: HubInvocationMessage {
    /// The type of this message.
    let type: MessageType = .streamInvocation
    /// The invocation ID.
    let invocationId: String?
    /// The target method name.
    let target: String
    /// The target method arguments.
    let arguments: [AnyCodable]
    /// The target methods stream IDs.
    let streamIds: [String]?
    /// Headers attached to the message.
    let headers: [String: String]?
}

/// A hub message representing a single item produced as part of a result stream.
struct StreamItemMessage: HubInvocationMessage {
    /// The type of this message.
    let type: MessageType = .streamItem
    /// The invocation ID.
    let invocationId: String?
    /// The item produced by the server.
    let item: AnyCodable?
    /// Headers attached to the message.
    let headers: [String: String]?
}

/// A hub message representing the result of an invocation.
struct CompletionMessage: HubInvocationMessage {
    /// The type of this message.
    let type: MessageType = .completion
    /// The invocation ID.
    let invocationId: String?
    /// The error produced by the invocation, if any.
    let error: String?
    /// The result produced by the invocation, if any.
    let result: AnyCodable?
    /// Headers attached to the message.
    let headers: [String: String]?
}

/// A hub message indicating that the sender is still active.
struct PingMessage: HubMessage {
    /// The type of this message.
    let type: MessageType = .ping
}

/// A hub message indicating that the sender is closing the connection.
struct CloseMessage: HubMessage {
    /// The type of this message.
    let type: MessageType = .close
    /// The error that triggered the close, if any.
    let error: String?
    /// If true, clients with automatic reconnects enabled should attempt to reconnect after receiving the CloseMessage.
    let allowReconnect: Bool?
}

/// A hub message sent to request that a streaming invocation be canceled.
struct CancelInvocationMessage: HubInvocationMessage {
    /// The type of this message.
    let type: MessageType = .cancelInvocation
    /// The invocation ID.
    let invocationId: String?
    /// Headers attached to the message.
    let headers: [String: String]?
}

/// A hub message representing an acknowledgment.
struct AckMessage: HubMessage {
    /// The type of this message.
    let type: MessageType = .ack
    /// The sequence ID.
    let sequenceId: Int
}

/// A hub message representing a sequence.
struct SequenceMessage: HubMessage {
    /// The type of this message.
    let type: MessageType = .sequence
    /// The sequence ID.
    let sequenceId: Int
}

/// A type-erased Codable value.
// struct AnyCodable: Codable {
//     let value: Any

//     init(_ value: Any) {
//         self.value = value
//     }

    // init(from decoder: Decoder) throws {
    //     let container = try decoder.singleValueContainer()
    //     if let intValue = try? container.decode(Int.self) {
    //         value = intValue
    //     } else if let doubleValue = try? container.decode(Double.self) {
    //         value = doubleValue
    //     } else if let stringValue = try? container.decode(String.self) {
    //         value = stringValue
    //     } else if let boolValue = try? container.decode(Bool.self) {
    //         value = boolValue
    //     } else {
    //         throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
    //     }
    // }

    // func encode(to encoder: Encoder) throws {
    //     var container = encoder.singleValueContainer()
    //     if let intValue = value as? Int {
    //         try container.encode(intValue)
    //     } else if let doubleValue = value as? Double {
    //         try container.encode(doubleValue)
    //     } else if let stringValue = value as? String {
    //         try container.encode(stringValue)
    //     } else if let boolValue = value as? Bool {
    //         try container.encode(boolValue)
    //     } else {
    //         throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
    //     }
    // }
// }