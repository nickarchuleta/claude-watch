import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var session: WatchViewState
    @StateObject private var bridge = WatchBridgeClient.shared

    @State private var code = ""
    @State private var ipAddress = ""
    @State private var isSearching = false
    @State private var isConnecting = false
    @State private var error: String?
    @State private var bridgeURL: URL?
    @State private var showDirectSetup = false
    @FocusState private var codeFocused: Bool
    @FocusState private var ipFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                AppLogo(size: 22)
                Text("Agent Watch")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.Text.primary)
            }

            if !showDirectSetup {
                relaySection
            } else if isSearching {
                Spacer()
                ProgressView().tint(Theme.Text.secondary)
                Text("Searching LAN…")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Text.secondary)
                Spacer()
            } else if bridgeURL != nil {
                directCodeSection
            } else {
                directManualSection
            }

            if let error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.Accent.error)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Background.primary)
    }

    // MARK: - Via iPhone (recommended — no same WiFi)

    private var relaySection: some View {
        VStack(spacing: 8) {
            Text("Pair iPhone to Mac first")
                .font(.system(size: 11))
                .foregroundColor(Theme.Text.secondary)
                .multilineTextAlignment(.center)

            Text("Watch relays through iPhone — works on cellular, coffee-shop WiFi, anywhere.")
                .font(.system(size: 9))
                .foregroundColor(Theme.Text.dimmed)
                .multilineTextAlignment(.center)

            Button {
                session.connectViaIPhone()
            } label: {
                Text("Connect via iPhone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Theme.Text.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if session.connectionMode == .iphoneRelay && !session.isPaired {
                ProgressView().scaleEffect(0.7)
                Text("Waiting for iPhone…")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.Text.secondary)
            }

            Button {
                showDirectSetup = true
                searchForBridge()
            } label: {
                Text("Direct to Mac (LAN)")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.Text.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Direct LAN pairing

    private var directCodeSection: some View {
        VStack(spacing: 6) {
            Text("Enter code from Mac")
                .font(.system(size: 11))
                .foregroundColor(Theme.Text.secondary)

            TextField("000000", text: $code)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.Text.primary)
                .multilineTextAlignment(.center)
                .textContentType(.oneTimeCode)
                .focused($codeFocused)
                .onChange(of: code) { _, newValue in
                    let filtered = String(newValue.filter { $0.isNumber }.prefix(6))
                    if filtered != newValue { code = filtered }
                    if filtered.count == 6 { submitCode(filtered) }
                }

            if isConnecting {
                ProgressView().tint(Theme.Text.primary).scaleEffect(0.7)
            }

            Button { showDirectSetup = false } label: {
                Text("← Via iPhone")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.Text.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var directManualSection: some View {
        VStack(spacing: 6) {
            Text("Mac IP or Tailscale host")
                .font(.system(size: 11))
                .foregroundColor(Theme.Text.secondary)

            TextField("192.168.1.x", text: $ipAddress)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.Text.primary)
                .multilineTextAlignment(.center)
                .focused($ipFocused)

            Button { connectManual() } label: {
                Text("Connect")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Theme.Text.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(ipAddress.isEmpty)

            Button("Retry auto") { searchForBridge() }
                .font(.system(size: 10))
                .foregroundColor(Theme.Text.secondary)
        }
    }

    private func connectManual() {
        let host = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        session.connectDirectToMac()
        isSearching = true
        error = nil

        Task {
            if let parsed = BridgeURLParser.parse(host) {
                let statusURL = BridgeURLParser.statusURL(for: parsed.baseURL)
                var request = URLRequest(url: statusURL)
                request.timeoutInterval = 10
                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        await MainActor.run {
                            isSearching = false
                            bridgeURL = parsed.baseURL
                            codeFocused = true
                        }
                        return
                    }
                } catch { /* fall through */ }
            }

            for port in 7860...7869 {
                let url = URL(string: "http://\(host):\(port)/status")!
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        await MainActor.run {
                            isSearching = false
                            bridgeURL = URL(string: "http://\(host):\(port)")
                            codeFocused = true
                        }
                        return
                    }
                } catch { continue }
            }
            await MainActor.run {
                isSearching = false
                self.error = "Can't reach \(host)"
            }
        }
    }

    private func searchForBridge() {
        session.connectDirectToMac()
        isSearching = true
        error = nil
        Task {
            let url = await bridge.discover()
            await MainActor.run {
                isSearching = false
                bridgeURL = url
                if url != nil { codeFocused = true }
                else { ipFocused = true }
            }
        }
    }

    private func submitCode(_ code: String) {
        guard let url = bridgeURL, !isConnecting else { return }
        isConnecting = true
        error = nil

        Task {
            do {
                try await bridge.pair(baseURL: url, code: code)
                await MainActor.run {
                    session.connectionMode = .direct
                    UserDefaults.standard.set(WatchConnectionMode.direct.rawValue, forKey: "watch_connection_mode")
                    session.isPaired = true
                    session.sessionState = SessionState(
                        connection: .connected, activity: .idle,
                        machineName: "Mac", modelName: nil,
                        workingDirectory: nil,
                        elapsedSeconds: 0, filesChanged: 0, linesAdded: 0,
                        transportMode: .lan,
                        iphoneRelayAvailable: false
                    )
                    session.appendLine(TerminalLine(text: "Connected to bridge", type: .system))
                    session.startEventStream()
                }
            } catch {
                await MainActor.run {
                    self.isConnecting = false
                    self.error = error.localizedDescription
                    self.code = ""
                }
            }
        }
    }
}

#Preview { OnboardingView().environmentObject(WatchViewState.shared) }