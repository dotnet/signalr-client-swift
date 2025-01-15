# SignalR Swift

SignalR Swift is a client library for connecting to SignalR servers from Swift applications.

## Installation

### Requirements

- Swift >= 5.10
- macOS >= 11.0

### Swift Package Manager

Add the project as a dependency to your Package.swift:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "signalr-client-app",
    dependencies: [
        .package(url: "https://github.com/Azure/signalr-swift")
    ],
    targets: [
        .target(name: "YourTargetName", dependencies: [.product(name: "SignalRClient", package: "signalr-swift")])
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

## Working with Streaming Responses
To receive a stream of data from the server, use the `stream` method:

```swift
let stream: any StreamResult<String> = try await connection.stream(method: "StreamMethod")
for try await item in stream.stream {
    print("Received item: \(item)")
}
```

## Handle lost connection

### Automatic reconnect

The swift client for SiganlR supports automatic reconnect. You can enable it by calling `withAutomaticReconnect()` while building the connection. It won't automatically reconnect by default.

```swift
let connection = HubConnectionBuilder()
    .withUrl(url: "https://your-signalr-server")
    .withAtuomaticReconnect()
    .build()
```

Without any parameters, `WithAutomaticReconnect` configures the client to wait 0, 2, 10, and 30 seconds respectively before trying each reconnect attempt. After four failed attempts, it stops trying to reconnect.

Before starting any reconnect attampts, the `HubConnection` transitions to the `Reconnecting` state and fires its `onReconnecting` callbacks.

### Configure strategy in automatic reconnect
In order to configure a custom number of reconnect attempts before disconnecting or change the reconnect timing, `withAutomaticReconnect` accepts an array of numbers representing the delay in milliseconds to wait before starting each reconnect attempt. 

```swift
let connection = HubConnectionBuilder()
    .withUrl(url: "https://your-signalr-server")
    .withAtuomaticReconnect([0, 0, 1]) // wait 0, 0, and 1 second before trying to reconnect and stop after 3 attempts
    .build()
```

For more control over the timing and number of automatic reconnect attempts, withAutomaticReconnect accepts an object implementing the `RetryPolicy` protocol, which has a single method named `nextRetryInterval`. The `nextRetryInterval` takes a single argument with the type `RetryContext`. The RetryContext has three properties: `retryCount`,` elapsed` and `retryReason` which are a Int, a TimeInterval and an Error respectively. Before the first reconnect attempt, both `retryCount` and `elapsed` will be zero, and the `retryReason` will be the Error that caused the connection to be lost. After each failed retry attempt, `retryCount` will be incremented by one, `elapsed` will be updated to reflect the amount of time spent reconnecting so far in seconds, and the `retryReason` will be the Error that caused the last reconnect attempt to fail.

```swift
let connection = HubConnectionBuilder()
    .withUrl(url: "https://your-signalr-server")
    .withAtuomaticReconnect({
        
    })
    .build()
```

## Support and unsupported features

| Feature                         | Supported |
|---------------------------------|-----------|
| Automatic Reconnect             |✅|
| Stateful Reconnect              ||
| Server to Client Streaming      |✅|
| Client to Server Streaming      ||
| Long Polling                    |✅|
| Server-Sent Events              |✅|
| WebSockets                      |✅|
| JSON Protocol                   |✅|
| MessagePack Protocol            |✅|
| Client Invocation               ||
