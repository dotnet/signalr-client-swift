protocol ConnectionProtocol: AnyObject, Sendable {
    func onReceive(_ handler: @escaping Transport.OnReceiveHandler) async
    func onClose(_ handler: @escaping Transport.OnCloseHander) async
    func start(transferFormat: TransferFormat) async throws
    func send(_ data: StringOrData) async throws
    func stop(error: Error?) async
    var inherentKeepAlive: Bool { get async }
}