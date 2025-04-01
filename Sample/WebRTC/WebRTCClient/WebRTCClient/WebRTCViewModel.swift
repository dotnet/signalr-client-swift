import SwiftUI
import SignalRClient
import WebRTC

@MainActor
class WebRTCViewModel: NSObject, ObservableObject, WebRTCClientDelegate {
    @Published var username: String = ""
    @Published var isConnected: Bool = false
    @Published var userList: [String] = [] {
        didSet {
            if let selected = selectedUser, !userList.contains(selected) {
                selectedUser = nil
            }
        }
    }
    @Published var selectedUser: String? = nil
    @Published var isCallActive: Bool = false
    
    private var signalRConnection: HubConnection?
    private var webRTCClient: WebRTCClient?
    
    private var currentCallUser: String?
    
    private let iceServers = ["stun:stun.l.google.com:19302"]
    
    override init() {
        super.init()
    }
    
    func setupWebRTC() {
        webRTCClient = WebRTCClient(iceServers: iceServers)
        webRTCClient?.delegate = self
    }
    
    func connectSignalR() async throws {
        guard !username.isEmpty else { return }
        let hubURLString = "http://localhost:8080/signalingHub?username=\(username)"
        
        signalRConnection = HubConnectionBuilder()
            .withUrl(url: hubURLString)
            .withAutomaticReconnect()
            .build()
        
        await signalRConnection?.on("ReceiveMessage") { [weak self] (user: String, messageJson: String) in
            self?.handleReceivedMessage(from: user, messageJson: messageJson)
        }
        
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
        
        await signalRConnection?.on("UserDisconnected") { [weak self] (user: String) in
            self?.userList.removeAll(where: { $0 == user })
        }
        
        try await signalRConnection?.start()
        isConnected = true
        
        setupWebRTC()
    }
    
    func startLocalCapture(renderer: RTCVideoRenderer) {
        webRTCClient?.startCaptureLocalVideo(renderer: renderer)
    }
    
    func startRemoteRender(to: RTCVideoRenderer) {
        webRTCClient?.renderRemoteVideo(to: to)
    }
    
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
    
    func handleReceivedMessage(from user: String, messageJson: String) {
        guard let data = messageJson.data(using: .utf8),
              let message = try? JSONDecoder().decode(SignalingMessage.self, from: data) else {
            return
        }
        
        switch message.type {
        case "offer":
            currentCallUser = user
            if let sdp = message.sdp {
                let remoteSdp = RTCSessionDescription(type: .offer, sdp: sdp)
                webRTCClient?.set(remoteSdp: remoteSdp, completion: { [weak self] error in
                    if error == nil {
                        self?.webRTCClient?.answer(completion: { answerSdp in
                            let answerMessage = SignalingMessage(type: "answer", sdp: answerSdp.sdp, candidate: nil, user: self?.username)
                            DispatchQueue.main.async {
                                self?.sendSignalMessage(to: user, message: answerMessage)
                                self?.isCallActive = true
                            }
                        })
                    }
                })
            }
        case "answer":
            if let sdp = message.sdp {
                let remoteSdp = RTCSessionDescription(type: .answer, sdp: sdp)
                webRTCClient?.set(remoteSdp: remoteSdp, completion: { [weak self] error in
                    if error == nil {
                        DispatchQueue.main.async {
                            self?.isCallActive = true
                        }
                    }
                })
            }
        case "candidate":
            if let candidateInfo = message.candidate {
                let candidate = RTCIceCandidate(sdp: candidateInfo.sdp,
                                                sdpMLineIndex: candidateInfo.sdpMLineIndex,
                                                sdpMid: candidateInfo.sdpMid)
                webRTCClient?.set(remoteCandidate: candidate, completion: { error in
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
    
    func callUser() {
        guard let selectedUser = selectedUser, let webRTCClient = webRTCClient else { return }
        currentCallUser = selectedUser
        webRTCClient.offer { [weak self] sdp in
            guard let self = self, let user = self.currentCallUser else {return}
            let offerMessage = SignalingMessage(type: "offer", sdp: sdp.sdp, candidate: nil, user: self.username)
            self.sendSignalMessage(to: user, message: offerMessage)
        }
    }
    
    func hangUp() {
        webRTCClient = nil
        isCallActive = false
        if let target = currentCallUser {
            Task {
                try await signalRConnection?.send(method: "Hangup", arguments: target)
            }
        }
    }
    
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate) {
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
            self.isCallActive = (state == .connected || state == .completed)
        }
    }
    
    func webRTCClient(_ client: WebRTCClient, didReceiveData data: Data) {
    }
}
