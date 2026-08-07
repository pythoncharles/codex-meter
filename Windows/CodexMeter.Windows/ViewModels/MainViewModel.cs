using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using CodexMeter.Windows.Models;
using CodexMeter.Windows.Services;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.Storage;

namespace CodexMeter.Windows.ViewModels;

public enum DetailPage { Quota, History, Settings }
public enum HistoryPeriod { Daily, Weekly, Cumulative }

public sealed record UsageRow(string Date, string Tokens);

public sealed class MainViewModel : INotifyPropertyChanged
{
    private const string CodexPathKey = "customCodexPath";
    private const string AutoRefreshKey = "autoRefresh";
    private const string RefreshIntervalKey = "refreshInterval";
    private const string LanguageKey = "appLanguage";
    private const string ThemeKey = "appTheme";
    private const string OpacityKey = "panelBackgroundOpacity";
    private readonly ApplicationDataContainer storage = ApplicationData.Current.LocalSettings;
    private CancellationTokenSource? autoRefreshCancellation;
    private string codexPath;
    private string statusText = "正在准备连接 Codex…";
    private string fiveHourRemaining = "--";
    private string weeklyRemaining = "--";
    private string fiveHourDetail = "等待刷新";
    private string weeklyDetail = "等待刷新";
    private double fiveHourRemainingValue;
    private double weeklyRemainingValue;
    private bool isRefreshing;
    private DetailPage detailPage;
    private DetailPage previousDetailPage;
    private HistoryPeriod historyPeriod;
    private QuotaSnapshot? snapshot;

