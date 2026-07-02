import Foundation

enum AgentTaskDomain: String, CaseIterable, Equatable {
  case coding
  case repoOps = "repo_ops"
  case browser
  case messaging
  case files
  case research
  case system

  static func parse(_ rawValue: String?) -> AgentTaskDomain? {
    let normalized = rawValue?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    guard !normalized.isEmpty else { return nil }
    return AgentTaskDomain(rawValue: normalized)
  }
}

struct AgentSelection: Equatable {
  let primaryHarness: AgentHarnessMode
  let fallbackChain: [AgentHarnessMode]
}

enum AgentSelector {
  private static let directedRankableAdapterIds = ["acp", "codex", "openclaw", "hermes"]

  // Keep in lockstep with rankAdapters() in desktop/macos/agent/src/runtime/adapter-selection.ts.
  static func rankAdapters(
    domain: AgentTaskDomain?,
    connected: [String],
    briefLength: Int
  ) -> [String] {
    let candidates = connected.filter { directedRankableAdapterIds.contains($0) }
    let scored = candidates.map { adapterId -> (adapterId: String, score: Int, order: Int) in
      let tags = capabilityTags(for: adapterId)
      var score = 0
      if let domain, tags.strengths.contains(domain) {
        score += 2
      }
      if tags.speedTier == .fast, briefLength < 200 {
        score += 1
      }
      let order = directedRankableAdapterIds.firstIndex(of: adapterId) ?? Int.max
      return (adapterId, score, order)
    }

    return scored.sorted { left, right in
      if left.score != right.score {
        return left.score > right.score
      }
      if left.adapterId == "acp", right.adapterId != "acp" {
        return true
      }
      if right.adapterId == "acp", left.adapterId != "acp" {
        return false
      }
      return left.order < right.order
    }.map(\.adapterId)
  }

  static func select(taskDomain: AgentTaskDomain?, briefLength: Int) -> AgentSelection {
    let harnessChain = availableHarnessChain(taskDomain: taskDomain, briefLength: briefLength)
    let primary = harnessChain.first ?? .acp
    return AgentSelection(
      primaryHarness: primary,
      fallbackChain: Array(harnessChain.dropFirst())
    )
  }

  static func availableHarnessChain(taskDomain: AgentTaskDomain?, briefLength: Int) -> [AgentHarnessMode] {
    rankAdapters(
      domain: taskDomain,
      connected: connectedSelectableAdapterIds(),
      briefLength: briefLength
    ).compactMap { adapterId in
      guard let harness = harnessMode(forSelectableAdapterId: adapterId) else { return nil }
      return isAvailable(harness: harness) ? harness : nil
    }
  }

  static func isAvailable(harness: AgentHarnessMode) -> Bool {
    switch harness {
    case .acp:
      return true
    case .hermes:
      return LocalAgentProviderDetector.isAvailable(.hermes)
    case .openclaw:
      return LocalAgentProviderDetector.isAvailable(.openclaw)
    case .codex:
      return LocalAgentProviderDetector.isAvailable(.codex)
    default:
      return false
    }
  }

  static func connectedSelectableAdapterIds() -> [String] {
    var connected = ["acp"]
    for provider in AgentPillsManager.DirectedProvider.allCases {
      if LocalAgentProviderDetector.isAvailable(provider) {
        connected.append(provider.rawValue)
      }
    }
    return connected
  }

  static func harnessMode(forSelectableAdapterId adapterId: String) -> AgentHarnessMode? {
    switch adapterId {
    case "acp":
      return .acp
    case "hermes":
      return .hermes
    case "openclaw":
      return .openclaw
    case "codex":
      return .codex
    default:
      return nil
    }
  }

  static func directedProvider(for harness: AgentHarnessMode) -> AgentPillsManager.DirectedProvider? {
    switch harness {
    case .hermes:
      return .hermes
    case .openclaw:
      return .openclaw
    case .codex:
      return .codex
    default:
      return nil
    }
  }

  static func displayName(
    for harness: AgentHarnessMode?,
    directedProvider: AgentPillsManager.DirectedProvider?
  ) -> String? {
    if let directedProvider {
      return directedProvider.displayName
    }
    switch harness {
    case .acp:
      return "Claude Code"
    case .hermes:
      return "Hermes"
    case .openclaw:
      return "OpenClaw"
    case .codex:
      return "Codex"
    default:
      return nil
    }
  }

  private enum SpeedTier {
    case fast
    case standard
  }

  private struct CapabilityTags {
    let strengths: [AgentTaskDomain]
    let speedTier: SpeedTier
  }

  private static func capabilityTags(for adapterId: String) -> CapabilityTags {
    switch adapterId {
    case "acp":
      return CapabilityTags(
        strengths: [.coding, .repoOps, .files, .research],
        speedTier: .standard
      )
    case "codex":
      return CapabilityTags(
        strengths: [.coding, .repoOps],
        speedTier: .standard
      )
    case "openclaw":
      return CapabilityTags(
        strengths: [.browser, .messaging, .system, .research],
        speedTier: .standard
      )
    case "hermes":
      return CapabilityTags(
        strengths: [.coding, .system, .research],
        speedTier: .fast
      )
    default:
      return CapabilityTags(strengths: [], speedTier: .standard)
    }
  }
}
