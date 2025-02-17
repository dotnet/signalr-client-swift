import SignalRClient
import Foundation

let client = HubConnectionBuilder()
    .withUrl(url: String("http://localhost:8080/chat"))
    .withAutomaticReconnect()
    .build()

await client.on("ReceiveMessage") { (message: String) in
    print("Received message: \(message)")
}

try await client.start()

try await client.invoke(method: "Echo", arguments: "Hello")
