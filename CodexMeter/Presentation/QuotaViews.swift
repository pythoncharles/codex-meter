import AppKit
import Charts
import SwiftUI

private let panelPrimary = Color.primary
private let panelSecondary = Color.secondary
private let panelTertiary = Color.secondary.opacity(0.72)

struct QuotaContentView: View {
    @ObservedObject var model: QuotaViewModel
    @StateObject private var settings = AppSettings()
    @AppStorage("appTheme") private var appTheme = AppTheme.dark.rawValue
    @AppStorage("panelBackgroundOpacity") private var panelBackgroundOpacity = 0.52
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.chinese.rawValue
    @State private var showDisconnectedAlert = false
    @State private var detailCard: DetailCard = .quota
    @State private var previousDetailCard: DetailCard = .quota
    @State private var pageOpacity = 1.0
    @State private var pageOffset: CGFloat = 0
    @State private var isPageTransitioning = false
    private var theme: AppTheme { AppTheme(rawValue: appTheme) ?? .dark }
    private var panelBackground: Color { (theme == .dark ? Color.black : .white).opacity(panelBackgroundOpacity) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(12)
        .frame(width: 350)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(panelPrimary)
        .background {
            ZStack {
//                 RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial)
//                 LinearGradient(colors: [.blue.opacity(0.16), .clear, .orange.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial).opacity(panelBackgroundOpacity)
                LinearGradient(colors: [.blue.opacity(0.16), .clear, .orange.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing).opacity(panelBackgroundOpacity)
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(panelBackground)
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.primary.opacity(0.2), lineWidth: 1.2) }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .environment(\.colorScheme, theme.colorScheme)
        .onChange(of: detailCard) { _, _ in
            DispatchQueue.main.async { PanelController.shared.resizeToFit(animated: true) }
        }
        .onExitCommand { PanelController.shared.hide() }
        .alert(appText("Codex app-server 未连接", "Codex app-server disconnected"), isPresented: $showDisconnectedAlert) {
            Button(appText("重试连接", "Reconnect")) { model.refresh() }
            Button(appText("取消", "Cancel"), role: .cancel) { }
        } message: {
            Text(appText("当前无法刷新额度，请检查 Codex 是否可用后重试。", "Quota refresh is unavailable. Check Codex and try again."))
        }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: .blue.opacity(0.35), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text("Codex Meter").font(.title3.bold())
                Text(verbatim: appText("额度概览 · 更新于", "Quota · Updated") + (snapshot.map { " \($0.fetchedAt.formatted(date: .omitted, time: .shortened))" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityLabel(snapshot.map { appText("额度概览，更新于 \($0.fetchedAt.formatted(date: .omitted, time: .shortened))", "Quota overview, updated at \($0.fetchedAt.formatted(date: .omitted, time: .shortened))") } ?? appText("额度概览", "Quota overview"))
            }
            Spacer()
            if let plan = snapshot?.planType {
                Text(plan.uppercased())
                    .font(.caption2.bold()).foregroundStyle(.cyan)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.cyan.opacity(0.14), in: Capsule())
            }
            Button {
                if model.connectionState == .disconnected { showDisconnectedAlert = true }
                else { model.refresh() }
            } label: {
                ZStack {
                    Circle().fill(.primary.opacity(0.055))
                    Circle().stroke(.primary.opacity(0.08))
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                        .animation(model.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .linear(duration: 0), value: model.isRefreshing)
                }
                .frame(width: 32, height: 32)
                .contentShape(Circle())
            }
            .buttonStyle(.plain).foregroundStyle(.blue)
            .disabled(model.isRefreshing)
            .help(appText("立即刷新", "Refresh now"))
            Button(action: toggleSettings) { Image(systemName: detailCard == .settings ? "arrow.uturn.backward" : "gearshape").frame(width: 32, height: 32) }
                .buttonStyle(.plain).foregroundStyle(detailCard == .settings ? .blue : panelPrimary)
                .background(.primary.opacity(0.055), in: Circle())
                .overlay { Circle().stroke(.primary.opacity(0.08)) }
                .help(detailCard == .settings ? appText("返回上一页", "Back") : appText("设置", "Settings"))
        }
    }
    private var snapshot: CodexQuotaSnapshot? {
        switch model.state {
        case .loaded(let snapshot), .stale(let snapshot, _): return snapshot
        default: return nil
        }
    }
    @ViewBuilder private var content: some View {
        if detailCard == .settings {
            SettingsCard(settings: settings) { interval, enabled in
                model.configureAutoRefresh(interval, enabled: enabled)
            }
            .opacity(pageOpacity)
            .offset(x: pageOffset)
            .allowsHitTesting(!isPageTransitioning)
        } else {
        switch model.state {
        case .loaded(let snapshot): quota(snapshot)
        case .stale(let snapshot, let error): VStack(alignment: .leading, spacing: 12) { quota(snapshot); Label(appText("额度更新失败：", "Quota update failed: ") + error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
        case .loading: HStack { Spacer(); ProgressView(appText("正在连接 Codex…", "Connecting to Codex…")); Spacer() }.padding(.vertical, 28)
        case .codexNotInstalled: error(appText("未找到 Codex CLI", "Codex CLI not found"), appText("请安装 Codex CLI，或在设置中选择 codex 可执行文件。", "Install Codex CLI or choose its executable in Settings."))
        case .notLoggedIn: error(appText("Codex 尚未登录 ChatGPT", "Codex is not logged in"), appText("请先在终端运行 codex 并完成登录。", "Run codex in Terminal and complete sign-in first."))
        case .unsupportedAuthMode: error(appText("当前 Codex 使用 API Key", "Codex uses an API key"), appText("ChatGPT 5 小时和周额度不适用于当前认证模式。", "ChatGPT quota windows do not apply to this authentication mode."))
        case .disconnected(let message): error(appText("Codex app-server 已断开", "Codex app-server disconnected"), appText("正在尝试重新连接。", "Reconnecting.") + "\n\(message)")
        }
        }
    }
    private func quota(_ snapshot: CodexQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fiveHour = snapshot.fiveHour { QuotaRow(title: appText("5 小时额度", "5-hour quota"), window: fiveHour, now: model.now) }
            if let weekly = snapshot.weekly {
                detailCardView(window: weekly, usage: snapshot.tokenUsage)
                    .opacity(pageOpacity)
                    .offset(x: pageOffset)
                    .allowsHitTesting(!isPageTransitioning)
            }
            if snapshot.fiveHour == nil && snapshot.weekly == nil { Text(appText("暂无可识别的额度窗口", "No recognized quota window")).foregroundStyle(panelSecondary) }
        }
    }
    private func error(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "exclamationmark.circle.fill").font(.headline).foregroundStyle(.orange)
            Text(detail).font(.subheadline).foregroundStyle(panelSecondary).fixedSize(horizontal: false, vertical: true)
            Button { model.refresh() } label: { Label(appText("重试", "Retry"), systemImage: "arrow.clockwise") }.buttonStyle(.borderedProminent)
        }
        .padding(16).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    @ViewBuilder private func detailCardView(window: QuotaWindow, usage: AccountTokenUsageResultDTO?) -> some View {
        switch detailCard {
        case .quota:
            WeeklyQuotaCard(window: window, usage: usage, now: model.now, showsHistory: false, toggleHistory: { setDetailCard(.history) })
                .frame(height: 205)
        case .history:
            WeeklyQuotaCard(window: window, usage: usage, now: model.now, showsHistory: true, toggleHistory: { setDetailCard(.quota) })
        case .settings: EmptyView()
        }
    }
    private func setDetailCard(_ value: DetailCard) {
        guard detailCard != value, !isPageTransitioning else { return }
        isPageTransitioning = true
        let exitOffset: CGFloat = value == .quota ? 8 : -8
        let enterOffset: CGFloat = value == .quota ? -8 : 8
        withAnimation(.smooth(duration: 0.16)) {
            pageOpacity = 0
            pageOffset = exitOffset
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            detailCard = value
            pageOffset = enterOffset
            DispatchQueue.main.async {
                withAnimation(.smooth(duration: 0.24)) {
                    pageOpacity = 1
                    pageOffset = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { isPageTransitioning = false }
            }
        }
    }
    private func toggleSettings() {
        if detailCard == .settings {
            setDetailCard(previousDetailCard)
        } else {
            previousDetailCard = detailCard
            setDetailCard(.settings)
        }
    }
}

private enum DetailCard: Equatable { case quota, history, settings }

private struct SettingsCard: View {
    @ObservedObject var settings: AppSettings
    let configureAutoRefresh: (RefreshInterval, Bool) -> Void
    @AppStorage("appTheme") private var appTheme = AppTheme.dark.rawValue
    @AppStorage("panelBackgroundOpacity") private var panelBackgroundOpacity = 0.52
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.chinese.rawValue

    private let labelWidth: CGFloat = 82

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(appText("设置", "Settings"), systemImage: "gearshape").font(.title3.bold())
                Spacer()
                Picker("", selection: $appLanguage) {
                    Text("中").tag(AppLanguage.chinese.rawValue)
                    Text("EN").tag(AppLanguage.english.rawValue)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 82)
            }
            HStack(spacing: 8) {
                Text(appText("主题", "Theme"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(panelSecondary)
                    .frame(width: labelWidth, alignment: .leading)
                Picker("", selection: $appTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden().pickerStyle(.segmented)
                .accessibilityLabel(appText("主题", "Theme"))
            }
            HStack(spacing: 8) {
                Text(verbatim: appText("背景", "Opacity") + " \(Int(panelBackgroundOpacity * 100))%")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(panelSecondary)
                    .frame(width: labelWidth, alignment: .leading)
                    .help(appText("背景透明度", "Background opacity"))
                Slider(value: $panelBackgroundOpacity, in: 0.15...0.9, step: 0.05)
                    .labelsHidden()
                    .accessibilityLabel(appText("背景透明度", "Background opacity"))
            }
            HStack(spacing: 10) {
                Text(appText("自动刷新", "Auto Refresh"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(panelSecondary)
                    .frame(width: labelWidth, alignment: .leading)
                    .help(appText("自动刷新", "Auto refresh"))
                Toggle("", isOn: $settings.autoRefresh)
                    .labelsHidden().toggleStyle(.switch).tint(settings.autoRefresh ? .green : .gray)
                    .accessibilityLabel(appText("自动刷新", "Auto refresh"))
                Picker(appText("刷新间隔", "Interval"), selection: $settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases, id: \.self) { Text($0 == .manual ? appText("仅手动", "Manual") : "\($0.rawValue) \(appText("秒", "sec"))").tag($0) }
                }
                .labelsHidden().frame(maxWidth: .infinity)
                .disabled(!settings.autoRefresh).opacity(settings.autoRefresh ? 1 : 0.45)
            }
            HStack(spacing: 8) {
                Text(appText("Codex 路径", "Codex Path"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(panelSecondary)
                    .frame(width: labelWidth, alignment: .leading)
                    .help(appText("Codex 路径", "Codex path"))
                TextField(appText("Codex 路径", "Codex path"), text: $settings.customCodexPath)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(12)
        .frame(height: 205)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.primary.opacity(0.16), lineWidth: 1) }
        .onAppear {
            guard settings.customCodexPath.isEmpty else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                guard let location = try? CodexBinaryLocator().locate() else { return }
                DispatchQueue.main.async {
                    guard settings.customCodexPath.isEmpty else { return }
                    settings.customCodexPath = location.url.path
                }
            }
        }
        .onChange(of: settings.autoRefresh) { _, enabled in configureAutoRefresh(settings.refreshInterval, enabled) }
        .onChange(of: settings.refreshInterval) { _, interval in configureAutoRefresh(interval, settings.autoRefresh) }
    }
}

private struct WeeklyQuotaCard: View {
    let window: QuotaWindow
    let usage: AccountTokenUsageResultDTO?
    let now: Date
    let showsHistory: Bool
    let toggleHistory: () -> Void

    var body: some View {
        ZStack {
            if showsHistory {
                TokenHistoryView(usage: usage, now: now) {
                    toggleHistory()
                }
            } else {
                QuotaRow(title: appText("周额度", "Weekly quota"), window: window, now: now)
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onTapGesture { toggleHistory() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(appText("周额度，点击查看历史用量", "Weekly quota, show usage history"))
            }
        }
    }
}

private struct TokenHistoryView: View {
    let usage: AccountTokenUsageResultDTO?
    let now: Date
    let close: () -> Void
    @State private var period: TokenUsagePeriod = .daily
    @State private var selectedDate: Date?
    @State private var isSwipeLocked = false

    private var buckets: [AccountTokenUsageDailyBucket] { usage?.dailyUsageBuckets ?? [] }
    private var points: [TokenUsagePoint] { TokenUsageSeries.points(from: buckets, period: period, endingAt: now) }
    private var gridDates: [Date] { TokenUsageSeries.gridDates(from: points, period: period) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(appText("历史用量", "Usage history"), systemImage: "chart.xyaxis.line").font(.headline)
                Spacer()
                Button(action: close) {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(0.055), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).help(appText("返回周额度", "Back to weekly quota"))
            }
            if let summary = usage?.summary {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    metric(appText("累计Token", "Total tokens"), compact(summary.lifetimeTokens), "sum")
                    metric(appText("单日峰值", "Daily peak"), compact(summary.peakDailyTokens), "waveform.path.ecg")
                    metric(appText("最长聊天", "Longest chat"), duration(summary.longestRunningTurnSec), "timer")
                    metric(appText("当前连续", "Current streak"), days(summary.currentStreakDays), "flame")
                    metric(appText("最长连续", "Longest streak"), days(summary.longestStreakDays), "trophy")
                }

                HStack(spacing: 2) {
                    periodButton(appText("每日", "Daily"), .daily)
                    periodButton(appText("每周", "Weekly"), .weekly)
                    periodButton(appText("累计", "Total"), .cumulative)
                }
                .padding(2)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.primary.opacity(0.14)) }

                HStack {
                    Text(periodTitle).font(.caption.bold()).foregroundStyle(panelSecondary)
                    Spacer()
                    if let point = displayedPoint {
                        Text("\(dateLabel(point.date)) · \(compact(point.tokens)) Token")
                            .font(.caption.monospacedDigit()).foregroundStyle(panelSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
//                  Text("亿").font(.caption2).foregroundStyle(panelSecondary).offset(y: -10).frame(width: 18, height: 8)
                    Chart(points) { point in
                    if period == .cumulative {
                        AreaMark(x: .value("日期", point.date), y: .value("Token", Double(point.tokens)))
                            .foregroundStyle(.blue.opacity(0.12).gradient)
                        LineMark(x: .value("日期", point.date), y: .value("Token", Double(point.tokens)))
                            .foregroundStyle(.blue.gradient).lineStyle(.init(lineWidth: 2, lineCap: .round))
                    } else {
                        BarMark(x: .value("日期", point.date), y: .value("Token", Double(point.tokens)))
                            .foregroundStyle(.green.gradient).cornerRadius(2)
                    }
                    if let selected = displayedPoint, selectedDate != nil {
                        RuleMark(x: .value("选择日期", selected.date))
                            .foregroundStyle(.secondary.opacity(0.55)).lineStyle(.init(lineWidth: 1, dash: [3]))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: gridDates) { _ in
                        AxisGridLine(stroke: .init(lineWidth: 0.7)).foregroundStyle(.primary.opacity(0.18))
                    }
                    AxisMarks(values: .automatic(desiredCount: 7)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel(anchor: .topTrailing) {
                                Text(shortDate(date)).font(.caption2).foregroundStyle(panelSecondary).fixedSize()
                                    .rotationEffect(.degrees(-45), anchor: .topTrailing).offset(y: -2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: .init(lineWidth: 0.7)).foregroundStyle(.primary.opacity(0.18))
                        if let tokens = value.as(Double.self) {
                            AxisValueLabel { Text(tokens == 0 ? "0" : String(format: "%.1f", tokens / 100_000_000)).font(.caption2).foregroundStyle(panelSecondary).frame(width: 18) }
                        }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .contentTransition(.opacity)
                .background(TrackpadSwipeHandler(
                    onSwipe: { offset in
                        guard !isSwipeLocked else { return }
                        isSwipeLocked = true
                        setPeriod(period.shifted(by: offset))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { isSwipeLocked = false }
                    }
                ))
                    .frame(height: 120)
                }
                .padding(.bottom, 4)
                Text(periodHint).font(.caption2).foregroundStyle(panelTertiary)
                    .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
            } else {
                ContentUnavailableView(appText("暂无历史用量", "No usage history"), systemImage: "chart.bar.xaxis", description: Text(appText("刷新后仍无数据时，表示当前账号暂未返回 Token 活动。", "No Token activity was returned for this account.")))
                    .frame(height: 210)
            }
        }
        .padding(12)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.primary.opacity(0.16), lineWidth: 1) }
        .onChange(of: period) { _, _ in selectedDate = nil }
    }

    private var displayedPoint: TokenUsagePoint? {
        guard let selectedDate else { return points.last(where: { $0.tokens > 0 }) ?? points.last }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private var periodTitle: String {
        switch period { case .daily: return appText("每日Token活动", "Daily Token activity"); case .weekly: return appText("每周Token活动", "Weekly Token activity"); case .cumulative: return appText("累计趋势", "Cumulative trend") }
    }
    private var periodHint: String {
        switch period { case .daily: return appText("每根柱代表1天，点击图表可查看日期与用量", "Each bar represents one day. Click the chart for details."); case .weekly: return appText("每根柱代表1个自然周", "Each bar represents one calendar week."); case .cumulative: return appText("折线表示历史记录累计到该日期的 Token 数", "The line is cumulative Tokens through each date.") }
    }
    private func dateLabel(_ date: Date) -> String {
        let value = date.formatted(.dateTime.month().day())
        return period == .weekly ? "\(value) 当周" : value
    }
    private func shortDate(_ date: Date) -> String {
        let calendar = Calendar.current
        return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
    }
    private func setPeriod(_ value: TokenUsagePeriod) {
        guard period != value else { return }
        withAnimation(.smooth(duration: 0.24)) { period = value }
    }
    private func periodButton(_ title: String, _ value: TokenUsagePeriod) -> some View {
        Button { setPeriod(value) } label: {
            Text(title).font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 23).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(period == value ? Color.primary.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityValue(period == value ? "已选择" : "")
    }
    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon).font(.caption2).foregroundStyle(panelSecondary).lineLimit(1)
            Text(value).font(.caption.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
    private func compact(_ value: Int64?) -> String {
        guard let value else { return "--" }
        if value >= 100_000_000 { return String(format: "%.1f亿", Double(value) / 100_000_000) }
        if value >= 10_000 { return String(format: "%.1f万", Double(value) / 10_000) }
        return value.formatted()
    }
    private func duration(_ seconds: Int64?) -> String {
        guard let seconds else { return "--" }
        let hours = seconds / 3_600, minutes = seconds / 60 % 60
        return hours > 0 ? "\(hours)时\(minutes)分" : "\(minutes)分钟"
    }
    private func days(_ value: Int64?) -> String { value.map { "\($0) 天" } ?? "--" }
}

private struct TrackpadSwipeHandler: NSViewRepresentable {
    let onSwipe: (Int) -> Void

    func makeNSView(context: Context) -> SwipeTrackingView {
        let view = SwipeTrackingView()
        view.onSwipe = onSwipe
        return view
    }
    func updateNSView(_ view: SwipeTrackingView, context: Context) { view.onSwipe = onSwipe }

    final class SwipeTrackingView: NSView {
        var onSwipe: ((Int) -> Void)?
        private var horizontalDelta: CGFloat = 0
        private var didSwitchPeriod = false
        private var eventMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            guard window != nil else { eventMonitor = nil; return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScroll(event)
                return event
            }
        }
        deinit {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        }
        private func handleScroll(_ event: NSEvent) {
            guard event.window === window, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            if event.phase == .began {
                horizontalDelta = 0
                didSwitchPeriod = false
            }
            if !didSwitchPeriod {
                horizontalDelta += event.scrollingDeltaX
            }
            if !didSwitchPeriod && abs(horizontalDelta) >= 30 {
                onSwipe?(horizontalDelta > 0 ? -1 : 1)
                horizontalDelta = 0
                didSwitchPeriod = true
            }
            if event.phase == .ended || event.phase == .cancelled {
                horizontalDelta = 0
                didSwitchPeriod = false
            }
        }
    }
}

private struct QuotaRow: View {
    let title: String; let window: QuotaWindow; let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(title, systemImage: "calendar")
                        .font(.title3.bold()).foregroundStyle(panelPrimary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(window.remainingPercent, specifier: "%.0f")%")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(progressColor)
                        Text(appText("剩余", "remaining")).font(.subheadline).foregroundStyle(panelSecondary)
                    }
                    Text(verbatim: appText("已用", "Used") + " " + String(format: "%.0f", window.usedPercent) + "%")
                        .font(.subheadline).foregroundStyle(panelSecondary)
                }
                Spacer()
                UsageRing(usedPercent: window.usedPercent, color: progressColor)
            }
            .padding(.bottom, 5)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.1))
                    Capsule().fill(progressColor.gradient).frame(width: geometry.size.width * window.remainingPercent / 100)
                }
            }
            .frame(height: 8)
            Divider().opacity(0.7)
            HStack(spacing: 14) {
                metric(icon: "clock", color: .blue, title: appText("重置于", "Resets"), value: window.resetsAt.formatted(date: .numeric, time: .shortened))
                Divider().frame(height: 34)
                metric(icon: "hourglass", color: .purple, title: appText("剩余时间", "Time left"), value: countdown(window.resetsAt.timeIntervalSince(now)))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.primary.opacity(0.16), lineWidth: 1) }
    }
    private var progressColor: Color { window.remainingPercent < 20 ? .red : window.remainingPercent < 50 ? .orange : .green }
    private func metric(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 23)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(panelSecondary)
                Text(value).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func countdown(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return appText("即将重置", "Resetting soon") }
        let seconds = Int(interval), days = seconds / 86_400, hours = seconds / 3_600 % 24, minutes = seconds / 60 % 60
        return days > 0 ? appText("\(days)天\(hours)小时\(minutes)分", "\(days)d \(hours)h \(minutes)m") : appText("\(hours)小时\(minutes)分", "\(hours)h \(minutes)m")
    }
}

