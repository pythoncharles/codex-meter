namespace CodexMeter.Windows.Models;

public sealed record QuotaWindow(double UsedPercent, DateTimeOffset ResetsAt)
{
    public double RemainingPercent => Math.Clamp(100 - UsedPercent, 0, 100);
}

public sealed record QuotaSnapshot(QuotaWindow? FiveHour, QuotaWindow? Weekly, string? PlanType);