    public MainViewModel()
    {
        codexPath = storage.Values[CodexPathKey] as string ?? string.Empty;
        ConfigureAutoRefresh();
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public event Action<ElementTheme>? ThemeChanged;

    public ObservableCollection<UsageRow> UsageRows { get; } = [];
    public string CodexPath { get => codexPath; set => SetField(ref codexPath, value); }
    public string StatusText { get => statusText; private set => SetField(ref statusText, value); }
    public string FiveHourRemaining { get => fiveHourRemaining; private set => SetField(ref fiveHourRemaining, value); }
    public string WeeklyRemaining { get => weeklyRemaining; private set => SetField(ref weeklyRemaining, value); }
    public string FiveHourDetail { get => fiveHourDetail; private set => SetField(ref fiveHourDetail, value); }
    public string WeeklyDetail { get => weeklyDetail; private set => SetField(ref weeklyDetail, value); }
    public double FiveHourRemainingValue { get => fiveHourRemainingValue; private set => SetField(ref fiveHourRemainingValue, value); }
    public double WeeklyRemainingValue { get => weeklyRemainingValue; private set => SetField(ref weeklyRemainingValue, value); }
    public bool IsRefreshing { get => isRefreshing; private set => SetField(ref isRefreshing, value); }
    public DetailPage DetailPage { get => detailPage; private set => SetField(ref detailPage, value); }
    public HistoryPeriod HistoryPeriod { get => historyPeriod; private set => SetField(ref historyPeriod, value); }
    public bool IsQuotaVisible => DetailPage == DetailPage.Quota;
    public bool IsHistoryVisible => DetailPage == DetailPage.History;
    public bool IsSettingsVisible => DetailPage == DetailPage.Settings;
    public bool IsSettings => IsSettingsVisible;
    public bool IsEnglish { get => (storage.Values[LanguageKey] as string) == "en"; set { storage.Values[LanguageKey] = value ? "en" : "zh-Hans"; RefreshLocalizedText(); } }
    public int ThemeIndex { get => (storage.Values[ThemeKey] as string) == "light" ? 1 : 0; set { storage.Values[ThemeKey] = value == 1 ? "light" : "dark"; OnPropertyChanged(); OnPropertyChanged(nameof(PanelBackground)); ThemeChanged?.Invoke(value == 1 ? ElementTheme.Light : ElementTheme.Dark); } }
    public double BackgroundOpacity { get => storage.Values[OpacityKey] as double? ?? 0.52; set { storage.Values[OpacityKey] = value; OnPropertyChanged(); OnPropertyChanged(nameof(PanelBackground)); OnPropertyChanged(nameof(BackgroundOpacityText)); } }
    public bool AutoRefresh { get => storage.Values[AutoRefreshKey] as bool? ?? true; set { storage.Values[AutoRefreshKey] = value; OnPropertyChanged(); ConfigureAutoRefresh(); } }
    public int RefreshInterval { get => storage.Values[RefreshIntervalKey] as int? ?? 300; set { storage.Values[RefreshIntervalKey] = value; OnPropertyChanged(); ConfigureAutoRefresh(); } }
    public Brush PanelBackground => ThemeIndex == 1
        ? new SolidColorBrush(ColorHelper.FromArgb((byte)(BackgroundOpacity * 255), 255, 255, 255))
        : new SolidColorBrush(ColorHelper.FromArgb((byte)(BackgroundOpacity * 255), 28, 35, 32));
    public string BackgroundOpacityText => $"{Text("背景", "Opacity")} {(int)(BackgroundOpacity * 100)}%";
    public string HeaderSubtitle => snapshot is null ? Text("额度概览", "Quota") : $"{Text("额度概览 · 更新于", "Quota · Updated")} {DateTime.Now:t}";
    public string PlanText => snapshot?.PlanType?.ToUpperInvariant() ?? string.Empty;
    public string SettingsGlyph => IsSettings ? "\uE72B" : "\uE713";
    public string SettingsTip => IsSettings ? Text("返回上一页", "Back") : Text("设置", "Settings");
    public string RefreshTip => Text("立即刷新", "Refresh now");
    public string FiveHourTitle => Text("5 小时额度", "5-hour quota");
    public string WeeklyTitle => Text("周额度", "Weekly quota");
    public string HistoryTitle => Text("历史用量", "Usage history");
    public string SettingsTitle => Text("设置", "Settings");
    public string ThemeLabel => Text("主题", "Theme");
    public string AutoRefreshLabel => Text("自动刷新", "Auto Refresh");
    public string CodexPathLabel => Text("Codex 路径", "Codex Path");
    public string DailyText => Text("每日", "Daily");
    public string WeeklyText => Text("每周", "Weekly");
    public string CumulativeText => Text("累计", "Total");
    public string NoHistoryText => Text("暂无历史用量", "No usage history");
    public string LifetimeTokens => FormatMetric(snapshot?.Usage?.Summary?.LifetimeTokens);
    public string PeakDailyTokens => FormatMetric(snapshot?.Usage?.Summary?.PeakDailyTokens);
    public string CurrentStreak => FormatDays(snapshot?.Usage?.Summary?.CurrentStreakDays);
    public string LongestStreak => FormatDays(snapshot?.Usage?.Summary?.LongestStreakDays);

    public async Task RefreshAsync()
    {
        if (IsRefreshing) return;
        IsRefreshing = true;
        try
        {
            StatusText = Text("正在读取 Codex 额度…", "Reading Codex quota…");
            var executable = CodexLocator.Locate(CodexPath) ?? throw new InvalidOperationException(Text("未找到 Codex。请安装 Codex CLI，或填写 codex.exe 路径。", "Codex was not found. Install Codex CLI or provide codex.exe."));
            if (string.IsNullOrWhiteSpace(CodexPath)) { CodexPath = executable; SaveCodexPath(); }
            snapshot = await new CodexClient().ReadQuotaAsync(executable, CancellationToken.None);
            Apply(snapshot);
            StatusText = Text("已更新", "Updated") + (snapshot.PlanType is null ? string.Empty : $" · {snapshot.PlanType.ToUpperInvariant()}");
        }
        catch (Exception error)
        {
            StatusText = error.Message;
        }
        finally
        {
            IsRefreshing = false;
        }
    }

    public void ShowHistory() { DetailPage = DetailPage.History; RefreshDetailPage(); }
    public void ShowQuota() { DetailPage = DetailPage.Quota; RefreshDetailPage(); }
    public void SetHistoryPeriod(HistoryPeriod value) { HistoryPeriod = value; BuildUsageRows(); }
    public void ToggleSettings()
    {
        if (IsSettings) DetailPage = previousDetailPage;
        else { previousDetailPage = DetailPage; DetailPage = DetailPage.Settings; }
        RefreshDetailPage();
    }
    public void SaveCodexPath() => storage.Values[CodexPathKey] = CodexPath;

    private void Apply(QuotaSnapshot value)
    {
        ApplyWindow(value.FiveHour, result => FiveHourRemaining = result, result => FiveHourRemainingValue = result, result => FiveHourDetail = result);
        ApplyWindow(value.Weekly, result => WeeklyRemaining = result, result => WeeklyRemainingValue = result, result => WeeklyDetail = result);
        OnPropertyChanged(nameof(HeaderSubtitle));
        OnPropertyChanged(nameof(PlanText));
        OnPropertyChanged(nameof(LifetimeTokens));
        OnPropertyChanged(nameof(PeakDailyTokens));
        OnPropertyChanged(nameof(CurrentStreak));
        OnPropertyChanged(nameof(LongestStreak));
        BuildUsageRows();
    }

    private void ApplyWindow(QuotaWindow? window, Action<string> setRemaining, Action<double> setValue, Action<string> setDetail)
    {
        if (window is null) { setRemaining("--"); setValue(0); setDetail(Text("当前账号未返回该额度窗口", "This quota window was not returned.")); return; }
        setRemaining($"{window.RemainingPercent:0}%");
        setValue(window.RemainingPercent);
        setDetail($"{Text("已用", "Used")} {window.UsedPercent:0}% · {Text("重置于", "Resets")} {window.ResetsAt.LocalDateTime:g}");
    }

    private void BuildUsageRows()
    {
        UsageRows.Clear();
        var buckets = snapshot?.Usage?.DailyBuckets.OrderBy(value => value.Date).ToList() ?? [];
        if (HistoryPeriod == HistoryPeriod.Weekly)
        {
            foreach (var group in buckets.GroupBy(value => $"{value.Date.Year}-{ISOWeek.GetWeekOfYear(value.Date.ToDateTime(TimeOnly.MinValue)):00}").TakeLast(8))
                UsageRows.Add(new UsageRow(group.First().Date.ToString("M/d"), FormatMetric(group.Sum(value => value.Tokens))));
            return;
        }
        long total = 0;
        foreach (var value in (HistoryPeriod == HistoryPeriod.Daily ? buckets.TakeLast(14) : buckets))
        {
            total += value.Tokens;
            UsageRows.Add(new UsageRow(value.Date.ToString("M/d"), FormatMetric(HistoryPeriod == HistoryPeriod.Cumulative ? total : value.Tokens)));
        }
    }

    private void ConfigureAutoRefresh()
    {
        autoRefreshCancellation?.Cancel();
        if (!AutoRefresh || RefreshInterval <= 0) return;
        var cancellation = autoRefreshCancellation = new CancellationTokenSource();
        _ = AutoRefreshAsync(cancellation.Token);
    }

    private async Task AutoRefreshAsync(CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                await Task.Delay(TimeSpan.FromSeconds(RefreshInterval), cancellationToken);
                if (!cancellationToken.IsCancellationRequested) await RefreshAsync();
            }
        }
        catch (OperationCanceledException) { }
    }

    private void RefreshDetailPage()
    {
        OnPropertyChanged(nameof(IsQuotaVisible));
        OnPropertyChanged(nameof(IsHistoryVisible));
        OnPropertyChanged(nameof(IsSettingsVisible));
        OnPropertyChanged(nameof(IsSettings));
        OnPropertyChanged(nameof(SettingsGlyph));
        OnPropertyChanged(nameof(SettingsTip));
    }

    private void RefreshLocalizedText()
    {
        OnPropertyChanged(nameof(IsEnglish));
        foreach (var property in new[] { nameof(StatusText), nameof(HeaderSubtitle), nameof(RefreshTip), nameof(SettingsTip), nameof(FiveHourTitle), nameof(WeeklyTitle), nameof(HistoryTitle), nameof(SettingsTitle), nameof(ThemeLabel), nameof(BackgroundOpacityText), nameof(AutoRefreshLabel), nameof(CodexPathLabel), nameof(DailyText), nameof(WeeklyText), nameof(CumulativeText), nameof(NoHistoryText), nameof(FiveHourDetail), nameof(WeeklyDetail), nameof(CurrentStreak), nameof(LongestStreak) }) OnPropertyChanged(property);
        BuildUsageRows();
    }

    private string Text(string chinese, string english) => IsEnglish ? english : chinese;
    private string FormatMetric(long? value) => value is null ? "--" : FormatMetric(value.Value);
    private static string FormatMetric(long value) => value >= 100_000_000 ? $"{value / 100_000_000d:0.0}亿" : value >= 10_000 ? $"{value / 10_000d:0.0}万" : value.ToString("N0");
    private string FormatDays(long? value) => value is null ? "--" : IsEnglish ? $"{value} days" : $"{value} 天";
    private void SetField<T>(ref T field, T value, [CallerMemberName] string? name = null) { if (EqualityComparer<T>.Default.Equals(field, value)) return; field = value; OnPropertyChanged(name); }
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
