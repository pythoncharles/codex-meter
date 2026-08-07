using System.ComponentModel;
using System.Runtime.CompilerServices;
using CodexMeter.Windows.Models;
using CodexMeter.Windows.Services;
using Windows.Storage;

namespace CodexMeter.Windows.ViewModels;

public sealed class MainViewModel : INotifyPropertyChanged
{
    private const string CodexPathKey = "customCodexPath";
    private string codexPath = ApplicationData.Current.LocalSettings.Values[CodexPathKey] as string ?? string.Empty;
    private string statusText = "正在准备连接 Codex…";
    private string fiveHourRemaining = "--";
    private string weeklyRemaining = "--";
    private string fiveHourDetail = "等待刷新";
    private string weeklyDetail = "等待刷新";
    private double fiveHourRemainingValue;
    private double weeklyRemainingValue;

    public event PropertyChangedEventHandler? PropertyChanged;
    public string CodexPath { get => codexPath; set => SetField(ref codexPath, value); }
    public string StatusText { get => statusText; private set => SetField(ref statusText, value); }
    public string FiveHourRemaining { get => fiveHourRemaining; private set => SetField(ref fiveHourRemaining, value); }
    public string WeeklyRemaining { get => weeklyRemaining; private set => SetField(ref weeklyRemaining, value); }
    public string FiveHourDetail { get => fiveHourDetail; private set => SetField(ref fiveHourDetail, value); }
    public string WeeklyDetail { get => weeklyDetail; private set => SetField(ref weeklyDetail, value); }
    public double FiveHourRemainingValue { get => fiveHourRemainingValue; private set => SetField(ref fiveHourRemainingValue, value); }
    public double WeeklyRemainingValue { get => weeklyRemainingValue; private set => SetField(ref weeklyRemainingValue, value); }

    public async Task RefreshAsync()
    {
        try
        {
            StatusText = "正在读取 Codex 额度…";
            var executable = CodexLocator.Locate(CodexPath) ?? throw new InvalidOperationException("未找到 Codex。请安装 Codex CLI，或填写 codex.exe 路径。");
            if (string.IsNullOrWhiteSpace(CodexPath)) CodexPath = executable;
            var snapshot = await new CodexClient().ReadQuotaAsync(executable, CancellationToken.None);
            Apply(snapshot);
            StatusText = $"已更新{(snapshot.PlanType is null ? string.Empty : $" · {snapshot.PlanType.ToUpperInvariant()}")}";
        }
        catch (Exception error)
        {
            StatusText = error.Message;
        }
    }

    public void SaveCodexPath() => ApplicationData.Current.LocalSettings.Values[CodexPathKey] = CodexPath;

    private void Apply(QuotaSnapshot snapshot)
    {
        ApplyWindow(snapshot.FiveHour, value => FiveHourRemaining = value, value => FiveHourRemainingValue = value, value => FiveHourDetail = value);
        ApplyWindow(snapshot.Weekly, value => WeeklyRemaining = value, value => WeeklyRemainingValue = value, value => WeeklyDetail = value);
    }

    private static void ApplyWindow(QuotaWindow? window, Action<string> setRemaining, Action<double> setValue, Action<string> setDetail)
    {
        if (window is null)
        {
            setRemaining("--");
            setValue(0);
            setDetail("当前账号未返回该额度窗口");
            return;
        }
        setRemaining($"{window.RemainingPercent:0}%");
        setValue(window.RemainingPercent);
        setDetail($"已用 {window.UsedPercent:0}% · 重置于 {window.ResetsAt.LocalDateTime:g}");
    }

    private void SetField<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
