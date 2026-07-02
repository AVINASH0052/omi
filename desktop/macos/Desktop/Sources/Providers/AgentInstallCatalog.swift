import Foundation

/// Allowlisted install commands for directed local agents.
/// Keep in lockstep with capabilityTags.installCommand in desktop/macos/agent/src/runtime/adapter-selection.ts.
enum AgentInstallCatalog {
  static func installCommand(for provider: AgentPillsManager.DirectedProvider) -> String? {
    switch provider {
    case .hermes:
      return "curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"
    case .openclaw:
      return "npm install -g openclaw@latest"
    case .codex:
      return "npm install -g @zed-industries/codex-acp"
    }
  }

  static func consentPrompt(for provider: AgentPillsManager.DirectedProvider) -> String {
    "\(provider.displayName) isn't installed. Want me to install it?"
  }

  static func authSetupInstruction(for provider: AgentPillsManager.DirectedProvider) -> String {
    switch provider {
    case .codex:
      return "Run codex login in your terminal, then retry."
    case .openclaw:
      return "Run openclaw onboard in your terminal, then retry."
    case .hermes:
      return "Run hermes model in your terminal, then retry."
    }
  }

  static func isLikelyAuthFailure(_ message: String, provider: AgentPillsManager.DirectedProvider) -> Bool {
    let lower = message.lowercased()
    if lower.contains("auth") || lower.contains("api key") || lower.contains("unauthorized") {
      return true
    }
    switch provider {
    case .codex:
      return lower.contains("login") || lower.contains("not signed in")
    case .openclaw:
      return lower.contains("onboard") || lower.contains("config")
    case .hermes:
      return lower.contains("model") || lower.contains("setup")
    }
  }
}
