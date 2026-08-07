import Foundation

enum QuotaRepositoryEvent: Sendable { case snapshot(CodexQuotaSnapshot), connectionState(ConnectionState), error(CodexMeterError), account(AccountInfo?) }
protocol QuotaRepositoryProtocol: Sendable { func start() async; func stop() async; func refresh() async; func events() async -> AsyncStream<QuotaRepositoryEvent> }

actor QuotaRepository: QuotaRepositoryProtocol {
    private let customPath: String?
    private var client: CodexAppServerClient?
    private var refreshing = false
    private let eventsContinuation: AsyncStream<QuotaRepositoryEvent>.Continuation
    private let eventStream: AsyncStream<QuotaRepositoryEvent>
    private var notificationTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private let cache = QuotaCache()

    init(customPath: String? = nil) { self.customPath = customPath; let events = AsyncStream.makeStream(of: QuotaRepositoryEvent.self); eventStream = events.stream; eventsContinuation = events.continuation }
    func events() async -> AsyncStream<QuotaRepositoryEvent> { eventStream }
    func start() async {
        guard client == nil else { return }
        eventsContinuation.yield(.connectionState(.connecting))
        do {
            try await connect()
        } catch let error as CodexMeterError { eventsContinuation.yield(.error(error)); eventsContinuation.yield(.connectionState(.disconnected))
        } catch { eventsContinuation.yield(.error(.disconnected(error.localizedDescription))) }
    }
    func stop() async { reconnectTask?.cancel(); notificationTask?.cancel(); reconnectTask = nil; notificationTask = nil; await client?.disconnect(); client = nil; eventsContinuation.yield(.connectionState(.disconnected)) }
    func refresh() async {
        guard !refreshing, let client else { return }; refreshing = true; defer { refreshing = false }
        do {
            let account = try await client.requestAccount()
            if account.account == nil && account.requiresOpenaiAuth == true { eventsContinuation.yield(.error(.notLoggedIn)); return }
            if account.account?.type == "apiKey" { eventsContinuation.yield(.error(.unsupportedAuthMode)); return }
            eventsContinuation.yield(.account(account.account))
            let limits = try await client.requestRateLimits()
            let usage = try? await client.requestTokenUsage()
            let snapshot = QuotaMapper.snapshot(from: limits, tokenUsage: usage)
            cache.save(snapshot); eventsContinuation.yield(.snapshot(snapshot))
        } catch let error as CodexMeterError { eventsContinuation.yield(.error(error))
        } catch { eventsContinuation.yield(.error(.disconnected(error.localizedDescription))) }
    }

    private func connect() async throws {
        let binary = try CodexBinaryLocator(customPath: customPath).locate()
        let client = CodexAppServerClient(transport: ProcessAppServerTransport(executableURL: binary.url)); self.client = client
        do { try await client.connect() } catch { self.client = nil; throw error }
        eventsContinuation.yield(.connectionState(.connected)); await refresh()
        notificationTask = Task { [weak self] in
            for await notification in await client.notifications() { await self?.handle(notification) }
        }
    }

    private func handle(_ notification: AppServerNotification) async {
        switch notification {
        case .rateLimitsUpdated, .accountUpdated: await refresh()
        case .disconnected(let message):
            client = nil; eventsContinuation.yield(.connectionState(.disconnected)); eventsContinuation.yield(.error(.disconnected(message)))
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            for attempt in 0..<5 {
                try? await Task.sleep(for: .seconds(min(30, 1 << attempt)))
                guard !Task.isCancelled, let self else { return }
                self.eventsContinuation.yield(.connectionState(.connecting))
                do { try await self.connect(); await self.clearReconnectTask(); return } catch { }
            }
            guard let self else { return }
            self.eventsContinuation.yield(.error(.disconnected("连续重连 5 次失败，请手动重试")))
            await self.clearReconnectTask()
        }
    }
    private func clearReconnectTask() { reconnectTask = nil }
}

final class QuotaCache {
    private let defaults = UserDefaults.standard
    private let snapshotKey = "lastQuotaSnapshot"
    func save(_ snapshot: CodexQuotaSnapshot) { defaults.set(try? JSONEncoder().encode(snapshot), forKey: snapshotKey); defaults.set(snapshot.fetchedAt, forKey: "lastQuotaUpdate") }
    func load() -> CodexQuotaSnapshot? { defaults.data(forKey: snapshotKey).flatMap { try? JSONDecoder().decode(CodexQuotaSnapshot.self, from: $0) } }
}

enum RefreshInterval: Int, CaseIterable { case seconds30 = 30, seconds60 = 60, seconds120 = 120, seconds300 = 300, seconds360 = 360, seconds600 = 600, seconds900 = 900, manual = 0 }

@MainActor final class AppSettings: ObservableObject {
    @Published var autoRefresh = UserDefaults.standard.object(forKey: "autoRefresh") as? Bool ?? true { didSet { UserDefaults.standard.set(autoRefresh, forKey: "autoRefresh") } }
    @Published var refreshInterval = RefreshInterval(rawValue: UserDefaults.standard.integer(forKey: "refreshInterval")) ?? .seconds60 { didSet { UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshInterval") } }
    @Published var floating = UserDefaults.standard.object(forKey: "floating") as? Bool ?? true { didSet { UserDefaults.standard.set(floating, forKey: "floating") } }
    @Published var allSpaces = UserDefaults.standard.object(forKey: "allSpaces") as? Bool ?? true { didSet { UserDefaults.standard.set(allSpaces, forKey: "allSpaces") } }
    @Published var customCodexPath = UserDefaults.standard.string(forKey: "customCodexPath") ?? "" { didSet { UserDefaults.standard.set(customCodexPath, forKey: "customCodexPath") } }
}
