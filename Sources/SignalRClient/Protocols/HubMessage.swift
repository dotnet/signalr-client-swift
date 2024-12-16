/// Defines properties common to all Hub messages.
protocol HubMessage: Encodable {
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
    let arguments: AnyEncodableArray
    /// The target methods stream IDs.
    let streamIds: [String]?
    /// Headers attached to the message.
    let headers: [String: String]?
    /// The ID of the invocation relating to this message.
    let invocationId: String?
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
    let arguments: AnyEncodableArray
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
    let item: AnyEncodable
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
    let result: AnyEncodable
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
    let sequenceId: Int64
}

/// A hub message representing a sequence.
struct SequenceMessage: HubMessage {
    /// The type of this message.
    let type: MessageType = .sequence
    /// The sequence ID.
    let sequenceId: Int64
}

/// A type-erased Codable value.
struct AnyEncodable: Encodable {
    public let value: Any?

    init(_ value: Any?) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        // Null
        guard let value = value else {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
            return
        }

        // Primitives and Encodable custom class
        if let encodable = value as? Encodable {
            try encodable.encode(to: encoder)
            return
        }

        // Array
        if let array = value as? [Any] {
            try AnyEncodableArray(array).encode(to: encoder)
            return
        }

        // Dictionary
        if let dictionary = value as? [String: Any] {
            try AnyEncodableDictionary(dictionary).encode(to: encoder)
            return
        }

        // Unsupported type
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
    }
}

struct AnyEncodableArray: Encodable {
    public let value: [Any?]?

    init(_ array: [Any?]?) {
        self.value = array
    }

    func encode(to encoder: Encoder) throws {
        guard let value = value else {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
            return
        }

        var container = encoder.unkeyedContainer()
        for value in value {
            try AnyEncodable(value).encode(to: container.superEncoder())
        }
    }
}

struct AnyEncodableDictionary: Encodable {
    public let value: [String: Any]?

    init(_ dictionary: [String: Any]?) {
        self.value = dictionary
    }

    func encode(to encoder: Encoder) throws {
        guard let value = value else {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
            return
        }

        var container = encoder.container(keyedBy: AnyEncodableCodingKey.self)
        for (key, value) in value {
            let codingKey = AnyEncodableCodingKey(stringValue: key)!
            try AnyEncodable(value).encode(to: container.superEncoder(forKey: codingKey))
        }
    }
}

struct AnyEncodableCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
