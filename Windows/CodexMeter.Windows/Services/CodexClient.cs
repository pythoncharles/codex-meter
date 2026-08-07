using System.Diagnostics;
using System.Text.Json;
using CodexMeter.Windows.Models;

namespace CodexMeter.Windows.Services;

public sealed class CodexClient
{
    public async Task<QuotaSnapshot> ReadQuotaAsync(string executablePath, CancellationToken cancellationToken)
    {
        using var process = Process.Start(new ProcessStartInfo(executablePath)
        {
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            ArgumentList = { "app-server", "--listen", "stdio://" }
        }) ?? throw new InvalidOperationException("无法启动 Codex app-server。");

        try
        {
            await SendAsync(process, "initialize", 1, new { clientInfo = new { name = "codex_meter_windows", title = "Codex Meter", version = "0.1.0" } }, cancellationToken);
            await ReadResultAsync(process, 1, cancellationToken);
            await SendNotificationAsync(process, "initialized", cancellationToken);
            await SendAsync<object?>(process, "account/rateLimits/read", 2, null, cancellationToken);
            var snapshot = QuotaMapper.FromRateLimits(await ReadResultAsync(process, 2, cancellationToken));
            TokenUsage? usage = null;
            try
            {
                await SendAsync<object?>(process, "account/usage/read", 3, null, cancellationToken);
                usage = QuotaMapper.FromUsage(await ReadResultAsync(process, 3, cancellationToken));
            }
            catch (InvalidOperationException)
            {
                // 历史用量不是所有 Codex 版本都支持，额度读取仍可正常显示。
            }
            return snapshot with { Usage = usage };
        }
        finally
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
        }
    }

    private static async Task SendAsync<T>(Process process, string method, int id, T parameters, CancellationToken cancellationToken)
    {
        await process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(new { method, id, @params = parameters }, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }).AsMemory(), cancellationToken);
        await process.StandardInput.FlushAsync(cancellationToken);
    }

    private static async Task SendNotificationAsync(Process process, string method, CancellationToken cancellationToken)
    {
        await process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(new { method }).AsMemory(), cancellationToken);
        await process.StandardInput.FlushAsync(cancellationToken);
    }

    private static async Task<JsonElement> ReadResultAsync(Process process, int requestId, CancellationToken cancellationToken)
    {
        while (await process.StandardOutput.ReadLineAsync(cancellationToken) is { } line)
        {
            using var document = JsonDocument.Parse(line);
            var root = document.RootElement;
            if (!root.TryGetProperty("id", out var id) || !id.TryGetInt32(out var value) || value != requestId) continue;
            if (root.TryGetProperty("error", out var error)) throw new InvalidOperationException(error.GetProperty("message").GetString() ?? "Codex app-server 返回错误。");
            return root.GetProperty("result").Clone();
        }
        throw new InvalidOperationException("Codex app-server 已断开。");
    }
}
