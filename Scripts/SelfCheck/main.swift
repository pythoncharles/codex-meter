import Foundation

func decodeJSON(_ messages: [Data]) -> [[String: Any]] {
    messages.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
}

var decoder = JSONLStreamDecoder(maximumLineBytes: 64)
assert(decoder.append(Data("{\"文本\":\"中".utf8)).isEmpty)
assert(decoder.append(Data("文\"}".utf8)).isEmpty)
let split = decoder.append(Data("\n".utf8))
assert(decodeJSON(split).first?["文本"] as? String == "中文")

let mixed = decoder.append(Data("\n{bad}\n{\"ok\":1}\n{\"ok\":2}\n".utf8))
assert(mixed.count == 3)
assert(decodeJSON(mixed).count == 2)
assert(decoder.append(Data(String(repeating: "x", count: 65).utf8)).isEmpty)

let fixture = Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000000},"secondary":null,"planType":"pro"},"rateLimitsByLimitId":null,"rateLimitResetCredits":null}"#.utf8)
let result = try JSONDecoder().decode(RateLimitsResultDTO.self, from: fixture)
let snapshot = QuotaMapper.snapshot(from: result)
assert(snapshot.fiveHour == nil)
assert(snapshot.weekly?.remainingPercent == 80)

let low = QuotaWindow(id: "low", durationMinutes: 60, usedPercent: -1, resetsAt: .now)
let high = QuotaWindow(id: "high", durationMinutes: 60, usedPercent: 101, resetsAt: .now)
assert(low.remainingPercent == 100 && high.remainingPercent == 0)

let usageFixture = Data(#"{"summary":{"lifetimeTokens":150,"peakDailyTokens":100,"longestRunningTurnSec":90,"currentStreakDays":2,"longestStreakDays":4},"dailyUsageBuckets":[{"startDate":"2026-06-18","tokens":100},{"startDate":"2026-06-19","tokens":50}]}"#.utf8)
let usage = try JSONDecoder().decode(AccountTokenUsageResultDTO.self, from: usageFixture)
let usageEnd = Calendar(identifier: .iso8601).date(from: DateComponents(year: 2026, month: 6, day: 19))!
assert(TokenUsageSeries.points(from: usage.dailyUsageBuckets!, period: .daily, endingAt: usageEnd, dayCount: 3).map(\.tokens) == [0, 100, 50])
assert(TokenUsageSeries.points(from: usage.dailyUsageBuckets!, period: .weekly).last?.tokens == 150)
assert(TokenUsageSeries.points(from: usage.dailyUsageBuckets!, period: .cumulative).map(\.tokens) == [100, 150])
let located = try CodexBinaryLocator().locate()
assert(FileManager.default.isExecutableFile(atPath: located.url.path))
print("JSONL、7 天额度映射、Token 历史聚合、剩余百分比边界：PASS")
