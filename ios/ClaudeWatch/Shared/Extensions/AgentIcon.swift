import SwiftUI

struct AgentIcon: View {
    let agent: AgentType
    var size: CGFloat = 14

    var body: some View {
        switch agent {
        case .claude:
            ClaudeMascot(size: size)
        case .codex:
            CodexLogo(size: size)
        case .pi:
            Text("π")
                .font(.system(size: size * 0.75, weight: .bold, design: .rounded))
                .foregroundStyle(Color.claudeOrange)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        AgentIcon(agent: .claude, size: 24)
        AgentIcon(agent: .codex, size: 24)
        AgentIcon(agent: .claude, size: 32)
        AgentIcon(agent: .codex, size: 32)
    }
    .padding()
    .background(Color.black)
}
