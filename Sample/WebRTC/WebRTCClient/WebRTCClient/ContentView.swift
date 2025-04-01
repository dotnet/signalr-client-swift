import SwiftUI
import SignalRClient
import WebRTC
import AVFoundation

struct ContentView: View {
    @StateObject var viewModel = WebRTCViewModel()
    @State private var localRendererView = VideoRendererView()
    @State private var remoteRendererView = VideoRendererView()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("WebRTC Demo")
                .font(.largeTitle)
            
            HStack {
                Text("Username:")
                TextField("Enter username", text: $viewModel.username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(viewModel.isConnected)
            }
            .padding(.horizontal)
            
            Button("Connect SignalR") {
                Task {
                    try await viewModel.connectSignalR()
                    viewModel.startLocalCapture(renderer: localRendererView.renderer)
                }
            }
            .disabled(viewModel.username.isEmpty || viewModel.isConnected)
            
            Divider()
            
            HStack {
                Text("User List:")
                Picker("Select a user", selection: $viewModel.selectedUser) {
                    Text("None").tag(nil as String?)
                    ForEach(viewModel.userList, id: \.self) { user in
                        Text(user).tag(Optional(user))
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            .padding(.horizontal)
            
            Button("Call User") {
                viewModel.callUser()
            }
            .disabled(viewModel.selectedUser == nil || !viewModel.isConnected)
            
            Divider()
            
            HStack {
                VideoRendererViewWrapper(videoRendererView: localRendererView)
                                    .frame(width: 150, height: 150)
                                    .border(Color.black)
                VideoRendererViewWrapper(videoRendererView: remoteRendererView)
                    .frame(width: 150, height: 150)
                    .border(Color.black)
            }
            
            Button("Hang Up") {
                viewModel.hangUp()
            }
            .disabled(!viewModel.isCallActive)
            
            Spacer()
        }
        .onAppear {
            viewModel.setupWebRTC()
        }
        .onChange(of: viewModel.isCallActive) {active in
            if active {
                viewModel.startRemoteRender(to: remoteRendererView.renderer)
            }
        }
    }
}

final class VideoRendererView {
    let renderer: RTCVideoRenderer
    let view: UIView
    
    init() {
        let videoView = RTCMTLVideoView(frame: .zero)
        self.view = videoView
        self.renderer = videoView
    }
}

/// UIViewRepresentable 包装 VideoRendererView 以在 SwiftUI 中展示
struct VideoRendererViewWrapper: UIViewRepresentable {
    let videoRendererView: VideoRendererView
    
    func makeUIView(context: Context) -> UIView {
        videoRendererView.view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // 无需更新
    }
}
