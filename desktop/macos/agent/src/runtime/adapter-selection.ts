import { AcpRuntimeAdapter } from "../adapters/acp.js";
import { CodexRuntimeAdapter } from "../adapters/codex.js";
import { HermesRuntimeAdapter } from "../adapters/hermes.js";
import { OpenClawRuntimeAdapter } from "../adapters/openclaw.js";
import { adapterCapabilitiesFor, type AdapterCapabilities, type ProductionAdapterId, type RuntimeAdapter } from "../adapters/interface.js";
import type { AdapterRegistry } from "./adapter-registry.js";

export const ADAPTER_ACTIVATION_ENV = {
  acp: undefined,
  "pi-mono": "OMI_AUTH_TOKEN",
  hermes: "OMI_HERMES_ADAPTER_COMMAND",
  openclaw: "OMI_OPENCLAW_ADAPTER_COMMAND",
  codex: "OMI_CODEX_ADAPTER_COMMAND",
} as const;

export type SelectableAdapterId = keyof typeof ADAPTER_ACTIVATION_ENV;

export type TaskDomain =
  | "coding"
  | "repo_ops"
  | "browser"
  | "messaging"
  | "files"
  | "research"
  | "system";

export type AdapterSpeedTier = "fast" | "standard";

export interface AdapterCapabilityTags {
  strengths: TaskDomain[];
  speedTier: AdapterSpeedTier;
  requiresAuth: string;
  installCommand: string;
  installCheckBinary: string;
}

export interface AdapterProfile {
  adapterId: ProductionAdapterId;
  activationEnv?: string;
  maxWorkers: number;
  capabilities: AdapterCapabilities;
  capabilityTags: AdapterCapabilityTags;
  createAdapter: (options: { log: (message: string) => void }) => RuntimeAdapter;
}

export const DIRECTED_SELECTABLE_ADAPTER_IDS = ["acp", "codex", "openclaw", "hermes"] as const;
export type DirectedSelectableAdapterId = typeof DIRECTED_SELECTABLE_ADAPTER_IDS[number];

const DIRECTED_SELECTABLE_INSERTION_ORDER: readonly DirectedSelectableAdapterId[] = DIRECTED_SELECTABLE_ADAPTER_IDS;

export const ADAPTER_PROFILES: Record<ProductionAdapterId, AdapterProfile> = {
  acp: {
    adapterId: "acp",
    activationEnv: ADAPTER_ACTIVATION_ENV.acp,
    maxWorkers: 1,
    capabilities: adapterCapabilitiesFor("acp"),
    capabilityTags: {
      strengths: ["coding", "repo_ops", "files", "research"],
      speedTier: "standard",
      requiresAuth: "Claude Code sign in",
      installCommand: "",
      installCheckBinary: "claude",
    },
    createAdapter: () => new AcpRuntimeAdapter(),
  },
  "pi-mono": {
    adapterId: "pi-mono",
    activationEnv: ADAPTER_ACTIVATION_ENV["pi-mono"],
    maxWorkers: 1,
    capabilities: adapterCapabilitiesFor("pi-mono"),
    capabilityTags: {
      strengths: [],
      speedTier: "standard",
      requiresAuth: "Omi sign in",
      installCommand: "",
      installCheckBinary: "",
    },
    createAdapter: () => {
      throw new Error("pi-mono adapter requires authenticated PiMonoAdapter construction");
    },
  },
  hermes: {
    adapterId: "hermes",
    activationEnv: ADAPTER_ACTIVATION_ENV.hermes,
    maxWorkers: 1,
    capabilities: adapterCapabilitiesFor("hermes"),
    capabilityTags: {
      strengths: ["coding", "system", "research"],
      speedTier: "fast",
      requiresAuth: "model API key via hermes setup",
      installCommand: "curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash",
      installCheckBinary: "hermes",
    },
    createAdapter: ({ log }) => new HermesRuntimeAdapter({ log }),
  },
  openclaw: {
    adapterId: "openclaw",
    activationEnv: ADAPTER_ACTIVATION_ENV.openclaw,
    maxWorkers: 1,
    capabilities: adapterCapabilitiesFor("openclaw"),
    capabilityTags: {
      strengths: ["browser", "messaging", "system", "research"],
      speedTier: "standard",
      requiresAuth: "model API key via openclaw onboard",
      installCommand: "npm install -g openclaw@latest",
      installCheckBinary: "openclaw",
    },
    createAdapter: ({ log }) => new OpenClawRuntimeAdapter({ log }),
  },
  codex: {
    adapterId: "codex",
    activationEnv: ADAPTER_ACTIVATION_ENV.codex,
    maxWorkers: 1,
    capabilities: adapterCapabilitiesFor("codex"),
    capabilityTags: {
      strengths: ["coding", "repo_ops"],
      speedTier: "standard",
      requiresAuth: "ChatGPT sign in or OpenAI API key",
      installCommand: "npm install -g @zed-industries/codex-acp",
      installCheckBinary: "codex-acp",
    },
    createAdapter: ({ log }) => new CodexRuntimeAdapter({ log }),
  },
};

