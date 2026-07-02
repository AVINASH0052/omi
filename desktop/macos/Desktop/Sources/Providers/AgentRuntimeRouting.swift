import Foundation

enum AgentHarnessMode: String {
    case piMono = "piMono"
    case acp = "acp"
    case hermes = "hermes"
    case openclaw = "openclaw"
    case codex = "codex"
}

extension Optional where Wrapped == AgentHarnessMode {
    /// Whether a pill renders an external-provider identity mark (a dedicated
    /// logo, or the robot catch-all) instead of the native Omi dot/badge.
    /// Omi-native agents (`nil` override) keep their round dot.
    var rendersProviderMark: Bool { self != nil }
}

enum AgentAdapterId: String {
    case piMono = "pi-mono"
    case acp = "acp"
    case hermes = "hermes"
    case openclaw = "openclaw"
    case codex = "codex"
}

enum AgentRuntimeRouting {
    static func harnessMode(for mode: ChatProvider.BridgeMode) -> AgentHarnessMode {
        switch mode {
        case .omiAI, .piMono:
            return .piMono
        case .userClaude:
            return .acp
        case .hermes:
            return .hermes
        case .openClaw:
            return .openclaw
        }
    }

    static func harnessMode(from rawValue: String) -> AgentHarnessMode? {
        switch rawValue {
        case AgentHarnessMode.piMono.rawValue, "pi-mono":
            return .piMono
        case AgentHarnessMode.acp.rawValue:
            return .acp
        case AgentHarnessMode.hermes.rawValue:
            return .hermes
        case AgentHarnessMode.openclaw.rawValue, "openClaw":
            return .openclaw
        case AgentHarnessMode.codex.rawValue:
            return .codex
        default:
            return nil
        }
    }

    static func adapterId(for harnessMode: AgentHarnessMode) -> AgentAdapterId {
        switch harnessMode {
        case .piMono:
            return .piMono
        case .acp:
            return .acp
        case .hermes:
            return .hermes
        case .openclaw:
            return .openclaw
        case .codex:
            return .codex
        }
    }
}

enum LocalAgentProviderNormalization {
    static func normalizeProviderToken(_ token: String) -> String {
        let normalized = token
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "codecs", "kodaks", "codex":
            return "codex"
        case "hermiss", "hermees", "hermes":
            return "hermes"
        case "openclaw":
            return "openclaw"
        default:
            return normalized
        }
    }
}

struct LocalAgentProviderAvailability: Equatable {
    enum Status: Equatable {
        case available(command: String)
        case missing
    }

    let provider: AgentPillsManager.DirectedProvider
    let status: Status

    var isAvailable: Bool {
        if case .available = status { return true }
        return false
    }

    var setupPrompt: String {
        switch provider {
        case .hermes:
            return "I don't see Hermes installed. Make sure Hermes is installed first, then try again."
        case .openclaw:
            return "I don't see OpenClaw installed. Make sure OpenClaw is installed first, then try again."
        case .codex:
            return "I don't see Codex installed. Make sure Codex is installed first, then try again."
        }
    }

    var toolError: String {
        "Error: \(setupPrompt)"
    }
}

enum LocalAgentProviderDetector {
    static func availability(
        for provider: AgentPillsManager.DirectedProvider,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        homeDirectory: String = NSHomeDirectory()
    ) -> LocalAgentProviderAvailability {
        if let command = configuredCommand(for: provider, environment: environment) {
            return LocalAgentProviderAvailability(provider: provider, status: .available(command: command))
        }

        let searchDirs = adapterActivationSearchDirectories(homeDirectory: homeDirectory)

        if provider == .codex {
            for name in [provider.executableName] + provider.alternateExecutableNames {
                if let path = firstExecutable(named: name, in: searchDirs, fileManager: fileManager) {
                    return LocalAgentProviderAvailability(provider: provider, status: .available(command: path))
                }
            }
            if let npxCommand = codexNpxFallbackCommand(
                environment: environment,
                fileManager: fileManager,
                searchDirectories: searchDirs
            ) {
                return LocalAgentProviderAvailability(provider: provider, status: .available(command: npxCommand))
            }
            return LocalAgentProviderAvailability(provider: provider, status: .missing)
        }

        if let path = firstExecutable(
            named: provider.executableName,
            in: searchDirs,
            fileManager: fileManager
        ) {
            return LocalAgentProviderAvailability(provider: provider, status: .available(command: path))
        }

        return LocalAgentProviderAvailability(provider: provider, status: .missing)
    }

    static func isAvailable(
        _ provider: AgentPillsManager.DirectedProvider,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        homeDirectory: String = NSHomeDirectory()
    ) -> Bool {
        availability(for: provider, environment: environment, fileManager: fileManager, homeDirectory: homeDirectory).isAvailable
    }

    private static func configuredCommand(
        for provider: AgentPillsManager.DirectedProvider,
        environment: [String: String]
    ) -> String? {
        let key = provider.commandEnvironmentName
        let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func firstExecutable(
        named name: String,
        in directories: [String],
        fileManager: FileManager
    ) -> String? {
        for dir in directories {
            let path = (dir as NSString).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func codexNpxFallbackCommand(
        environment: [String: String],
        fileManager: FileManager,
        searchDirectories: [String]
    ) -> String? {
        var directories = searchDirectories
        if let pathValue = environment["PATH"] {
            for entry in pathValue.split(separator: ":").map(String.init) where !entry.isEmpty {
                if !directories.contains(entry) {
                    directories.append(entry)
                }
            }
        }
        guard firstExecutable(named: "node", in: directories, fileManager: fileManager) != nil else {
            return nil
        }
        guard let npx = firstExecutable(named: "npx", in: directories, fileManager: fileManager) else {
            return nil
        }
        return "\(shellQuote(npx)) -y @zed-industries/codex-acp"
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func adapterActivationSearchDirectories(homeDirectory: String) -> [String] {
        [
            "\(homeDirectory)/.hermes/hermes-agent/venv/bin",
            "\(homeDirectory)/.hermes/node/bin",
            "\(homeDirectory)/.hermes/hermes-agent",
            "\(homeDirectory)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
    }
}
