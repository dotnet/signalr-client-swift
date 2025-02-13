/// An abstraction over the behavior of transports.
/// This is designed to support the framework and not intended for use by applications.
protocol Transport: Sendable {
    /// Connects to the specified URL with the given transfer format.
    /// - Parameters:
    ///   - url: The URL to connect to.
    ///   - transferFormat: The transfer format to use.
    func connect(url: String, transferFormat: TransferFormat) async throws

    /// Sends data over the transport.
    /// - Parameter data: The data to send.
    func send(_ data: StringOrData) async throws

    /// Stops the transport.
    func stop(error: Error?) async throws

    /// A closure that is called when data is received.
    func onReceive(_ handler: OnReceiveHandler?) async

    /// A closure that is called when the transport is closed.
    func onClose(_ handler: OnCloseHander?) async

    typealias OnReceiveHandler = @Sendable (StringOrData) async -> Void

    typealias OnCloseHander = @Sendable (Error?) async -> Void
}
