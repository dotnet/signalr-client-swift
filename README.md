# SignalR Swift

SignalR Swift is a client library for connecting to SignalR servers from Swift applications.

## Installation

### Requirements

- Swift >= 5.10
- macOS >= 11.0
- iOS >= 14

### Swift Package Manager

Add the project as a dependency to your Package.swift from a verion:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "signalr-client-app",
    dependencies: [
        .package(url: "https://github.com/dotnet/signalr-client-swift", .upToNextMinor(from: "1.0.0-preview.3"))
    ],
    targets: [
        .executableTarget(name: "YourTargetName", dependencies: [.product(name: "SignalRClient", package: "signalr-client-swift")])
    ]
)
```

Also you can add the project as a dependency to your Package.swift from a git branch:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "signalr-client-app",
    dependencies: [
        .package(url: "https://github.com/dotnet/signalr-client-swift", branch: "main")
    ],
    targets: [
        .executableTarget(name: "YourTargetName", dependencies: [.product(name: "SignalRClient", package: "signalr-client-swift")])
    ]
)
```

The you can use with `import SignalRClient` in your code.

## Connect to a hub

To entablish a connection, create a `HubConnectionBuilder` and call `build()`. Url is required to connect to a server, thus you need to use `withUrl()` while building the connection. After the connection is built, you can call `start()` to connect to the server.

```swift
import SignalRClient

let connection = HubConnectionBuilder()
    .withUrl(url: "https://your-signalr-server")
    .build()

try await connection.start()
```

## Handle hub method calls from the server

You can listen for events from the server using the `on` method. The `on` method takes the name of the method and a closure that will be called when the server calls the method.

```swift
await connection.on("ReceiveMessage") { (user: String, message: String) in
    print("\(user) says: \(message)")
}
```

## Call hub method calls to the server

Swift clients can also call public methods on hubs via the send method of the HubConnection. `invoke` will wait until the server response. And it will throw if there's an error sending message. Unlike the `invoke` method, the `send` method doesn't wait for a response from the server. Consequently, it's not possible to return data or errors from the server.

```swift
try await connection.invoke(method: "SendMessage", arguments: "myUser", "Hello")

try await connection.send(method: "SendMessage", arguments: "myUser", "Hello")
```

## Client results

In addition to making calls to clients, the server can request a result from a client. This requires the server to use `ISingleClientProxy.InvokeAsync` and the client to return a result from its `.on` handler.

```swift
await connection.on("ClientResult") { (message: String) in
    return "client response"
}
```

In the following example, the server calls the `ClientResult` method on the client and waits for the client to return a result. The message will be "client response".
```C#
public class ChatHub : Hub
{
    public async Task TriggerClientResult()
    {
        var message = await Clients.Client(connectionId).InvokeAsync<string>("ClientResult");
    }
}
```

## Working with Streaming Responses
To receive a stream of data from the server, use the `stream` method:

```swift
let stream: any StreamResult<String> = try await connection.stream(method: "StreamMethod")
for try await item in stream.stream {
    print("Received item: \(item)")
}
```

## Client-to-server streaming
To send a stream of data from the client to the server, use the `AsyncStream`:

```swift
let (clientStream, continuation) = AsyncStream.makeStream(of: Int.self)
try await connection.send("UploadStream", arguments: clientStream)
for i in 1...100 {
    continuation.yield(i)
}
continuation.finish()
``` 

## Handle lost connection

### Automatic reconnect

The swift client for SiganlR supports automatic reconnect. You can enable it by calling `withAutomaticReconnect()` while building the connection. It won't automatically reconnect by default.

```swift
let connection = HubConnectionBuilder()
    .withUrl(url: "https://your-signalr-server")
    .withAutomaticReconnect()
    .build()
```

Without any parameters, `WithAutomaticReconnect` configures the client to wait 0, 2, 10, and 30 seconds respectively before trying each reconnect attempt. After four failed attempts, it stops trying to reconnect.

