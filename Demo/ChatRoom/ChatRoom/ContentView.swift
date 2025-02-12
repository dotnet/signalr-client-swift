import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var messageText: String = ""
    @State private var username: String = ""
    @State private var isShowingUsernameSheet: Bool = true

    var body: some View {
        VStack {
            Text(viewModel.isConnected ? "Connected" : "Disconnected")
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(5)
                .background(viewModel.isConnected ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                .foregroundColor(.white)

            Text("User: \(username)")
                .font(.headline)
                .frame(minHeight: 15)
                .padding()

            List(viewModel.messages, id: \.self) { message in
                Text(message)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }

            HStack {
                TextField("Type your message here...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minHeight: 15)
                    .padding()

                Button(action: {
                    Task {
                        try await viewModel.sendMessage(user: "user", message: messageText)
                        messageText = ""
                    }
                }) {
                    Text("Send")
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .padding()
        }
        .sheet(isPresented: $isShowingUsernameSheet) {
            UsernameEntryView(username: $username, isPresented: $isShowingUsernameSheet, viewModel: viewModel)
                .frame(width: 300, height: 200) // 设定弹窗大小
        }
    }
}

struct UsernameEntryView: View {
    @Binding var username: String
    @Binding var isPresented: Bool
    var viewModel: ChatViewModel

    var body: some View {
        VStack {
            Text("Enter your username")
                .font(.headline)
                .padding()

            TextField("Username", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button(action: {
                if !username.isEmpty {
                    isPresented = false
                    viewModel.username = username

                    Task {
                        try await viewModel.setupConnection()
                    }
                }
            }) {
                Text("Enter")
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)
            .frame(width: 120)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
