// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

protocol ConnectionProtocol: AnyObject, Sendable {
    func onReceive(_ handler: @escaping Transport.OnReceiveHandler) async
    func onClose(_ handler: @escaping Transport.OnCloseHander) async
    func start(transferFormat: TransferFormat) async throws
    func send(_ data: StringOrData) async throws
    func stop(error: Error?) async
    var inherentKeepAlive: Bool { get async }
}