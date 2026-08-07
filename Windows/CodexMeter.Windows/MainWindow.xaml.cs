using CodexMeter.Windows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexMeter.Windows;

public sealed partial class MainWindow : Window
{
    private bool isInitializing = true;
    public MainViewModel ViewModel { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        Root.DataContext = ViewModel;
        ViewModel.ThemeChanged += theme => DispatcherQueue.TryEnqueue(() => Root.RequestedTheme = theme);
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        Root.RequestedTheme = ViewModel.ThemeIndex == 1 ? ElementTheme.Light : ElementTheme.Dark;
        ApplyLocalizedUi();
        ApplyPage();
        isInitializing = false;
        await ViewModel.RefreshAsync();
        UpdateHistoryAvailability();
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e)
    {
        await ViewModel.RefreshAsync();
        UpdateHistoryAvailability();
    }

    private void Settings_Click(object sender, RoutedEventArgs e)
    {
        ViewModel.ToggleSettings();
        ApplyPage();
    }

    private void Weekly_Click(object sender, RoutedEventArgs e)
    {
        ViewModel.ShowHistory();
        ApplyPage();
    }

    private void HistoryBack_Click(object sender, RoutedEventArgs e)
    {
        ViewModel.ShowQuota();
        ApplyPage();
    }

    private async void About_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ContentDialog
        {
            Title = "Codex Meter",
            Content = ViewModel.IsEnglish ? "Created by Wang Chenglong · WeChat: amaowangcl" : "版权所有来自王成龙制作，绿泡泡：amaowangcl",
            CloseButtonText = ViewModel.IsEnglish ? "OK" : "确定",
            XamlRoot = Root.XamlRoot
        };
        await dialog.ShowAsync();
    }

    private void Chinese_Click(object sender, RoutedEventArgs e) { ViewModel.IsEnglish = false; ApplyLocalizedUi(); }
    private void English_Click(object sender, RoutedEventArgs e) { ViewModel.IsEnglish = true; ApplyLocalizedUi(); }
    private void Theme_SelectionChanged(object sender, SelectionChangedEventArgs e) { if (!isInitializing) ViewModel.ThemeIndex = ThemePicker.SelectedIndex; }
    private void RefreshInterval_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!isInitializing && RefreshPicker.SelectedItem is ComboBoxItem item && int.TryParse(item.Tag?.ToString(), out var seconds)) ViewModel.RefreshInterval = seconds;
    }
    private void CodexPath_LostFocus(object sender, RoutedEventArgs e) => ViewModel.SaveCodexPath();
    private void HistoryPeriod_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string value } && Enum.TryParse<HistoryPeriod>(value, out var period)) ViewModel.SetHistoryPeriod(period);
        UpdateHistoryAvailability();
    }

    private void ApplyPage()
    {
        QuotaPage.Visibility = ViewModel.IsQuotaVisible ? Visibility.Visible : Visibility.Collapsed;
        HistoryPage.Visibility = ViewModel.IsHistoryVisible ? Visibility.Visible : Visibility.Collapsed;
        SettingsPage.Visibility = ViewModel.IsSettingsVisible ? Visibility.Visible : Visibility.Collapsed;
        UpdateHistoryAvailability();
    }

    private void ApplyLocalizedUi()
    {
        var english = ViewModel.IsEnglish;
        ChineseButton.IsChecked = !english;
        EnglishButton.IsChecked = english;
        DarkThemeItem.Content = english ? "Dark" : "深色";
        LightThemeItem.Content = english ? "Light" : "浅色";
        ThemePicker.SelectedIndex = ViewModel.ThemeIndex;
        var units = english ? "sec" : "秒";
        foreach (var item in RefreshPicker.Items.OfType<ComboBoxItem>()) item.Content = item.Tag?.ToString() == "0" ? (english ? "Manual" : "仅手动") : $"{item.Tag} {units}";
        RefreshPicker.SelectedItem = RefreshPicker.Items.OfType<ComboBoxItem>().FirstOrDefault(item => item.Tag?.ToString() == ViewModel.RefreshInterval.ToString());
        DailyButton.Content = ViewModel.DailyText;
        WeeklyPeriodButton.Content = ViewModel.WeeklyText;
        CumulativeButton.Content = ViewModel.CumulativeText;
        TotalTokensLabel.Text = english ? "Total tokens" : "累计 Token";
        DailyPeakLabel.Text = english ? "Daily peak" : "单日峰值";
        CurrentStreakLabel.Text = english ? "Current streak" : "当前连续";
        LongestStreakLabel.Text = english ? "Longest streak" : "最长连续";
    }

    private void UpdateHistoryAvailability() => NoHistoryText.Visibility = ViewModel.UsageRows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
}
