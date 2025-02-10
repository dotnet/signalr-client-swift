import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var messageText: String = ""
    @State private var username: String = ""
    @State private var isUsernameEntered: Bool = false
 
    var body: some View {
        VStack {
            if (!isUsernameEntered) {
                Text("Enter your username")
                    .font(.headline)
                    .padding()
                
                TextField("Username", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                Button(action: {
                    if !username.isEmpty {
                        isUsernameEntered = true
                        viewModel.username = username
                    }
                }) {
                    Text("Enter")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            } else {
                Text("User: \(username)")
                    .font(.headline)
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
                        .frame(minHeight: 30)
     
                    Button(action: {
                        Task {
                            try await viewModel.sendMessage(user: "user", message: messageText)
                            messageText = ""
                        }
                    }) {
                        Text("Send")
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
    }
}

#Preview {
    ContentView()
}
