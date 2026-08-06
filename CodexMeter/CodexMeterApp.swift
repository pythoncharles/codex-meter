import AppKit
import SwiftUI

@main struct CodexMeterApp: App {
    @StateObject private var model: QuotaViewModel
    init() {
        let model = QuotaViewModel()
        _model = StateObject(wrappedValue: model)
        model.start()
    }
    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .scaleEffect(1.3)
                .accessibilityLabel(menuTitle)
        }
        .menuBarExtraStyle(.menu)
        Settings { SettingsView() }
    }
    private var menuTitle: String {
        if case .loaded(let snapshot) = model.state, let window = snapshot.fiveHour ?? snapshot.weekly { return "\(Int(window.remainingPercent))%" }
        return "Codex"
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: QuotaViewModel
    var body: some View {
        Button("显示或隐藏浮窗") { PanelController.shared.toggle(model: model) }
        Button("立即刷新") { model.refresh() }
        Divider()
        SettingsLink { Text("打开设置") }
        Button("退出 Codex Meter") { NSApplication.shared.terminate(nil) }
        .onAppear { model.start() }
    }
}

private struct SettingsView: View {
    @StateObject private var settings = AppSettings()
    var body: some View { Form { Toggle("自动刷新", isOn: $settings.autoRefresh); Picker("刷新间隔", selection: $settings.refreshInterval) { ForEach(RefreshInterval.allCases, id: \.self) { Text($0 == .manual ? "仅手动" : "\($0.rawValue) 秒").tag($0) } }; TextField("Codex 路径", text: $settings.customCodexPath) }.padding().frame(width: 420) }
}