function isDirectedSelectableAdapterId(adapterId: SelectableAdapterId): adapterId is DirectedSelectableAdapterId {
  return (DIRECTED_SELECTABLE_ADAPTER_IDS as readonly SelectableAdapterId[]).includes(adapterId);
}

export function installCommandForDirectedAdapter(adapterId: string): string | null {
  const selectable = adapterId as SelectableAdapterId;
  if (!isDirectedSelectableAdapterId(selectable)) {
    return null;
  }
  const command = ADAPTER_PROFILES[selectable].capabilityTags.installCommand;
  return command || null;
}

export function rankAdapters(
  domain: TaskDomain | undefined,
  connected: SelectableAdapterId[],
  briefLength: number
): DirectedSelectableAdapterId[] {
  const candidates = connected.filter(isDirectedSelectableAdapterId);
  const scored = candidates.map((adapterId) => {
    const tags = ADAPTER_PROFILES[adapterId].capabilityTags;
    let score = 0;
    if (domain && tags.strengths.includes(domain)) {
      score += 2;
    }
    if (tags.speedTier === "fast" && briefLength < 200) {
      score += 1;
    }
    return {
      adapterId,
      score,
      order: DIRECTED_SELECTABLE_INSERTION_ORDER.indexOf(adapterId),
    };
  });

  scored.sort((left, right) => {
    if (right.score !== left.score) {
      return right.score - left.score;
    }
    if (left.adapterId === "acp" && right.adapterId !== "acp") {
      return -1;
    }
    if (right.adapterId === "acp" && left.adapterId !== "acp") {
      return 1;
    }
    return left.order - right.order;
  });

  return scored.map((entry) => entry.adapterId);
}

export function adapterIdForHarnessMode(harnessMode: string | undefined): SelectableAdapterId {
  if (harnessMode === undefined) return "acp";
  switch (harnessMode) {
    case "piMono":
    case "pi-mono":
      return "pi-mono";
    case "hermes":
      return "hermes";
    case "openclaw":
    case "openClaw":
      return "openclaw";
    case "codex":
      return "codex";
    case "acp":
      return "acp";
    default:
      throw new Error(`Unknown harness mode: ${harnessMode}`);
  }
}

export function adapterActivationEnv(adapterId: SelectableAdapterId): string | undefined {
  return ADAPTER_PROFILES[adapterId].activationEnv;
}

export function adapterIsActivated(
  adapterId: SelectableAdapterId,
  env: NodeJS.ProcessEnv = process.env
): boolean {
  const activationEnv = adapterActivationEnv(adapterId);
  return activationEnv === undefined || Boolean(env[activationEnv]?.trim());
}

export function adapterProfile(adapterId: ProductionAdapterId): AdapterProfile {
  return ADAPTER_PROFILES[adapterId];
}

export function adapterActivationError(adapterId: ProductionAdapterId): string | undefined {
  const envName = adapterActivationEnv(adapterId);
  if (!envName) return undefined;
  const label = adapterId === "pi-mono" ? "pi-mono" : adapterId === "openclaw" ? "OpenClaw" : adapterId === "codex" ? "Codex" : "Hermes";
  if (adapterId === "hermes" || adapterId === "openclaw" || adapterId === "codex") {
    return `${label} is not available. Make sure ${label} is installed first, then try again.`;
  }
  return `${label} adapter is unavailable.`;
}

export function ensureRegisteredAdapter(
  registry: AdapterRegistry,
  adapterId: ProductionAdapterId,
  options: {
    log: (message: string) => void;
    maxWorkers?: number;
    onCreate?: (adapter: RuntimeAdapter) => void;
  }
): boolean {
  if (!adapterIsActivated(adapterId)) return false;
  if (registry.has(adapterId)) return true;
  const profile = adapterProfile(adapterId);
  registry.register(adapterId, () => {
    const adapter = profile.createAdapter({ log: options.log });
    options.onCreate?.(adapter);
    return adapter;
  }, options.maxWorkers ?? profile.maxWorkers);
  options.log(`Adapter registered id=${adapterId} tools=${profile.capabilities.supportsTools} maxWorkers=${options.maxWorkers ?? profile.maxWorkers}`);
  return true;
}
