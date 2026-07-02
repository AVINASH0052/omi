import XCTest
@testable import Omi

final class AgentInstallCatalogTests: XCTestCase {
  func testInstallCommandAllowlist() {
    XCTAssertEqual(
      AgentInstallCatalog.installCommand(for: .hermes),
      "curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"
    )
    XCTAssertEqual(
      AgentInstallCatalog.installCommand(for: .openclaw),
      "npm install -g openclaw@latest"
    )
    XCTAssertEqual(
      AgentInstallCatalog.installCommand(for: .codex),
      "npm install -g @zed-industries/codex-acp"
    )
  }

  func testConsentPrompt() {
    XCTAssertEqual(
      AgentInstallCatalog.consentPrompt(for: .hermes),
      "Hermes isn't installed. Want me to install it?"
    )
  }

  func testPostInstallRedetectionUsesInjectedHomeDirectory() throws {
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("omi-install-redetect-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }

    XCTAssertFalse(
      LocalAgentProviderDetector.isAvailable(
        .hermes,
        environment: [:],
        fileManager: .default,
        homeDirectory: home.path
      )
    )

    let bin = home.appendingPathComponent(".local/bin", isDirectory: true)
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let hermes = bin.appendingPathComponent("hermes")
    try "#!/bin/sh\nexit 0\n".write(to: hermes, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hermes.path)

    XCTAssertTrue(
      LocalAgentProviderDetector.isAvailable(
        .hermes,
        environment: [:],
        fileManager: .default,
        homeDirectory: home.path
      )
    )
  }
}
