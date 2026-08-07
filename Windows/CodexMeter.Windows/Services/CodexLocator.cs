namespace CodexMeter.Windows.Services;

public static class CodexLocator
{
    public static string? Locate(string? customPath)
    {
        if (!string.IsNullOrWhiteSpace(customPath) && File.Exists(customPath)) return customPath;
        var pathEntries = (Environment.GetEnvironmentVariable("PATH") ?? string.Empty).Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);
        foreach (var folder in pathEntries)
        {
            foreach (var name in new[] { "codex.exe", "codex.cmd", "codex" })
            {
                var candidate = Path.Combine(folder, name);
                if (File.Exists(candidate)) return candidate;
            }
        }
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        foreach (var candidate in new[]
        {
            Path.Combine(localAppData, "Programs", "Codex", "codex.exe"),
            Path.Combine(localAppData, "Programs", "ChatGPT", "resources", "codex.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "ChatGPT", "resources", "codex.exe")
        })
        {
            if (File.Exists(candidate)) return candidate;
        }
        return null;
    }
}
