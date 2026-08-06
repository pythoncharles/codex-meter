import Foundation

enum AppServerNotification: Sendable { case rateLimitsUpdated, accountUpdated, disconnected(String) }
private struct RPCRequest<Params: Encodable>: Encodable { let method: String; let id: Int; let params: Params? }
private struct RPCNotification: Encodable { let method: String; let params: Empty? = nil }
private struct Empty: Encodable { }

actor CodexAppServerClient {
    private let transport: AppServerTransport
    private var nextID = 1
    private struct PendingRequest {
        let continuation: CheckedContinuation<Data, Error>
        let timeout: Task<Void, Never>
    }
    private var pending = [Int: PendingRequest]()
    private let notificationContinuation: AsyncStream<AppServerNotification>.Continuation
    private let notificationStream: AsyncStream<AppServerNotification>
    private var reader: Task<Void, Never>?
    private var lifecycle: Task<Void, Never>?
    private var initialized = false

    init(transport: AppServerTransport) {
        self.transport = transport
        let notifications = AsyncStream.makeStream(of: AppServerNotification.self)
        notificationStream = notifications.stream; notificationContinuation = notifications.continuation
    }
    func notifications() -> AsyncStream<AppServerNotification> { notificationStream }
    func connect() async throws {
        guard !initialized else { return }
        try await transport.start()
        reader = Task { [weak self] in await self?.receiveLoop() }
        lifecycle = Task { [weak self] in await self?.observeLifecycle() }
        do {
            _ = try await request(method: "initialize", params: ["clientInfo": ["name": "codex_meter", "title": "Codex Meter", "version": "0.1.0"]], requiresInitialization: false)
            try await send(RPCNotification(method: "initialized"))
            initialized = true
        } catch {
            await disconnect()
            throw error
        }
    }
    func disconnect() async { reader?.cancel(); lifecycle?.cancel(); reader = nil; lifecycle = nil; initialized = false; await transport.stop(); failPending(CodexMeterError.disconnected("Codex app-server 已断开")) }
    func requestRateLimits() async throws -> RateLimitsResultDTO { try decode(try await request(method: "account/rateLimits/read", params: Optional<[String: String]>.none)) }
    func requestTokenUsage() async throws -> AccountTokenUsageResultDTO { try decode(try await request(method: "account/usage/read", params: Optional<[String: String]>.none)) }
    func requestAccount() async throws -> AccountReadResultDTO { try decode(try await request(method: "account/read", params: ["refreshToken": false])) }

    private func request<Params: Encodable>(method: String, params: Params?, requiresInitialization: Bool = true) async throws -> Data {
        guard !requiresInitialization || initialized else { throw CodexMeterError.disconnected("尚未完成 initialize") }
        let id = nextID; nextID += 1
        let requestData = try encoded(RPCRequest(method: method, id: id, params: params))
        return try await withCheckedThrowingContinuation { continuation in
            let timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await self?.failRequest(id, error: .timeout)
            }
            pending[id] = PendingRequest(continuation: continuation, timeout: timeout)
            Task { [weak self] in
                do { try await self?.transport.send(requestData) }
                catch { await self?.failRequest(id, error: .disconnected(error.localizedDescription)) }
            }
        }
    }
    private func send<T: Encodable>(_ value: T) async throws {
        try await transport.send(try encoded(value))
    }
    private func encoded<T: Encodable>(_ value: T) throws -> Data { var data = try JSONEncoder().encode(value); data.append(10); return data }
    private func decode<T: Decodable>(_ data: Data) throws -> T { try JSONDecoder().decode(T.self, from: data) }
    private func receiveLoop() async {
        var decoder = JSONLStreamDecoder()
        for await chunk in await transport.incomingData() {
            for message in decoder.append(chunk) { handle(message) }
        }
    }
    private func handle(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let id = object["id"] as? Int, let request = pending.removeValue(forKey: id) {
            request.timeout.cancel()
            if let error = object["error"] as? [String: Any] { request.continuation.resume(throwing: CodexMeterError.invalidResponse(error["message"] as? String ?? "RPC 错误")) }
            else if let result = object["result"] { request.continuation.resume(returning: (try? JSONSerialization.data(withJSONObject: result)) ?? Data()) }
        }
        if let method = object["method"] as? String {
            if method == "account/rateLimits/updated" { notificationContinuation.yield(.rateLimitsUpdated) }
            if method == "account/updated" { notificationContinuation.yield(.accountUpdated) }
        }
    }
    private func observeLifecycle() async {
        for await event in await transport.events() {
            guard case .terminated(let status) = event else { continue }
            initialized = false
            let error = CodexMeterError.disconnected("Codex app-server 异常退出（状态码 \(status)）")
            failPending(error); notificationContinuation.yield(.disconnected(error.localizedDescription))
        }
    }
    private func failRequest(_ id: Int, error: CodexMeterError) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel(); request.continuation.resume(throwing: error)
    }
    private func failPending(_ error: Error) {
        let values = pending.values; pending.removeAll()
        values.forEach { $0.timeout.cancel(); $0.continuation.resume(throwing: error) }
    }
}
