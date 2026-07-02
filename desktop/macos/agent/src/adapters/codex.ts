import { AcpRuntimeAdapter } from "./acp.js";

export interface CodexRuntimeAdapterOptions {
  command?: string;
  log?: (message: string) => void;
}

export class CodexRuntimeAdapter extends AcpRuntimeAdapter {
  constructor(options: CodexRuntimeAdapterOptions = {}) {
    super({
      adapterId: "codex",
      envCommandName: "OMI_CODEX_ADAPTER_COMMAND",
      command: options.command,
      // @zed-industries/codex-acp accepts client-provided MCP servers; keep passthrough default.
      log: options.log,
    });
  }
}
