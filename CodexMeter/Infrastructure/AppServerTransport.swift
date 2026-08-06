import Foundation

enum TransportEvent: Sendable { case started, terminated(Int32), stderr(String) }

protocol AppServerTransport: Sendable {
    func start() async throws
    func stop() async
    func send(_ data: Data) async throws
    func incomingData() async -> AsyncStream<Data>
    func events() async -> AsyncStream<TransportEvent>
}

actor ProcessAppServerTransport: AppServerTransport {
    private let executableURL: URL
    private var process: Process?
    private var input: FileHandle?
    private let stdoutContinuation: AsyncStream<Data>.Continuation
    private let eventContinuation: AsyncStream<TransportEvent>.Continuation
    private var stderrLines = [String]()
    private let stdoutStream: AsyncStream<Data>
    private let eventStream: AsyncStream<TransportEvent>

    init(executableURL: URL) {
        self.executableURL = executableURL
        let stdout = AsyncStream.makeStream(of: Data.self)
        let events = AsyncStream.makeStream(of: TransportEvent.self)
        stdoutStream = stdout.stream; stdoutContinuation = stdout.continuation
        eventStream = events.stream; eventContinuation = events.continuation
    }
    func incomingData() async -> AsyncStream<Data> { stdoutStream }
    func events() async -> AsyncStream<TransportEvent> { eventStream }
    func start() async throws {
        guard process == nil else { return }
        let process = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = executableURL; process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
        let owner = self
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData; guard !data.isEmpty else { return }; Task { await owner.emitStdout(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData; guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            Task { await owner.recordStderr(text) }
        }
        process.terminationHandler = { process in Task { await owner.terminated(process.terminationStatus) } }
        try process.run(); self.process = process; input = stdin.fileHandleForWriting; eventContinuation.yield(.started)
    }
    func stop() async {
        input?.closeFile(); process?.terminate(); process = nil; input = nil
    }
    func send(_ data: Data) async throws {
        guard let input else { throw CodexMeterError.disconnected("Codex app-server 已断开") }
        try input.write(contentsOf: data)
    }
    func diagnosticStderr() -> [String] { stderrLines }
    private func recordStderr(_ text: String) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let safe = redact(String(line)); stderrLines.append(safe); eventContinuation.yield(.stderr(safe))
        }
        if stderrLines.count > 100 { stderrLines.removeFirst(stderrLines.count - 100) }
    }
    private func redact(_ line: String) -> String {
        line.replacingOccurrences(of: "(?i)(authorization|api[_-]?key|token|cookie)\\s*[:=]\\s*[^\\s,]+", with: "$1: [REDACTED]", options: .regularExpression)
    }
    private func emitStdout(_ data: Data) { stdoutContinuation.yield(data) }
    private func terminated(_ status: Int32) { process = nil; input = nil; eventContinuation.yield(.terminated(status)) }
}
