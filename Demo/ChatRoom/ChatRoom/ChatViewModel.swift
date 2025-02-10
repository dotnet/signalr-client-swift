import SwiftUI
import SignalRClient

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [String] = []
    var username: String = ""
    private var connection: HubConnection?
 
    init() {
        Task {
            try await setupConnection()
        }
    }
 
    private func setupConnection() async throws {
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
    }
 
    func sendMessage(user: String, message: String) async throws {
        try await connection?.invoke(method: "Broadcast", arguments: username, message)
    }
}
