import SwiftUI
import SignalRClient
import WebRTC

/// 用于简化的 WebRTC 调用管理，同时集成 SignalR 信令功能
@MainActor
class WebRTCViewModel: NSObject, ObservableObject, WebRTCClientDelegate {
    
    // MARK: - Published Properties
    @Published var username: String = ""
    @Published var isConnected: Bool = false
    @Published var userList: [String] = []
    @Published var selectedUser: String? = nil
    @Published var isCallActive: Bool = false
    
    // MARK: - Private Properties
    private var signalRConnection: HubConnection?
    private var webRTCClient: WebRTCClient?
    
    /// 当前通话对方，用于信令消息发送
    private var currentCallUser: String?
    
    /// ICE 服务器列表，此处仅使用 Google 的公开 STUN 服务器
    private let iceServers = ["stun:stun.l.google.com:19302"]
    
    // MARK: - 初始化
    override init() {
        super.init()
    }
    
    // MARK: - WebRTC 初始化
    /// 初始化 WebRTCClient，并设置代理
    func setupWebRTC() {
        webRTCClient = WebRTCClient(iceServers: iceServers)
        webRTCClient?.delegate = self
        // 注意：如果需要启动摄像头采集显示本地视频，
        // 请在 View 层创建一个 RTCVideoRenderer（如 RTCEAGLVideoView 包装的 SwiftUI View），
        // 并调用 webRTCClient?.startCaptureLocalVideo(renderer: renderer)
    }
    
    // MARK: - SignalR 连接
    func connectSignalR() async throws {
        guard !username.isEmpty else { return }
        // 替换为你实际的 SignalR 服务地址
        let hubURLString = "http://localhost:8080/signalingHub?username=\(username)"
        
        signalRConnection = HubConnectionBuilder()
            .withUrl(url: hubURLString)
            .withAutomaticReconnect()
            .build()
        
        // 注册信令消息接收
        await signalRConnection?.on("ReceiveMessage") { [weak self] (user: String, messageJson: String) in
            self?.handleReceivedMessage(from: user, messageJson: messageJson)
        }
        
        // 用户上线事件
        await signalRConnection?.on("UserConnected") { [weak self] (user: String) in
            guard let self = self else { return }
            print("User Connected called: \(user)")
            if user != self.username, !(self.userList.contains(user)) {
                self.userList.append(user)
                do {
                    try await self.signalRConnection?.send(method: "Online", arguments: user)
                } catch {
                    print(error)
                }
            }
        }
        
        // 用户下线事件
        await signalRConnection?.on("UserDisconnected") { [weak self] (user: String) in
            self?.userList.removeAll(where: { $0 == user })
        }
        
        try await signalRConnection?.start()
        isConnected = true
        
        // SignalR 连接成功后，初始化 WebRTCClient
        setupWebRTC()
    }
    
    func startLocalCapture(renderer: RTCVideoRenderer) {
        webRTCClient?.startCaptureLocalVideo(renderer: renderer)
    }
    
    func startRemoteRender(to: RTCVideoRenderer) {
        webRTCClient?.renderRemoteVideo(to: to)
    }
    
    // MARK: - 信令消息结构
    struct SignalingMessage: Codable {
        let type: String
        let sdp: String?
        let candidate: Candidate?
        let user: String?
    }
    
    struct Candidate: Codable {
        let sdp: String
        let sdpMLineIndex: Int32
        let sdpMid: String?
    }
    
    // MARK: - 信令消息处理
    func handleReceivedMessage(from user: String, messageJson: String) {
        guard let data = messageJson.data(using: .utf8),
              let message = try? JSONDecoder().decode(SignalingMessage.self, from: data) else {
            return
        }
        
        switch message.type {
        case "offer":
            // 收到呼叫请求：保存当前呼叫对方，设置远端 SDP，然后自动应答（实际项目中可提示用户）
            currentCallUser = user
            if let sdp = message.sdp {
                let remoteSdp = RTCSessionDescription(type: .offer, sdp: sdp)
                webRTCClient?.set(remoteSdp: remoteSdp, completion: { [weak self] error in
                    if error == nil {
                        self?.webRTCClient?.answer(completion: { answerSdp in
                            let answerMessage = SignalingMessage(type: "answer", sdp: answerSdp.sdp, candidate: nil, user: self?.username)
                            self?.sendSignalMessage(to: user, message: answerMessage)
                            self?.isCallActive = true
                        })
                    }
                })
            }
        case "answer":
            // 对方应答，将远端 SDP 设置到 WebRTCClient 中
            if let sdp = message.sdp {
                let remoteSdp = RTCSessionDescription(type: .answer, sdp: sdp)
                webRTCClient?.set(remoteSdp: remoteSdp, completion: { [weak self] error in
                    if error == nil {
                        self?.isCallActive = true
                    }
                })
            }
        case "candidate":
            // 处理 ICE 候选消息
            if let candidateInfo = message.candidate {
                let candidate = RTCIceCandidate(sdp: candidateInfo.sdp,
                                                sdpMLineIndex: candidateInfo.sdpMLineIndex,
                                                sdpMid: candidateInfo.sdpMid)
                webRTCClient?.set(remoteCandidate: candidate, completion: { error in
                    // 如有错误，可在此处理
                })
            }
        case "hangup":
            hangUp()
        default:
            break
        }
    }
    
    private func sendSignalMessage(to user: String, message: SignalingMessage) {
        guard let messageData = try? JSONEncoder().encode(message),
              let messageJson = String(data: messageData, encoding: .utf8) else {
            return
        }
        
        Task {
            try await signalRConnection?.send(method: "SendMessage", arguments: user, messageJson)
        }
        
    }
    
    // MARK: - 呼叫控制
    /// 主动呼叫选中的用户
    func callUser() {
        guard let selectedUser = selectedUser, let webRTCClient = webRTCClient else { return }
        currentCallUser = selectedUser
        webRTCClient.offer { [weak self] sdp in
            guard let self = self, let user = self.currentCallUser else {return}
            let offerMessage = SignalingMessage(type: "offer", sdp: sdp.sdp, candidate: nil, user: self.username)
            self.sendSignalMessage(to: user, message: offerMessage)
        }
    }
    
    /// 挂断当前通话
    func hangUp() {
        // 清空 WebRTCClient（实际项目中可能需要调用 close() 等方法）
        webRTCClient = nil
        isCallActive = false
        if let target = currentCallUser {
            Task {
                try await signalRConnection?.send(method: "Hangup", arguments: target)
            }
        }
    }
    
    // MARK: - WebRTCClientDelegate 实现
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate) {
        // 发送本地 ICE 候选到对方
        let candidateMessage = SignalingMessage(type: "candidate",
                                                sdp: candidate.sdp,
                                                candidate: Candidate(sdp: candidate.sdp,
                                                                       sdpMLineIndex: candidate.sdpMLineIndex,
                                                                       sdpMid: candidate.sdpMid),
                                                user: username)
        sendSignalMessage(to: currentCallUser ?? "", message: candidateMessage)
    }
    
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState) {
        DispatchQueue.main.async {
            // 根据连接状态更新通话状态（这里只是一个简单示例）
            self.isCallActive = (state == .connected || state == .completed)
        }
    }
    
    func webRTCClient(_ client: WebRTCClient, didReceiveData data: Data) {
        // 若使用数据通道传输数据，在此处理
    }
}
