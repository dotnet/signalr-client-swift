# SignalR Swift

SignalR Swift is a client library for connecting to SignalR servers from Swift applications.

## Installation

### Requirements

- Swift >= 5.10
- macOS >= 11.0
- iOS >= 14

### Swift Package Manager

Add the project as a dependency to your Package.swift from a version:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "signalr-client-app",
    dependencies: [
        .package(url: "https://github.com/dotnet/signalr-client-swift", .upToNextMinor(from: "1.0.0"))
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
| Stateful Reconnect              |✅|
| Server to Client Streaming      |✅|
| Client to Server Streaming      |✅|
| Long Polling                    |✅|
| Server-Sent Events              |✅|
| WebSockets                      |✅|
| JSON Protocol                   |✅|
| MessagePack Protocol            |✅|
| Client Results                  |✅|

# Code of Conduct

This project has adopted the code of conduct defined by the Contributor Covenant
to clarify expected behavior in our community.

For more information, see the [.NET Foundation Code of Conduct](https://dotnetfoundation.org/code-of-conduct).

# License

.NET (including the runtime repo) is licensed under the MIT license.

## :twisted_rightwards_arrows: Branch strategy and protection

This repository is SpringTree's fork of
[`dotnet/signalr-client-swift`](https://github.com/dotnet/signalr-client-swift).

The default branch is `dev`. It has protection enabled against direct pushes,
through the organisation ruleset "Enforce PR workflow":

- All changes go through a pull request. Merges are squash or rebase only, and
  the history must stay linear.
- Force pushes and deleting the branch are blocked.
- Changes to the policy files (`.github/CODEOWNERS`,
  `.github/workflows/compliance.yml` and `licence-exemptions.json`) need a
  review from `@springtreesolutions/springtree-admins` (see
  `.github/CODEOWNERS`).
- The four `supply-chain / *` checks (`secrets`, `licences`, `code`,
  `quarantine`) run on every pull request. An admin makes them required checks
  for this repository.

Other branches on this fork:

- `feat/swarm`
- `feature/connection-status`
- `feature/custom-json-decoder`

This fork has no `main` branch. Upstream uses `main` for releases and `dev` for
development.

## :lock: Compliance

This repository is gated by SpringTree's shared supply-chain workflow
(`.github/workflows/compliance.yml`), which runs four checks on every pull
request and a full-history scan weekly:

| Gate         | Refuses                                                 |
| ------------ | ------------------------------------------------------- |
| `secrets`    | a credential committed anywhere in the scanned range    |
| `licences`   | a dependency whose licence is not on the allow-list     |
| `code`       | a code pattern the ruleset classes as a security defect |
| `quarantine` | missing or incorrect package-cooldown configuration     |

A red gate is fixed here, in this repository. What each gate does and which
inputs it takes is documented in
[`springtree-ci-workflows`](https://github.com/SpringTree/springtree-ci-workflows).

### :mag: Before you push

```bash
git config core.hooksPath .githooks   # once per clone
brew install gitleaks                 # once per machine
```

The hook scans the commits you are about to push and refuses the push when
gitleaks is not installed. It is feedback, not enforcement: `--no-verify` skips
it and CI does not. Skipping is break-glass.

## :up: Deploying

This is a library. Nothing is deployed. Apps consume it as a Swift package
straight from git: Swift Package Manager resolves a version from a git tag, a
branch or a commit. There is no package registry.

The workflows in `.github/workflows` come from upstream. What they do on this
fork today:

- `swift.yml` (Swift): on every push and pull request to `dev` (and `main`),
  builds the package and runs the unit tests and the integration tests on
  macOS 14. The integration tests start the .NET test server in
  `Tests/IntegrationTestServer`. It needs no secrets.
- `swift-e2e.yml` (Swift E2E Test): same triggers. It runs the integration
  tests against Azure SignalR Service and needs the secret
  `E2E_CONNECTION_STRING`. This fork does not have that secret as a repository
  secret, so this workflow fails unless an organisation secret provides it.
- `release.yml` (Release version (tag)): started by hand. It checks out `main`,
  tags the version in `Sources/SignalRClient/Version.swift` as `v<version>`,
  pushes the tag and opens a pull request that bumps the version. This fork has
  no `main` branch, so the workflow fails at checkout.

This fork has no release tags of its own. The `v1.0.0` tags belong to
upstream. Until this fork has a release process, an app that uses this fork
pins a branch or a commit of
`https://github.com/springtreesolutions/signalr-client-swift`.
