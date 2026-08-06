import Combine
import AppKit
import Foundation

enum QuotaScreenState { case loading, loaded(CodexQuotaSnapshot), stale(CodexQuotaSnapshot, error: String), codexNotInstalled, notLoggedIn, unsupportedAuthMode, disconnected(message: String) }

@MainActor final class QuotaViewModel: NSObject, ObservableObject {
    @Published private(set) var state: QuotaScreenState = .loading
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var now = Date()
    @Published private(set) var isRefreshing = false
    let repository: QuotaRepositoryProtocol
    private var eventTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    init(repository: QuotaRepositoryProtocol? = nil) {
        let customPath = UserDefaults.standard.string(forKey: "customCodexPath")
        self.repository = repository ?? QuotaRepository(customPath: customPath?.isEmpty == false ? customPath : nil)
        super.init()
    }
    func start() {
        guard eventTask == nil else { return }
        let repository = repository
        eventTask = Task { [weak self] in
            let stream = await repository.events()
            for await event in stream { self?.receive(event) }
        }
        Task { await repository.start() }
        let defaults = UserDefaults.standard
        configureAutoRefresh(RefreshInterval(rawValue: defaults.integer(forKey: "refreshInterval")) ?? .seconds60, enabled: defaults.object(forKey: "autoRefresh") as? Bool ?? true)
        tickTask = Task { [weak self] in while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)); self?.now = .now } }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willTerminate), name: NSApplication.willTerminateNotification, object: nil)
    }
    func stop() { eventTask?.cancel(); refreshTask?.cancel(); tickTask?.cancel(); eventTask = nil; NSWorkspace.shared.notificationCenter.removeObserver(self); NotificationCenter.default.removeObserver(self); Task { await repository.stop() } }
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let repository = repository, reconnect = connectionState == .disconnected
        Task { [weak self] in
            reconnect ? await repository.start() : await repository.refresh()
            self?.isRefreshing = false
        }
    }
    func configureAutoRefresh(_ interval: RefreshInterval, enabled: Bool) {
        refreshTask?.cancel(); guard enabled, interval.rawValue > 0 else { return }
        refreshTask = Task { [weak self] in while !Task.isCancelled { try? await Task.sleep(for: .seconds(interval.rawValue)); self?.refresh() } }
    }
    private func receive(_ event: QuotaRepositoryEvent) {
        switch event {
        case .snapshot(let snapshot): state = .loaded(snapshot)
        case .connectionState(let value): connectionState = value
        case .account: break
        case .error(let error):
            if case .loaded(let snapshot) = state { state = .stale(snapshot, error: error.localizedDescription) }
            else { switch error { case .codexNotInstalled: state = .codexNotInstalled; case .notLoggedIn: state = .notLoggedIn; case .unsupportedAuthMode: state = .unsupportedAuthMode; default: state = .disconnected(message: error.localizedDescription) } }
        }
    }
    @objc private func didWake() { refresh() }
    @objc private func willTerminate() { stop() }
}
