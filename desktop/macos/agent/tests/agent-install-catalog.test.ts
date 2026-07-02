import { describe, expect, it } from "vitest";
import { installCommandForDirectedAdapter } from "../src/runtime/adapter-selection.js";

describe("installCommandForDirectedAdapter", () => {
  it("returns allowlisted install commands for directed adapters", () => {
    expect(installCommandForDirectedAdapter("hermes")).toBe(
      "curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"
    );
    expect(installCommandForDirectedAdapter("openclaw")).toBe("npm install -g openclaw@latest");
    expect(installCommandForDirectedAdapter("codex")).toBe("npm install -g @zed-industries/codex-acp");
  });

  it("returns null for adapters outside the directed install table", () => {
    expect(installCommandForDirectedAdapter("acp")).toBeNull();
    expect(installCommandForDirectedAdapter("pi-mono")).toBeNull();
    expect(installCommandForDirectedAdapter("unknown")).toBeNull();
  });
});
