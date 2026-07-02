import { describe, expect, it } from "vitest";
import {
  buildAdapterChain,
  formatFallbackStatusLine,
  isMeaningfulAdapterOutput,
  nextAdapterInChain,
  shouldRerouteAdapter,
} from "../src/runtime/fallback-policy.js";
import type { RuntimeFailure } from "../src/runtime/failures.js";

function failure(overrides: Partial<RuntimeFailure> = {}): RuntimeFailure {
  return {
    code: "test_failure",
    userMessage: "Agent failed",
    source: "adapter_process",
    adapterId: "codex",
    retryable: true,
    ...overrides,
  };
}

describe("fallback-policy", () => {
  it("buildAdapterChain deduplicates while preserving order", () => {
    expect(buildAdapterChain("codex", ["acp", "codex", "hermes"])).toEqual(["codex", "acp", "hermes"]);
  });

  it("treats assistant text and tool events as meaningful output", () => {
    expect(isMeaningfulAdapterOutput({ type: "text_delta", text: "hi" })).toBe(true);
    expect(isMeaningfulAdapterOutput({ type: "tool_use", callId: "1", name: "Read", input: {} })).toBe(true);
    expect(isMeaningfulAdapterOutput({ type: "tool_activity", name: "Read", status: "started" })).toBe(true);
    expect(isMeaningfulAdapterOutput({ type: "tool_result_display", toolUseId: "1", name: "Read", output: "ok" })).toBe(true);
    expect(isMeaningfulAdapterOutput({ type: "thinking_delta", text: "hmm" })).toBe(false);
    expect(isMeaningfulAdapterOutput({ type: "error", message: "boom" })).toBe(false);
  });

  it("reroutes on adapter_process failures", () => {
    const chain = ["codex", "acp", "hermes"];
    const tried = new Set(["codex"]);
    expect(
      shouldRerouteAdapter({
        failure: failure({ source: "adapter_process" }),
        meaningfulOutputProduced: false,
        triedAdapterIds: tried,
        adapterChain: chain,
      })
    ).toEqual({ reroute: true, nextAdapterId: "acp" });
  });

  it("reroutes on retryable failures before meaningful output", () => {
    expect(
      shouldRerouteAdapter({
        failure: failure({ source: "adapter_execution", retryable: true }),
        meaningfulOutputProduced: false,
        triedAdapterIds: new Set(["codex"]),
        adapterChain: ["codex", "acp"],
      })
    ).toEqual({ reroute: true, nextAdapterId: "acp" });
  });

  it("blocks reroute after meaningful output on adapter_execution failures", () => {
    expect(
      shouldRerouteAdapter({
        failure: failure({ source: "adapter_execution", retryable: true }),
        meaningfulOutputProduced: true,
        triedAdapterIds: new Set(["codex"]),
        adapterChain: ["codex", "acp"],
      })
    ).toEqual({ reroute: false, nextAdapterId: null });
  });

  it("does not reroute non-retryable adapter_execution failures without process death", () => {
    expect(
      shouldRerouteAdapter({
        failure: failure({ source: "adapter_execution", retryable: false }),
        meaningfulOutputProduced: false,
        triedAdapterIds: new Set(["codex"]),
        adapterChain: ["codex", "acp"],
      })
    ).toEqual({ reroute: false, nextAdapterId: null });
  });

  it("exhausts the chain without revisiting adapters", () => {
    const chain = ["codex", "acp"];
    expect(nextAdapterInChain(chain, new Set(["codex"]))).toBe("acp");
    expect(nextAdapterInChain(chain, new Set(["codex", "acp"]))).toBeNull();
    expect(
      shouldRerouteAdapter({
        failure: failure({ source: "adapter_process" }),
        meaningfulOutputProduced: false,
        triedAdapterIds: new Set(["codex", "acp"]),
        adapterChain: chain,
      })
    ).toEqual({ reroute: false, nextAdapterId: null });
  });

  it("formats fallback status lines for the pill", () => {
    expect(formatFallbackStatusLine("codex", "acp")).toBe("Codex unavailable, trying Claude Code");
  });
});
