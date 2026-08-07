using System.Text.Json;
using CodexMeter.Windows.Models;
using CodexMeter.Windows.Services;
using Xunit;

namespace CodexMeter.Windows.Tests;

public sealed class QuotaMapperTests
{
    [Fact]
    public void MapsFiveHourAndWeeklyWindows()
    {
        using var document = JsonDocument.Parse("""{"rateLimits":{"planType":"plus","primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":2000000000}}}""");

        var snapshot = QuotaMapper.FromRateLimits(document.RootElement);

        Assert.Equal("plus", snapshot.PlanType);
        Assert.Equal(80, snapshot.FiveHour?.RemainingPercent);
        Assert.Equal(60, snapshot.Weekly?.RemainingPercent);
    }

    [Fact]
    public void ClampsRemainingPercentage()
    {
        var above = new QuotaWindow(120, DateTimeOffset.UtcNow);
        var below = new QuotaWindow(-20, DateTimeOffset.UtcNow);

        Assert.Equal(0, above.RemainingPercent);
        Assert.Equal(100, below.RemainingPercent);
    }
}
