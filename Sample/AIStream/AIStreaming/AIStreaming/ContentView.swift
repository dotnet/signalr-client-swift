import SwiftUI

struct ContentView: View {
    var body: some View {
        ChatView(viewModel: ViewModel())
    }
}

struct ChatView: View {
    @ObservedObject var viewModel: ViewModel
    @State private var inputText: String = ""
    @State private var isShowingEntrySheet: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Group: \(viewModel.group)")
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.8))
                .foregroundColor(.white)
            
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.messages) { message in
                            MessageView(message: message, selfUser: viewModel.username)
                        }
                    }
                    .padding()
                }
                .background(Color.platformBackground)
                .onChange(of: viewModel.messages) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }
            
            Divider()
            
            // Input Field and Send Button
            HStack {
                TextField("Type your message here... Use @gpt to invoke in a LLM model", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(8)
                
                Button("Send") {
                    sendMessage()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding(8)
            }
            .padding()
        }
        .sheet(isPresented: $isShowingEntrySheet) {
            UserEntryView(isPresented: $isShowingEntrySheet, viewModel: viewModel)
        }
        .frame(minWidth: 400, minHeight: 500)
    }
    
    // Scroll to the latest message
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = self.viewModel.messages.last {
            DispatchQueue.main.async {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        Task {
            viewModel.addMessage(id: UUID().uuidString, sender: viewModel.username, content: inputText)
            try await viewModel.sendMessage(message: inputText)
            inputText = ""
        }
    }
}

struct MessageView: View {
    let message: Message
    let selfUser: String
    
    var body: some View {
        HStack {
            let isSelf = message.sender == selfUser
            if isSelf {
                Spacer()
                VStack(alignment: .trailing) {
                    Text(message.sender)
                        .font(.caption)
                        .bold()
                        .foregroundColor(.green)
                    Text(message.content)
                        .padding(8)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(8)
                }
                .frame(maxWidth: 250, alignment: .trailing)
            } else {
                VStack(alignment: .leading) {
                    Text(message.sender)
                        .font(.caption)
                        .bold()
                        .foregroundColor(.blue)
                    Text(message.content)
                        .padding(8)
                        .background(Color.platformBackground)
                        .cornerRadius(8)
                }
                .frame(maxWidth: 250, alignment: .leading)
                Spacer()
            }
        }
    }
}

struct UserEntryView: View {
    @State var username: String = ""
    @State var group: String = ""
    @Binding var isPresented: Bool
    var viewModel: ViewModel
    
    var body: some View {
            VStack {
                Text("Enter your username")
                    .font(.headline)
                    .padding()
     
                TextField("Username", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                TextField("Create or Join Group", text: $group)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
     
                Button(action: {
                    if !username.isEmpty && !group.isEmpty {
                        isPresented = false
                        viewModel.username = username
                        viewModel.group = group
     
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

extension Color {
    static var platformBackground : Color {
#if os(macOS)
        return Color(NSColor.windowBackgroundColor)
#else
        return Color(UIColor.systemBackground)
#endif
    }
}
