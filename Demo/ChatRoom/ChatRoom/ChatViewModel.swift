// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import SwiftUI
import SignalRClient

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [String] = []
    @Published var isConnected: Bool = false
    var username: String = ""
    private var connection: HubConnection?
 
    func setupConnection() async throws {
        guard connection == nil else {
            return
        }
        
        connection = HubConnectionBuilder()
            .withUrl(url: "http://localhost:8080/chat")
            .withAutomaticReconnect()
            .build()

        await connection!.on("message") { (user: String, message: String) in
            DispatchQueue.main.async {
                self.messages.append("\(user): \(message)")
            }
        }
 
        try await connection!.start()
        isConnected = true
    }
 
    func sendMessage(user: String, message: String) async throws {
        try await connection?.invoke(method: "Broadcast", arguments: username, message)
    }
}
