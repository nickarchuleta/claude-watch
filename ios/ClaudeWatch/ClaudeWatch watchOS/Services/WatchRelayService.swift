import Foundation
import WatchConnectivity

/// Routes all watch traffic through the paired iPhone (WCSession).
/// Works when iPhone is on cellular or remote Tailscale — watch does not need Mac LAN access.
@MainActor
final class WatchRelayService: ObservableObject {
    static let shared = WatchRelayService()

    @Published private(set) var isActive = false
    @Published private(set) var lastError: String?

    var onTerminalLines: (([TerminalLine]) -> Void)?
    var onApproval: ((ApprovalRequest) -> Void)?
    var onSessionState: ((SessionState) -> Void)?
    var onSessions: (([AgentSession]) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?

    private let sessionManager = WatchSessionManager.shared

    private init() {
        sessionManager.activate()
        sessionManager.onMessageReceived = { [weak self] message in
            Task { @MainActor in
                self?.handleMessage(message)
            }
        }
        sessionManager.onApplicationContextReceived = { [weak self] dict in
            Task { @MainActor in
                self?.handleContext(dict)
            }
        }
    }

    func start() {
        isActive = true
        lastError = nil
        if let state = sessionManager.lastReceivedState {
            applySessionState(state)
        }
    }

    func stop() {
        isActive = false
    }

    // MARK: - Outbound (watch -> iPhone -> Mac)

    func sendVoiceCommand(_ text: String) {
        let message = WatchMessage.voiceCommand(
            WatchMessage.VoiceCommand(transcribedText: text)
        )
        sessionManager.send(message)
    }

    func sendApprovalOption(
        permissionId: String,
        optionLabel: String,
        index: Int,
        optionCount: Int,
        question: String?
    ) {
        let response = WatchMessage.ApprovalOptionResponse(
            permissionId: permissionId,
            optionLabel: optionLabel,
            optionIndex: index,
            optionCount: optionCount,
            question: question
        )
        sessionManager.send(.approvalOptionResponse(response))
    }

    // MARK: - Inbound

    private func handleMessage(_ message: WatchMessage) {
        guard isActive else { return }
        switch message {
        case .terminalUpdate(let update):
            onTerminalLines?(update.lines)

        case .approvalRequestMessage(let request):
            onApproval?(request)

        case .sessionStateUpdate(let state):
            applySessionState(state)

        case .connectionStatus(let status):
            if status.state == .connected {
                onConnected?()
            } else if status.state == .disconnected {
                onDisconnected?()
            }

        case .sessionsUpdate(let update):
            onSessions?(update.sessions)

        default:
            break
        }
    }

    private func handleContext(_ dictionary: [String: Any]) {
        guard isActive else { return }
        if let message = try? WatchMessage(from: dictionary),
           case .sessionStateUpdate(let state) = message {
            applySessionState(state)
        }
    }

    private func applySessionState(_ state: SessionState) {
        onSessionState?(state)
        if state.relayReady && state.connection == .connected {
            onConnected?()
        } else if state.connection == .disconnected {
            onDisconnected?()
            lastError = "iPhone not connected to Mac bridge"
        }
    }
}