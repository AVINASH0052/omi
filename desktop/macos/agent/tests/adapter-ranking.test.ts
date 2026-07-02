import { describe, expect, it } from "vitest";
import {
  DIRECTED_SELECTABLE_ADAPTER_IDS,
  rankAdapters,
  type TaskDomain,
} from "../src/runtime/adapter-selection.js";

describe("rankAdapters", () => {
  const allConnected = [...DIRECTED_SELECTABLE_ADAPTER_IDS];

  it("returns an empty list when nothing is connected", () => {
    expect(rankAdapters("browser", [], 120)).toEqual([]);
    expect(rankAdapters(undefined, [], 50)).toEqual([]);
  });

  it("ranks a domain match above adapters without that strength", () => {
    expect(rankAdapters("browser", allConnected, 120)).toEqual([
      "openclaw",
      "hermes",
      "acp",
      "codex",
    ]);
  });

  it("prefers codex and acp for repo work with acp winning ties", () => {
    expect(rankAdapters("repo_ops", allConnected, 120)).toEqual([
      "acp",
      "codex",
      "hermes",
      "openclaw",
    ]);
  });

  it("adds a speed bonus for fast adapters on short briefs", () => {
    expect(rankAdapters(undefined, ["hermes", "openclaw"], 80)).toEqual([
      "hermes",
      "openclaw",
    ]);
    expect(rankAdapters(undefined, ["hermes", "openclaw"], 240)).toEqual([
      "openclaw",
      "hermes",
    ]);
  });

  it("keeps stable insertion order among equal scores", () => {
    expect(rankAdapters(undefined, ["codex", "openclaw", "hermes"], 240)).toEqual([
      "codex",
      "openclaw",
      "hermes",
    ]);
  });

  it("excludes pi-mono from directed ranking", () => {
    const ranked = rankAdapters("research" as TaskDomain, ["pi-mono", "hermes", "acp"], 120);
    expect(ranked).toEqual(["hermes", "acp"]);
    expect(ranked).not.toContain("pi-mono");
  });
});
