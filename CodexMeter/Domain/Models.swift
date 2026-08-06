import Foundation

struct RateLimitWindowDTO: Codable, Sendable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}

struct RateLimitBucketDTO: Codable, Sendable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindowDTO?
    let secondary: RateLimitWindowDTO?
    let rateLimitReachedType: String?
    let planType: String?

    init(limitId: String? = nil, limitName: String? = nil, primary: RateLimitWindowDTO? = nil, secondary: RateLimitWindowDTO? = nil, rateLimitReachedType: String? = nil, planType: String? = nil) {
        self.limitId = limitId; self.limitName = limitName; self.primary = primary; self.secondary = secondary
        self.rateLimitReachedType = rateLimitReachedType; self.planType = planType
    }
}

struct RateLimitResetCreditsDTO: Codable, Sendable { let availableCount: Int?; let credits: [RateLimitResetCreditDTO]? }
struct RateLimitResetCreditDTO: Codable, Sendable { let id: String; let resetType: String; let status: String; let grantedAt: TimeInterval; let expiresAt: TimeInterval?; let title: String?; let description: String? }

struct RateLimitsResultDTO: Codable, Sendable {
    let rateLimits: RateLimitBucketDTO?
    let rateLimitsByLimitId: [String: RateLimitBucketDTO]?
    let rateLimitResetCredits: RateLimitResetCreditsDTO?
}

struct AccountReadResultDTO: Codable, Sendable {
    let account: AccountInfo?
    let requiresOpenaiAuth: Bool?
}

struct AccountInfo: Codable, Sendable {
    let type: String
    let planType: String?
}

struct AccountTokenUsageDailyBucket: Codable, Sendable {
    let startDate: String
    let tokens: Int64

    var date: Date? {
        let values = startDate.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: values[0], month: values[1], day: values[2]))
    }
}

struct AccountTokenUsageSummary: Codable, Sendable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSec: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?
}

struct AccountTokenUsageResultDTO: Codable, Sendable {
    let summary: AccountTokenUsageSummary
    let dailyUsageBuckets: [AccountTokenUsageDailyBucket]?
}

enum TokenUsagePeriod: CaseIterable { case daily, weekly, cumulative }

struct TokenUsagePoint: Identifiable, Equatable {
    let date: Date
    let tokens: Int64
    var id: Date { date }
}

enum TokenUsageSeries {
    static func points(from buckets: [AccountTokenUsageDailyBucket], period: TokenUsagePeriod, endingAt endDate: Date = .now, dayCount: Int = 14) -> [TokenUsagePoint] {
        let calendar = Calendar(identifier: .iso8601)
        let dated = buckets.compactMap { bucket in bucket.date.map { (calendar.startOfDay(for: $0), bucket.tokens) } }.sorted { $0.0 < $1.0 }
        switch period {
        case .daily:
            let values = Dictionary(dated, uniquingKeysWith: +)
            let end = calendar.startOfDay(for: endDate)
            return (0..<dayCount).compactMap { offset in
                calendar.date(byAdding: .day, value: offset - dayCount + 1, to: end).map { TokenUsagePoint(date: $0, tokens: values[$0, default: 0]) }
            }
        case .weekly:
            var values = [Date: Int64]()
            for (date, tokens) in dated {
                guard let week = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) else { continue }
                values[week, default: 0] += tokens
            }
            return values.map(TokenUsagePoint.init).sorted { $0.date < $1.date }.suffix(8)
        case .cumulative:
            var total: Int64 = 0
            return dated.map { date, tokens in total += tokens; return TokenUsagePoint(date: date, tokens: total) }
        }
    }
}

struct QuotaWindow: Codable, Identifiable, Sendable {
    let id: String
    let durationMinutes: Int
    let usedPercent: Double
    let resetsAt: Date
    var remainingPercent: Double { min(100, max(0, 100 - usedPercent)) }
    var resetInterval: TimeInterval { max(0, resetsAt.timeIntervalSinceNow) }
}

struct CodexQuotaSnapshot: Codable, Sendable {
    let fiveHour: QuotaWindow?
    let weekly: QuotaWindow?
    let otherWindows: [QuotaWindow]
    let planType: String?
    let reachedType: String?
    let tokenUsage: AccountTokenUsageResultDTO?
    let fetchedAt: Date
}

enum QuotaMapper {
    static func snapshot(from result: RateLimitsResultDTO, tokenUsage: AccountTokenUsageResultDTO? = nil, fetchedAt: Date = .now) -> CodexQuotaSnapshot {
        let buckets = result.rateLimitsByLimitId.map { Array($0.values) } ?? (result.rateLimits.map { [$0] } ?? [])
        var seen = Set<String>(), fiveHour: QuotaWindow?, weekly: QuotaWindow?, others = [QuotaWindow]()
        for bucket in buckets {
            for window in [bucket.primary, bucket.secondary].compactMap({ $0 }) {
                guard let duration = window.windowDurationMins, let resetsAt = window.resetsAt else { continue }
                let key = "\(bucket.limitId ?? "unknown")|\(duration)|\(resetsAt)"
                guard seen.insert(key).inserted else { continue }
                let quota = QuotaWindow(id: key, durationMinutes: duration, usedPercent: window.usedPercent, resetsAt: Date(timeIntervalSince1970: resetsAt))
                if abs(duration - 300) <= 5 { fiveHour = fiveHour ?? quota }
                else if abs(duration - 10_080) <= 60 { weekly = weekly ?? quota }
                else { others.append(quota) }
            }
        }
        let representative = buckets.first
        return CodexQuotaSnapshot(fiveHour: fiveHour, weekly: weekly, otherWindows: others, planType: representative?.planType, reachedType: representative?.rateLimitReachedType, tokenUsage: tokenUsage, fetchedAt: fetchedAt)
    }
}

enum ConnectionState: String, Codable, Sendable { case disconnected, connecting, connected }

enum CodexMeterError: LocalizedError, Sendable {
    case codexNotInstalled, notLoggedIn, unsupportedAuthMode, disconnected(String), timeout, invalidResponse(String)
    var errorDescription: String? {
        switch self {
        case .codexNotInstalled: return "未找到 Codex CLI"
        case .notLoggedIn: return "Codex 尚未登录 ChatGPT"
        case .unsupportedAuthMode: return "当前 Codex 使用 API Key"
        case .disconnected(let message): return message
        case .timeout: return "请求超时"
        case .invalidResponse(let message): return message
        }
    }
}
