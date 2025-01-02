# SignalR-Swift

SignalR-Swift is a client library for ASP.NET SignalR, written in Swift. It allows you to add real-time web functionality to your iOS and macOS applications.

## Features

- Real-time communication between server and clients
- Supports both WebSockets and Server-Sent Events (SSE)
- Automatic reconnection
- Easy integration with existing SignalR hubs

## Requirements

- 11+
- Swift 5.10+

## Installation

### CocoaPods

Add the following to your `Podfile`:

```ruby
pod 'SignalR-Swift'
```

Then run:

```sh
pod install
```

### Carthage

Add the following to your `Cartfile`:

```
github "yourusername/SignalR-Swift"
```

Then run:

```sh
carthage update
```

## Usage

### Connecting to a Hub

```swift
import SignalRSwift

let hubConnection = HubConnectionBuilder(url: URL(string: "https://your-signalr-server.com/signalr")!)
    .withLogging(minLogLevel: .debug)
    .build()

let chatHub = hubConnection.createHubProxy(hubName: "chatHub")

hubConnection.start()
```

### Sending Messages

```swift
chatHub.invoke(method: "SendMessage", arguments: ["Hello, World!"])
```

### Receiving Messages

```swift
chatHub.on(method: "ReceiveMessage") { args in
    if let message = args[0] as? String {
        print("Received message: \(message)")
    }
}
```
### Server-to-Client Streaming

```swift
chatHub.on(method: "StreamMessages") { args, streamItem in
    if let message = streamItem as? String {
        print("Streamed message: \(message)")
    }
}
```

### Client-to-Server Streaming

```swift
let stream = hubConnection.stream(method: "UploadStream", arguments: [])

stream.send(item: "First message")
stream.send(item: "Second message")
stream.complete()
```
## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## Acknowledgements

This project is inspired by the [ASP.NET SignalR](https://github.com/SignalR/SignalR) library.
