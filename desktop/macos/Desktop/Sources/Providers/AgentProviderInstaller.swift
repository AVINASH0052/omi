import Foundation

enum AgentProviderInstaller {
  struct Result: Equatable {
    let exitCode: Int32
    let stderrTail: String
    var succeeded: Bool { exitCode == 0 }
  }

  /// Runs an allowlisted install command exactly as provided. No interpolation.
  static func run(
    command: String,
    onLine: @escaping @MainActor (String) -> Void
  ) async -> Result {
    await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/bash")
      process.arguments = ["-c", command]

      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe

      var stderrLines: [String] = []
      let stderrLock = NSLock()

      func drain(pipe: Pipe, prefix: String) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
          let data = handle.availableData
          guard !data.isEmpty else { return }
          guard let chunk = String(data: data, encoding: .utf8) else { return }
          for rawLine in chunk.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if prefix == "stderr" {
              stderrLock.lock()
              stderrLines.append(line)
              if stderrLines.count > 40 {
                stderrLines.removeFirst(stderrLines.count - 40)
              }
              stderrLock.unlock()
            }
            Task { @MainActor in
              onLine(line)
            }
          }
        }
      }

      drain(pipe: stdoutPipe, prefix: "stdout")
      drain(pipe: stderrPipe, prefix: "stderr")

      process.terminationHandler = { proc in
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stderrLock.lock()
        let tail = stderrLines.suffix(8).joined(separator: "\n")
        stderrLock.unlock()
        continuation.resume(returning: Result(exitCode: proc.terminationStatus, stderrTail: tail))
      }

      do {
        try process.run()
      } catch {
        continuation.resume(returning: Result(exitCode: 127, stderrTail: error.localizedDescription))
      }
    }
  }
}
