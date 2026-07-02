import type { OutboundMessage } from "../protocol.js";
import type { RuntimeFailure } from "./failures.js";

/** Outbound event types that count as meaningful agent output for reroute gating. */
export const MEANINGFUL_OUTPUT_EVENT_TYPES = new Set<OutboundMessage["type"]>([
  "text_delta",
  "tool_use",
  "tool_activity",
  "tool_result_display",
]);

export function isMeaningfulAdapterOutput(event: OutboundMessage): boolean {
  return MEANINGFUL_OUTPUT_EVENT_TYPES.has(event.type);
}

export function buildAdapterChain(
  primaryAdapterId: string,
  fallbackAdapterIds: readonly string[] = []
): string[] {
  const chain: string[] = [];
  const seen = new Set<string>();
  for (const adapterId of [primaryAdapterId, ...fallbackAdapterIds]) {
    if (!adapterId || seen.has(adapterId)) {
      continue;
    }
    seen.add(adapterId);
    chain.push(adapterId);
  }
  return chain;
}

export function nextAdapterInChain(
  adapterChain: readonly string[],
  triedAdapterIds: ReadonlySet<string>
): string | null {
  for (const adapterId of adapterChain) {
    if (!triedAdapterIds.has(adapterId)) {
      return adapterId;
    }
  }
  return null;
}

export interface ShouldRerouteAdapterInput {
  failure: RuntimeFailure;
  meaningfulOutputProduced: boolean;
  triedAdapterIds: ReadonlySet<string>;
  adapterChain: readonly string[];
}

export interface ShouldRerouteAdapterResult {
  reroute: boolean;
  nextAdapterId: string | null;
}

export function shouldRerouteAdapter(input: ShouldRerouteAdapterInput): ShouldRerouteAdapterResult {
  const { failure, meaningfulOutputProduced, triedAdapterIds, adapterChain } = input;
  const nextAdapterId = nextAdapterInChain(adapterChain, triedAdapterIds);

  if (!nextAdapterId || triedAdapterIds.size >= adapterChain.length) {
    return { reroute: false, nextAdapterId: null };
  }

  const source = failure.source ?? "runtime";

  if (source === "adapter_process") {
    return { reroute: true, nextAdapterId };
  }

  if (source === "adapter_execution" && meaningfulOutputProduced) {
    return { reroute: false, nextAdapterId: null };
  }

  if (failure.retryable && !meaningfulOutputProduced) {
    return { reroute: true, nextAdapterId };
  }

  return { reroute: false, nextAdapterId: null };
}

export function adapterFallbackStatusLabel(adapterId: string): string {
  switch (adapterId) {
    case "acp":
      return "Claude Code";
    case "codex":
      return "Codex";
    case "openclaw":
      return "OpenClaw";
    case "hermes":
      return "Hermes";
    case "pi-mono":
      return "Omi AI";
    default:
      return adapterId;
  }
}

export function formatFallbackStatusLine(fromAdapterId: string, toAdapterId: string): string {
  return `${adapterFallbackStatusLabel(fromAdapterId)} unavailable, trying ${adapterFallbackStatusLabel(toAdapterId)}`;
}

/** Prefix for pill status lines sent through the existing tool_activity channel. */
export const OMI_STATUS_TOOL_ACTIVITY_PREFIX = "__omi_status:";

export function omiStatusToolActivityName(statusText: string): string {
  return `${OMI_STATUS_TOOL_ACTIVITY_PREFIX}${statusText}`;
}
