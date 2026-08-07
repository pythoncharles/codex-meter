namespace CodexMeter.Windows.Models;

public sealed record QuotaWindow(double UsedPercent, DateTimeOffset ResetsAt)
{
    public double RemainingPercent => Math.Clamp(100 - UsedPercent, 0, 100);
}

public sealed record TokenUsageBucket(DateOnly Date, long Tokens);

public sealed record TokenUsageSummary(long? LifetimeTokens, long? PeakDailyTokens, long? LongestRunningTurnSec, long? CurrentStreakDays, long? LongestStreakDays);

public sealed record TokenUsage(TokenUsageSummary? Summary, IReadOnlyList<TokenUsageBucket> DailyBuckets);

public sealed record QuotaSnapshot(QuotaWindow? FiveHour, QuotaWindow? Weekly, string? PlanType, TokenUsage? Usage = null);
