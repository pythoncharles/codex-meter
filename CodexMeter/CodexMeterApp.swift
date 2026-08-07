import AppKit
import SwiftUI

enum AppTheme: String, CaseIterable {
    case dark, light
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var title: String { self == .dark ? "深色" : "浅色" }
}

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
        Button("退出 Codex Meter") { NSApplication.shared.terminate(nil) }
        .onAppear { model.start() }
    }
}
