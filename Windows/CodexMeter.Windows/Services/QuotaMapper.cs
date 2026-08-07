using System.Text.Json;
using CodexMeter.Windows.Models;

namespace CodexMeter.Windows.Services;

public static class QuotaMapper
{
    public static QuotaSnapshot FromRateLimits(JsonElement result)
    {
        var buckets = new List<JsonElement>();
        if (result.TryGetProperty("rateLimitsByLimitId", out var byLimitId) && byLimitId.ValueKind == JsonValueKind.Object)
        {
            buckets.AddRange(byLimitId.EnumerateObject().Select(property => property.Value));
        }
        else if (result.TryGetProperty("rateLimits", out var rateLimits) && rateLimits.ValueKind == JsonValueKind.Object)
        {
            buckets.Add(rateLimits);
        }

        QuotaWindow? fiveHour = null;
        QuotaWindow? weekly = null;
        string? planType = null;
        foreach (var bucket in buckets)
        {
            if (planType is null && bucket.TryGetProperty("planType", out var plan)) planType = plan.GetString();
            foreach (var name in new[] { "primary", "secondary" })
            {
                if (!bucket.TryGetProperty(name, out var window) || window.ValueKind != JsonValueKind.Object) continue;
                if (!window.TryGetProperty("windowDurationMins", out var duration) || !duration.TryGetInt32(out var minutes)) continue;
                if (!window.TryGetProperty("usedPercent", out var used) || !used.TryGetDouble(out var usedPercent)) continue;
                if (!window.TryGetProperty("resetsAt", out var reset) || !reset.TryGetDouble(out var seconds)) continue;
                var quota = new QuotaWindow(usedPercent, DateTimeOffset.FromUnixTimeSeconds((long)seconds));
                if (Math.Abs(minutes - 300) <= 5) fiveHour ??= quota;
                if (Math.Abs(minutes - 10_080) <= 60) weekly ??= quota;
            }
        }
        return new QuotaSnapshot(fiveHour, weekly, planType);
    }
}
