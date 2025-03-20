
import SwiftUI
import SignalRClient

struct Message: Identifiable, Equatable {
    let id: String?
    let sender: String
    var content: String
}

@MainActor
class ViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isConnected: Bool = false
    var username: String = ""
    var group: String = ""
    private var connection: HubConnection?
    
    func setupConnection() async throws {
        guard connection == nil else {
            return
        }
        
        connection = HubConnectionBuilder()
            .withUrl(url: "http://localhost:8080/chat")
            .withAutomaticReconnect()
            .build()
        
        await connection!.on("NewMessage") { (user: String, message: String) in
            self.addMessage(id: nil, sender: user, content: message)
        }
        
        await connection!.on("newMessageWithId") { (user: String, id: String, chunk: String) in
            self.addOrUpdateMessage(id: id, sender: user, chunk: chunk)
        }
        
        try await connection!.start()
        isConnected = true
    }
    
    func sendMessage(message: String) async throws {
        try await connection?.invoke(method: "Chat", arguments: self.username, message)
    }
    
    func joinGroup() async throws {
        try await connection?.invoke(method: "JoinGroup", arguments: self.group)
    }
    
    func addMessage(id: String?, sender: String, content: String) {
        DispatchQueue.main.async {
            self.messages.append(Message(id: id, sender: sender, content: content))
        }
    }
    
    func addOrUpdateMessage(id: String, sender: String, chunk: String) {
        DispatchQueue.main.async {
            if let index = self.messages.firstIndex(where: {$0.id == id}) {
                self.messages[index].content.append(chunk)
            } else {
                self.messages.append(Message(id: id, sender: sender, content: chunk))
            }
        }
    }
}
