/// Defines the type of a Hub Message.
public enum MessageType: Int, Codable {
    /// Indicates the message is an Invocation message.
    case invocation = 1
    /// Indicates the message is a StreamItem message.
    case streamItem = 2
    /// Indicates the message is a Completion message.
    case completion = 3
    /// Indicates the message is a Stream Invocation message.
    case streamInvocation = 4
    /// Indicates the message is a Cancel Invocation message.
    case cancelInvocation = 5
    /// Indicates the message is a Ping message.
    case ping = 6
    /// Indicates the message is a Close message.
    case close = 7
    /// Indicates the message is an Acknowledgment message.
    case ack = 8
    /// Indicates the message is a Sequence message.
    case sequence = 9
}