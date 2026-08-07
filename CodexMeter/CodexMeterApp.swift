import AppKit
import SwiftUI

enum AppLanguage: String, CaseIterable {
    case chinese = "zh-Hans", english = "en"
}

func appText(_ chinese: String, _ english: String) -> String {
    (AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.chinese.rawValue) ?? .chinese) == .english ? english : chinese
}

enum AppTheme: String, CaseIterable {
    case dark, light
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var title: String { self == .dark ? appText("深色", "Dark") : appText("浅色", "Light") }
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
        Button(appText("显示或隐藏浮窗", "Show or hide panel")) { PanelController.shared.toggle(model: model) }
        Button(appText("立即刷新", "Refresh now")) { model.refresh() }
        Divider()
        Button(appText("关于Codex Meter", "About Codex Meter")) { presentAbout() }
        Button(appText("退出Codex Meter", "Quit Codex Meter")) { NSApplication.shared.terminate(nil) }
        .onAppear { model.start() }
    }
    private func presentAbout() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = appText("关于Codex Meter", "About Codex Meter")
            alert.informativeText = appText("版权所有来自王成龙制作，绿泡泡：amaowangcl", "Created by Wang Chenglong · WeChat: amaowangcl")
            alert.addButton(withTitle: appText("确定", "OK"))
            NSApplication.shared.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