private struct UsageRing: View {
    let usedPercent: Double
    let color: Color
    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.1), lineWidth: 8)
            Circle().trim(from: 0, to: min(1, max(0, usedPercent / 100)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(appText("已用", "Used")).font(.caption2).foregroundStyle(panelSecondary)
                Text("\(usedPercent, specifier: "%.0f")%").font(.title3.bold())
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: 104, height: 104)
        .fixedSize()
    }
}

@MainActor final class PanelController {
    static let shared = PanelController()
    private var panel: NSPanel?
    func toggle(model: QuotaViewModel) { if panel?.isVisible == true { hide() } else { show(model: model) } }
    func show(model: QuotaViewModel) {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 340), styleMask: [.nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
            panel.isFloatingPanel = true; panel.level = .floating; panel.hidesOnDeactivate = false; panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            let content = NSHostingView(rootView: QuotaContentView(model: model)); panel.contentView = content
            panel.setContentSize(content.fittingSize); self.panel = panel
        }
        panel?.center(); panel?.makeKeyAndOrderFront(nil)
    }
    func resizeToFit(animated: Bool = false) {
        guard let panel, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        var frame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: content.fittingSize))
        frame.origin = NSPoint(x: panel.frame.minX, y: panel.frame.maxY - frame.height)
        guard animated else { panel.setFrame(frame, display: true); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            panel.animator().setFrame(frame, display: true)
        }
    }
    func hide() { panel?.orderOut(nil) }
}
