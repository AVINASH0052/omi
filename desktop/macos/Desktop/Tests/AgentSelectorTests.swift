import XCTest

@testable import Omi_Computer

final class AgentSelectorTests: XCTestCase {
  func testRankAdaptersPrefersBrowserMatchForOpenClaw() {
    let ranked = AgentSelector.rankAdapters(
      domain: .browser,
      connected: ["acp", "codex", "openclaw", "hermes"],
      briefLength: 120
    )

    XCTAssertEqual(ranked.first, "openclaw")
  }

  func testRankAdaptersPrefersAcpOnRepoOpsTies() {
    let ranked = AgentSelector.rankAdapters(
      domain: .repoOps,
      connected: ["acp", "codex", "openclaw", "hermes"],
      briefLength: 120
    )

    XCTAssertEqual(ranked.prefix(2).map { $0 }, ["acp", "codex"])
  }

  func testRankAdaptersAddsSpeedBonusForShortBriefs() {
    let ranked = AgentSelector.rankAdapters(
      domain: nil,
      connected: ["hermes", "openclaw"],
      briefLength: 80
    )

    XCTAssertEqual(ranked, ["hermes", "openclaw"])
  }

  func testRankAdaptersReturnsEmptyForNoConnectedAgents() {
    XCTAssertTrue(AgentSelector.rankAdapters(domain: .browser, connected: [], briefLength: 50).isEmpty)
  }

  func testTaskDomainParserAcceptsKnownValues() {
    XCTAssertEqual(AgentTaskDomain.parse("repo_ops"), .repoOps)
    XCTAssertEqual(AgentTaskDomain.parse(" browser "), .browser)
    XCTAssertNil(AgentTaskDomain.parse(""))
    XCTAssertNil(AgentTaskDomain.parse("unknown"))
  }
}
