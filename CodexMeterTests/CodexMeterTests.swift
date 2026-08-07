import XCTest
@testable import CodexMeter

final class CodexMeterTests: XCTestCase {
    func testJSONLSplitAndMultipleMessages() {
        var decoder = JSONLStreamDecoder()
        XCTAssertEqual(decoder.append(Data("{\"a\":1}".utf8)), [])
        XCTAssertEqual(decoder.append(Data("\n{\"b\":2}\n\n".utf8)).count, 2)
    }

    func testWeeklyWindowWithoutFiveHourWindow() throws {
        let json = """{"rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000000},"secondary":null,"planType":"pro"},"rateLimitsByLimitId":null,"rateLimitResetCredits":null}"""
        let result = try JSONDecoder().decode(RateLimitsResultDTO.self, from: Data(json.utf8))
        let snapshot = QuotaMapper.snapshot(from: result)
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertEqual(snapshot.weekly?.remainingPercent, 80)
    }

    func testRemainingPercentIsClamped() {
        let above = QuotaWindow(id: "1", durationMinutes: 60, usedPercent: 120, resetsAt: .now)
        let below = QuotaWindow(id: "2", durationMinutes: 60, usedPercent: -20, resetsAt: .now)
        XCTAssertEqual(above.remainingPercent, 0); XCTAssertEqual(below.remainingPercent, 100)
    }

    func testTokenUsageDecodeAndSeries() throws {
        let json = #"{"summary":{"lifetimeTokens":150,"peakDailyTokens":100,"longestRunningTurnSec":90,"currentStreakDays":2,"longestStreakDays":4},"dailyUsageBuckets":[{"startDate":"2026-06-18","tokens":100},{"startDate":"2026-06-19","tokens":50}]}"#
        let usage = try JSONDecoder().decode(AccountTokenUsageResultDTO.self, from: Data(json.utf8))
        let end = Calendar(identifier: .iso8601).date(from: DateComponents(year: 2026, month: 6, day: 19))!
        XCTAssertEqual(usage.summary.lifetimeTokens, 150)
        XCTAssertEqual(TokenUsageSeries.points(from: usage.dailyUsageBuckets!, period: .daily, endingAt: end, dayCount: 3).map(\.tokens), [0, 100, 50])
        XCTAssertEqual(TokenUsageSeries.points(from: usage.dailyUsageBuckets!, period: .weekly).last?.tokens, 150)
        XCTAssertEqual(TokenUsageSeries.points(from: usage.dailyUsageBuckets!, period: .cumulative).map(\.tokens), [100, 150])
    }

    func testTokenUsagePeriodSwitchesInBothDirections() {
        XCTAssertEqual(TokenUsagePeriod.daily.shifted(by: 1), .weekly)
        XCTAssertEqual(TokenUsagePeriod.daily.shifted(by: -1), .cumulative)
    }

}
