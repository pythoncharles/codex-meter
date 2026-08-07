using CodexMeter.Windows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexMeter.Windows;

public sealed partial class MainWindow : Window
{
    public MainViewModel ViewModel { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        Root.DataContext = ViewModel;
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        await ViewModel.RefreshAsync();
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e)
    {
        await ViewModel.RefreshAsync();
    }

    private async void About_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ContentDialog
        {
            Title = "关于Codex Meter",
            Content = "版权所有来自王成龙制作，绿泡泡：amaowangcl",
            CloseButtonText = "确定",
            XamlRoot = Root.XamlRoot
        };
        await dialog.ShowAsync();
    }

    private void CodexPath_LostFocus(object sender, RoutedEventArgs e)
    {
        ViewModel.SaveCodexPath();
    }
}
