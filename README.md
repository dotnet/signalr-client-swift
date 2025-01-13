# SignalR Swift

SignalR Swift is a client library for connecting to SignalR servers from Swift applications.

## Client Interface

### Connecting to a Server
To connect to a SignalR server:

```swift
let connection = HubConnectionBuilder()
    .withUrl(url: "https://your-signalr-server")
    .build()

try await connection.start()
```

### Listening for Events
You can listen for events from the server using the `on` method:

```swift
connection.on("ReceiveMessage") { (user: String, message: String) in
    print("\(user): \(message)")
}
```

### Call hub methods from client
To send a message to the server, use the `send` method:

```swift
try await connection.send(method: "SendMessage", arguments: "Hello", 123)
```

### Invoking hub methods from client
To invoke a method on the server and receive a result, use the `invoke` method:

```swift
let result: String = try await connection.invoke(method: "Echo", arguments: "Hello")
print("Received result: \(result)")
```

### Working with Streaming Responses
To receive a stream of data from the server, use the `stream` method:

```swift
let stream: any StreamResult<String> = try await connection.stream(method: "StreamMethod")
for try await item in stream.stream {
    print("Received item: \(item)")
}
```
