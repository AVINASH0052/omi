import Foundation

@MainActor
final class AgentInstallCoordinator {
  static let shared = AgentInstallCoordinator()

  struct HeldAgentRequest: Equatable {
    let provider: AgentPillsManager.DirectedProvider
    let brief: String
    let title: String?
    let model: String
    let fromVoice: Bool
    let bridgeHarnessOverride: AgentHarnessMode
    let fallbackChain: [AgentHarnessMode]
  }

  private struct PendingOffer {
    let request: HeldAgentRequest
    let pillID: UUID
  }

  private(set) var pending: PendingOffer?
  private var installTask: Task<Void, Never>?

  private init() {}

  func beginOffer(request: HeldAgentRequest) -> AgentPill {
    installTask?.cancel()
    let pill = AgentPillsManager.shared.spawnInstallOffer(
      request: request,
      consentPrompt: AgentInstallCatalog.consentPrompt(for: request.provider)
    )
    pending = PendingOffer(request: request, pillID: pill.id)
    managerHoverInstallPill(pill)
    return pill
  }

  func declineInstall() {
    guard let pending else { return }
    if let pill = AgentPillsManager.shared.pill(id: pending.pillID) {
      pill.status = .stopped
      pill.latestActivity = "Install cancelled"
      pill.awaitingInstallConfirmation = false
      pill.markContentChanged()
    }
    clearPending()
  }

  func confirmInstall(pillID: UUID? = nil) {
    guard let pending else { return }
    if let pillID, pillID != pending.pillID { return }
    guard installTask == nil else { return }

    guard let command = AgentInstallCatalog.installCommand(for: pending.request.provider) else {
      failInstall(message: "Install is not available for this provider.")
      return
    }

    guard let pill = AgentPillsManager.shared.pill(id: pending.pillID) else {
      clearPending()
      return
    }

    pill.awaitingInstallConfirmation = false
    pill.status = .running
    pill.latestActivity = "Installing \(pending.request.provider.displayName)…"
    pill.markContentChanged()

    let heldRequest = pending.request
    let targetPillID = pending.pillID
    installTask = Task { [weak self] in
      guard let self else { return }
      let result = await AgentProviderInstaller.run(command: command) { line in
        guard let pill = AgentPillsManager.shared.pill(id: targetPillID) else { return }
        pill.latestActivity = String(line.prefix(140))
        pill.markContentChanged()
      }

      guard !Task.isCancelled else { return }
      self.installTask = nil

      if result.succeeded {
        await self.resumeAfterInstall(request: heldRequest, pillID: targetPillID)
      } else {
        let tail = result.stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = tail.isEmpty
          ? "Install failed (exit \(result.exitCode))."
          : String(tail.suffix(280))
        self.failInstall(message: message, pillID: targetPillID)
      }
    }
  }

  func tryHandleUserResponse(_ text: String, fromVoice: Bool = false) async -> Bool {
    guard pending != nil else { return false }
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return false }

    if matchesDecline(normalized) {
      declineInstall()
      if fromVoice {
        FloatingBarVoicePlaybackService.shared.speakOneShot("Okay, I won't install it.")
      }
      return true
    }

    if matchesConfirmation(normalized) {
      confirmInstall()
      if fromVoice {
        FloatingBarVoicePlaybackService.shared.speakOneShot("Installing now.")
      }
      return true
    }

    return false
  }

  func handlePostInstallAuthFailure(message: String, provider: AgentPillsManager.DirectedProvider, pill: AgentPill) {
    guard AgentInstallCatalog.isLikelyAuthFailure(message, provider: provider) else { return }
    let instruction = AgentInstallCatalog.authSetupInstruction(for: provider)
    pill.status = .failed(instruction)
    pill.latestActivity = instruction
    pill.completedAt = Date()
    pill.markContentChanged()
  }

  private func resumeAfterInstall(request: HeldAgentRequest, pillID: UUID) async {
    guard LocalAgentProviderDetector.isAvailable(request.provider) else {
      failInstall(message: "\(request.provider.displayName) installed but is still not detected.", pillID: pillID)
      return
    }

    clearPending()
    guard let pill = AgentPillsManager.shared.pill(id: pillID) else { return }
    pill.latestActivity = "Install complete. Starting agent…"
    pill.markContentChanged()
    await AgentPillsManager.shared.executeHeldAgent(request: request, on: pill)
  }

  private func failInstall(message: String, pillID: UUID? = nil) {
    let targetID = pillID ?? pending?.pillID
    if let targetID, let pill = AgentPillsManager.shared.pill(id: targetID) {
      pill.awaitingInstallConfirmation = false
      pill.status = .failed(message)
      pill.latestActivity = message
      pill.completedAt = Date()
      pill.markContentChanged()
    }
    clearPending()
  }

  private func clearPending() {
    installTask?.cancel()
    installTask = nil
    pending = nil
  }

  private func managerHoverInstallPill(_ pill: AgentPill) {
    AgentPillsManager.shared.hoveredPillID = pill.id
  }

  private func matchesConfirmation(_ normalized: String) -> Bool {
    let tokens = ["yes", "yeah", "yep", "sure", "install", "go ahead", "please", "ok", "okay", "do it", "confirm"]
    return tokens.contains(where: { normalized == $0 || normalized.hasPrefix("\($0) ") || normalized.contains(" \($0)") })
  }

  private func matchesDecline(_ normalized: String) -> Bool {
    let tokens = ["no", "nope", "cancel", "don't", "do not", "never mind", "nevermind", "stop"]
    return tokens.contains(where: { normalized == $0 || normalized.hasPrefix("\($0) ") || normalized.contains(" \($0)") })
  }
}
