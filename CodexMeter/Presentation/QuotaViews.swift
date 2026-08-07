import AppKit
import Charts
import SwiftUI

private let panelPrimary = Color.white
private let panelSecondary = Color.white.opacity(0.72)
private let panelTertiary = Color.white.opacity(0.52)

struct QuotaContentView: View {
    @ObservedObject var model: QuotaViewModel
    @State private var showDisconnectedAlert = false
    @State private var showsHistory = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: .blue.opacity(0.35), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Codex Meter").font(.title3.bold())
                    HStack(spacing: 5) {
                        Text("额度概览")
                        if let updatedAt = snapshot?.fetchedAt {
                            Text("·")
                            Text("更新于 \(updatedAt.formatted(date: .omitted, time: .shortened))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(panelSecondary)
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
                            .animation(model.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: model.isRefreshing)
                    }
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
                }
                    .buttonStyle(.plain).foregroundStyle(.blue)
                    .disabled(model.isRefreshing)
                    .help("立即刷新")
                SettingsLink { Image(systemName: "gearshape").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).foregroundStyle(panelPrimary)
                    .background(.primary.opacity(0.055), in: Circle())
                    .overlay { Circle().stroke(.primary.opacity(0.08)) }
                    .help("设置")
            }
            content
        }
        .padding(12)
        .frame(width: 350)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(panelPrimary)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial)
                LinearGradient(colors: [.blue.opacity(0.16), .clear, .orange.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.black.opacity(0.52))
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.26), lineWidth: 1.2) }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onChange(of: showsHistory) { _, _ in
            DispatchQueue.main.async { PanelController.shared.resizeToFit() }
        }
        .onExitCommand { PanelController.shared.hide() }
        .alert("Codex app-server 未连接", isPresented: $showDisconnectedAlert) {
            Button("重试连接") { model.refresh() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("当前无法刷新额度，请检查 Codex 是否可用后重试。")
        }
    }
    private var snapshot: CodexQuotaSnapshot? {
        switch model.state {
        case .loaded(let snapshot), .stale(let snapshot, _): return snapshot
        default: return nil
        }
    }
    @ViewBuilder private var content: some View {
        switch model.state {
        case .loaded(let snapshot): quota(snapshot)
        case .stale(let snapshot, let error): VStack(alignment: .leading, spacing: 12) { quota(snapshot); Label("额度更新失败：\(error)", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
        case .loading: HStack { Spacer(); ProgressView("正在连接 Codex…"); Spacer() }.padding(.vertical, 28)
        case .codexNotInstalled: error("未找到 Codex CLI", "请安装 Codex CLI，或在设置中选择 codex 可执行文件。")
        case .notLoggedIn: error("Codex 尚未登录 ChatGPT", "请先在终端运行 codex 并完成登录。")
        case .unsupportedAuthMode: error("当前 Codex 使用 API Key", "ChatGPT 5 小时和周额度不适用于当前认证模式。")
        case .disconnected(let message): error("Codex app-server 已断开", "正在尝试重新连接。\n\(message)")
        }
    }
    private func quota(_ snapshot: CodexQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fiveHour = snapshot.fiveHour { QuotaRow(title: "5 小时额度", window: fiveHour, now: model.now) }
            if let weekly = snapshot.weekly {
                WeeklyQuotaCard(window: weekly, usage: snapshot.tokenUsage, now: model.now, showsHistory: $showsHistory)
            }
            if snapshot.fiveHour == nil && snapshot.weekly == nil { Text("暂无可识别的额度窗口").foregroundStyle(panelSecondary) }
        }
    }
    private func error(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "exclamationmark.circle.fill").font(.headline).foregroundStyle(.orange)
            Text(detail).font(.subheadline).foregroundStyle(panelSecondary).fixedSize(horizontal: false, vertical: true)
            Button { model.refresh() } label: { Label("重试", systemImage: "arrow.clockwise") }.buttonStyle(.borderedProminent)
        }
        .padding(16).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct WeeklyQuotaCard: View {
    let window: QuotaWindow
    let usage: AccountTokenUsageResultDTO?
    let now: Date
    @Binding var showsHistory: Bool

    var body: some View {
        ZStack {
            if showsHistory {
                TokenHistoryView(usage: usage, now: now) {
                    withAnimation(.easeInOut(duration: 0.2)) { showsHistory = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                QuotaRow(title: "周额度", window: window, now: now)
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showsHistory = true } }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("周额度，点击查看历史用量")
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
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

    private var buckets: [AccountTokenUsageDailyBucket] { usage?.dailyUsageBuckets ?? [] }
    private var points: [TokenUsagePoint] { TokenUsageSeries.points(from: buckets, period: period, endingAt: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("历史用量", systemImage: "chart.xyaxis.line").font(.headline)
                Spacer()
                Button(action: close) {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(0.055), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).help("返回周额度")
            }
            if let summary = usage?.summary {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    metric("累计 Token", compact(summary.lifetimeTokens), "sum")
                    metric("单日峰值", compact(summary.peakDailyTokens), "waveform.path.ecg")
                    metric("最长聊天", duration(summary.longestRunningTurnSec), "timer")
                    metric("当前连续", days(summary.currentStreakDays), "flame")
                    metric("最长连续", days(summary.longestStreakDays), "trophy")
                }

                HStack(spacing: 2) {
                    periodButton("每日", .daily)
                    periodButton("每周", .weekly)
                    periodButton("累计", .cumulative)
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
                    Text("亿").font(.caption2).foregroundStyle(panelSecondary).offset(x: -31, y: -8).frame(width: 28, height: 8)
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
                    AxisMarks(values: .automatic(desiredCount: 7)) { value in
                        AxisGridLine(stroke: .init(lineWidth: 0.7)).foregroundStyle(.primary.opacity(0.18))
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
                            AxisValueLabel { Text(tokens == 0 ? "0" : String(format: "%.1f", tokens / 100_000_000)).font(.caption2).foregroundStyle(panelSecondary).frame(width: 28).offset(x: -31) }
                        }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .contentTransition(.opacity)
                .background(TrackpadSwipeHandler { offset in setPeriod(period.shifted(by: offset)) })
                    .frame(height: 120)
                }
                .padding(.bottom, 4)
                Text(periodHint).font(.caption2).foregroundStyle(panelTertiary)
                    .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
            } else {
                ContentUnavailableView("暂无历史用量", systemImage: "chart.bar.xaxis", description: Text("刷新后仍无数据时，表示当前账号暂未返回 Token 活动。"))
                    .frame(height: 210)
            }
        }
        .padding(12)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1) }
        .onChange(of: period) { _, _ in selectedDate = nil }
    }

    private var displayedPoint: TokenUsagePoint? {
        guard let selectedDate else { return points.last(where: { $0.tokens > 0 }) ?? points.last }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private var periodTitle: String {
        switch period { case .daily: return "每日 Token 活动"; case .weekly: return "每周 Token 活动"; case .cumulative: return "累计趋势" }
    }
    private var periodHint: String {
        switch period { case .daily: return "每根柱代表 1 天，点击图表可查看日期与用量"; case .weekly: return "每根柱代表 1 个自然周"; case .cumulative: return "折线表示历史记录累计到该日期的 Token 数" }
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
            Text(title).font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 27).contentShape(Rectangle())
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
                        Text("剩余").font(.subheadline).foregroundStyle(panelSecondary)
                    }
                    Text("已用 \(window.usedPercent, specifier: "%.0f")%")
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
                metric(icon: "clock", color: .blue, title: "重置于", value: window.resetsAt.formatted(date: .numeric, time: .shortened))
                Divider().frame(height: 34)
                metric(icon: "hourglass", color: .purple, title: "剩余时间", value: countdown(window.resetsAt.timeIntervalSince(now)))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1) }
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
        guard interval > 0 else { return "即将重置" }
        let seconds = Int(interval), days = seconds / 86_400, hours = seconds / 3_600 % 24, minutes = seconds / 60 % 60
        return days > 0 ? "\(days) 天 \(hours) 小时 \(minutes) 分" : "\(hours) 小时 \(minutes) 分"
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
                Text("已用").font(.caption2).foregroundStyle(panelSecondary)
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
    func resizeToFit() {
        guard let panel, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(content.fittingSize)
        panel.setFrameTopLeftPoint(topLeft)
    }
    func hide() { panel?.orderOut(nil) }
}