Before starting any reconnect attempts, the `HubConnection` transitions to the `Reconnecting` state and fires its `onReconnecting` callbacks.

After the reconnection succeeds, the `HubConnection` transitions to the `connected` state and fires its `onReconnected` callbacks.

A general way to use `onReconnecting` and `onReconnected` is to mark the connection state changes:

```swift
connection.onReconnecting { error in
    // connection is disconnected because of error
}

connection.onReconnected {
    // connection is connected back
}
```

### Configure strategy in automatic reconnect
In order to configure a custom number of reconnect attempts before disconnecting or change the reconnect timing, `withAutomaticReconnect` accepts an array of numbers representing the delay in seconds to wait before starting each reconnect attempt. 

```swift
let connection = HubConnectionBuilder()
    .withUrl(url: "https://your-signalr-server")
    .withAutomaticReconnect([0, 0, 1]) // wait 0, 0, and 1 second before trying to reconnect and stop after 3 attempts
    .build()
```

For more control over the timing and number of automatic reconnect attempts, withAutomaticReconnect accepts an object implementing the `RetryPolicy` protocol, which has a single method named `nextRetryInterval`. The `nextRetryInterval` takes a single argument with the type `RetryContext`. The RetryContext has three properties: `retryCount`,` elapsed` and `retryReason` which are a Int, a TimeInterval and an Error respectively. Before the first reconnect attempt, both `retryCount` and `elapsed` will be zero, and the `retryReason` will be the Error that caused the connection to be lost. After each failed retry attempt, `retryCount` will be incremented by one, `elapsed` will be updated to reflect the amount of time spent reconnecting so far in seconds, and the `retryReason` will be the Error that caused the last reconnect attempt to fail.

```swift
// Define a customized retry policy
struct CustomRetryPolicy: RetryPolicy {
    func nextRetryInterval(retryContext: RetryContext) -> TimeInterval? {
        return 1 // unlimited retry with 1 second
    }
}

let connection = HubConnectionBuilder()
    .withUrl(url: "https://your-signalr-server")
    .withAutomaticReconnect(CustomRetryPolicy())
    .build()
```

## Configure timeout and keep-alive options

| Options | Default Value | Description |
|---------|---------------|-------------|
|withKeepAliveInterval| 15 (seconds)|Determines the interval at which the client sends ping messages and is set directly on HubConnectionBuilder. This setting allows the server to detect hard disconnects, such as when a client unplugs their computer from the network. Sending any message from the client resets the timer to the start of the interval. If the client hasn't sent a message in the ClientTimeoutInterval set on the server, the server considers the client disconnected.|
|withServerTimeout| 30 (seconds)|Determines the interval at which the client waits for a response from the server before it considers the server disconnected. This setting is set directly on HubConnectionBuilder.|

## Configure transport

The SignalR Swift client supports three transports: LongPolling, ServerSentEvents, and WebSockets. By default, the client will use WebSockets if the server supports it, and fall back to ServerSentEvents and LongPolling if it doesn't. You can configure the client to use a specific transport by calling `withUrl(url:transport:)` while building the connection.

```swift
let connection = HubConnectionBuilder()
    .withUrl(url: "https://your-signalr-server", transport: .webSockets) // use websocket only
    .build()
```

```swift
let connection = HubConnectionBuilder()
    .withUrl(url: "https://your-signalr-server", transport: [.webSockets, .serverSentEvents]) // use websockets and server sent events
    .build()
```

## Support and unsupported features

| Feature                         | Supported |
|---------------------------------|-----------|
| Azure SignalR Service Support   |✅|
| Automatic Reconnection          |✅|
| Stateful Reconnect              ||
| Server to Client Streaming      |✅|
| Client to Server Streaming      |✅|
| Long Polling                    |✅|
| Server-Sent Events              |✅|
| WebSockets                      |✅|
| JSON Protocol                   |✅|
| MessagePack Protocol            |✅|
| Client Results                  |✅|

# License

.NET (including the runtime repo) is licensed under the MIT license.
