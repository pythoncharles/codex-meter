import Foundation

struct CodexBinaryLocator {
    var customPath: String?
    private let fileManager: FileManager
    init(customPath: String? = nil, fileManager: FileManager = .default) { self.customPath = customPath; self.fileManager = fileManager }

    func locate() throws -> (url: URL, version: String) {
        let home = fileManager.homeDirectoryForCurrentUser.path
        var paths = [customPath].compactMap { $0 }
        paths += ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map { "\($0)/codex" } ?? []
        paths += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex", "\(home)/bin/codex", "/Applications/ChatGPT.app/Contents/Resources/codex"]
        if let shellPath = try? shellCodexPath() { paths.append(shellPath) }
        for path in paths {
            guard fileManager.isExecutableFile(atPath: path) else { continue }
            if let version = try? runVersion(URL(fileURLWithPath: path)) { return (URL(fileURLWithPath: path), version) }
        }
        throw CodexMeterError.codexNotInstalled
    }

    private func shellCodexPath() throws -> String {
        let output = try run("/bin/zsh", ["-lc", "command -v codex"])
        guard let path = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { throw CodexMeterError.codexNotInstalled }
        return path
    }
    private func runVersion(_ url: URL) throws -> String {
        let output = try run(url.path, ["--version"])
        return String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    private func run(_ executable: String, _ arguments: [String]) throws -> Data {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe(); try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CodexMeterError.codexNotInstalled }
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }
}
