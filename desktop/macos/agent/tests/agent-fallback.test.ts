import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { AdapterRuntimeError } from "../src/runtime/failures.js";
import { AdapterRegistry } from "../src/runtime/adapter-registry.js";
import { AgentRuntimeKernel } from "../src/runtime/kernel.js";
import { SqliteAgentStore } from "../src/runtime/sqlite-store.js";
import { baseRunInput, FakeRuntimeAdapter } from "./kernel-fakes.js";

const createdDirs: string[] = [];

afterEach(() => {
  for (const dir of createdDirs.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
  }
});

describe("AgentRuntimeKernel adapter fallback", () => {
  it("reroutes across the adapter chain after a process failure and completes on the fallback", async () => {
    const { store, primary, fallback, kernel } = createDualAdapterHarness();
    primary.failNextOpenError = new AdapterRuntimeError({
      code: "adapter_process_exited",
      source: "adapter_process",
      adapterId: "codex",
      retryable: true,
      userMessage: "Codex failed: process exited",
    });

    const result = await kernel.executeRun({
      ...baseRunInput,
      adapterId: "codex",
      fallbackAdapterIds: ["acp"],
      defaultAdapterId: "codex",
    });

    expect(result.terminalStatus).toBe("succeeded");
    expect(primary.opened).toHaveLength(1);
    expect(fallback.opened).toHaveLength(1);
    expect(primary.executed).toHaveLength(0);
    expect(fallback.executed).toHaveLength(1);
    expect(store.allRows("SELECT adapter_id, attempt_no, status FROM run_attempts ORDER BY attempt_no")).toEqual([
      expect.objectContaining({ adapter_id: "codex", attempt_no: 1, status: "failed" }),
      expect.objectContaining({ adapter_id: "acp", attempt_no: 2, status: "succeeded" }),
    ]);
    expect(
      store.allRows("SELECT type, payload_json FROM events WHERE type = 'run.fallback_reroute'").map((row) =>
        JSON.parse(String(row.payload_json))
      )
    ).toEqual([
      expect.objectContaining({
        statusText: "Codex unavailable, trying Claude Code",
        fromAdapterId: "codex",
        toAdapterId: "acp",
      }),
    ]);
    store.close();
  });

  it("does not reroute after meaningful output on adapter_execution failures", async () => {
    const { store, primary, fallback, kernel } = createDualAdapterHarness();
    primary.failNextExecutionError = new AdapterRuntimeError({
      code: "adapter_execution_failed",
      source: "adapter_execution",
      adapterId: "codex",
      retryable: true,
      userMessage: "Codex produced a wrong answer",
    });

    const result = await kernel.executeRun({
      ...baseRunInput,
      adapterId: "codex",
      fallbackAdapterIds: ["acp"],
      defaultAdapterId: "codex",
      maxAttempts: 1,
    });

    expect(result.terminalStatus).toBe("failed");
    expect(result.run.errorMessage).toBe("Codex produced a wrong answer");
    expect(primary.executed).toHaveLength(1);
    expect(fallback.executed).toHaveLength(0);
    expect(store.allRows("SELECT type FROM events WHERE type = 'run.fallback_reroute'")).toHaveLength(0);
    store.close();
  });

  it("surfaces the last failure when the adapter chain is exhausted", async () => {
    const { store, primary, fallback, kernel } = createDualAdapterHarness();
    primary.failNextOpenError = new AdapterRuntimeError({
      code: "adapter_process_exited",
      source: "adapter_process",
      adapterId: "codex",
      retryable: true,
      userMessage: "Codex failed: process exited",
    });
    fallback.failNextOpenError = new AdapterRuntimeError({
      code: "adapter_process_exited",
      source: "adapter_process",
      adapterId: "acp",
      retryable: true,
      userMessage: "Claude Code failed: process exited",
    });

    const result = await kernel.executeRun({
      ...baseRunInput,
      adapterId: "codex",
      fallbackAdapterIds: ["acp"],
      defaultAdapterId: "codex",
    });

    expect(result.terminalStatus).toBe("failed");
    expect(result.run.errorMessage).toBe("Claude Code failed: process exited");
    expect(store.allRows("SELECT adapter_id, status FROM run_attempts ORDER BY attempt_no")).toEqual([
      expect.objectContaining({ adapter_id: "codex", status: "failed" }),
      expect.objectContaining({ adapter_id: "acp", status: "failed" }),
    ]);
    store.close();
  });
});

function createDualAdapterHarness() {
  const databasePath = newDatabasePath();
  const store = new SqliteAgentStore({ databasePath, reconcileOnOpen: false });
  const primary = new FakeRuntimeAdapter("codex");
  const fallback = new FakeRuntimeAdapter("acp");
  const registry = new AdapterRegistry();
  registry.register("codex", () => primary, 2);
  registry.register("acp", () => fallback, 2);
  const kernel = new AgentRuntimeKernel({ store, registry });
  return { store, primary, fallback, kernel };
}

function newDatabasePath(): string {
  const dir = mkdtempSync(join(tmpdir(), "omi-agent-fallback-"));
  createdDirs.push(dir);
  return join(dir, "omi-agentd.sqlite3");
}
