# SignalR Swift

## Description
SignalR Swift is a client library for ASP.NET Core SignalR that enables real-time web functionality to apps. This library allows you to add real-time features to your iOS applications using Swift.

## Installation
To install SignalR Swift, you can use CocoaPods or Swift Package Manager.

### CocoaPods (Not implemented yet)
Add the following line to your Podfile:
```ruby
pod 'SignalRSwift'
```
Then run:
```sh
pod install
```

### Swift Package Manager
Add the following dependency to your `Package.swift` file:
```swift
dependencies: [
    .package(url: "https://github.com/your-repo/signalr-swift.git", from: "1.0.0")
]
```

## Usage
Here is a basic example of how to use SignalR Swift in your project:

```swift
import SignalRSwift

let connection = HubConnectionBuilder(url: URL(string: "https://your-signalr-server")!)
    .withLogging(minLogLevel: .debug)
    .build()

connection.on(method: "ReceiveMessage") { (user: String, message: String) in
    print("\(user): \(message)")
}

connection.start()
```

### Invoking Methods
You can invoke server methods using the `invoke` method:

```swift
connection.invoke(method: "SendMessage", "user", "message") { error in
    if let error = error {
        print("Error calling SendMessage: \(error)")
    } else {
        print("SendMessage invoked successfully")
    }
}
```

### Streaming
You can receive a stream of data from the server using the `stream` method:

```swift
let stream = connection.stream(method: "Counter", 10)

stream.observe { value in
    print("Received value: \(value)")
}

stream.start()
```

### Handling Connection Events
You can handle connection events such as starting, closing, and reconnecting:

```swift
connection.onConnected = {
    print("Connection started")
}

connection.onDisconnected = { error in
    if let error = error {
        print("Connection closed with error: \(error)")
    } else {
        print("Connection closed")
    }
}

connection.onReconnecting = { error in
    print("Reconnecting due to error: \(error)")
}

connection.onReconnected = {
    print("Reconnected")
}
```

## Contributing
Contributions are welcome! Please fork the repository and submit a pull request.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contact Information
For any questions or suggestions, please contact [your-email@example.com](mailto:your-email@example.com).
