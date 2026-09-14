using System.Text.Json;
using System.Text.Json.Serialization;

namespace SteamService;

internal sealed class ServiceCommand
{
    [JsonPropertyName("cmd")] public string Command { get; set; } = "";
    [JsonPropertyName("requestId")] public string? RequestId { get; set; }
    [JsonPropertyName("username")] public string? Username { get; set; }
    [JsonPropertyName("password")] public string? Password { get; set; }
    [JsonPropertyName("guardCode")] public string? GuardCode { get; set; }
    [JsonPropertyName("refreshToken")] public string? RefreshToken { get; set; }
    [JsonPropertyName("workshopId")] public ulong? WorkshopId { get; set; }
    [JsonPropertyName("outputRoot")] public string? OutputRoot { get; set; }
}

internal sealed class ProtocolWriter
{
    private readonly object gate = new();
    public void Send(object payload)
    {
        var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions
        {
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });
        lock (gate) { Console.Out.WriteLine(json); Console.Out.Flush(); }
    }
}

internal static class Program
{
    private static readonly ProtocolWriter writer = new();

    private static async Task<int> Main(string[] args)
    {
        // SK0.1 探针模式：独立于产品 NDJSON 服务循环，仅开发验证使用。
        if (args.Length > 0 && args[0] == "probe")
        {
            return await Probe.ProbeHost.RunAsync(args[1..]).ConfigureAwait(false);
        }
        await RunServiceAsync().ConfigureAwait(false);
        return 0;
    }

    private static async Task RunServiceAsync()
    {
        writer.Send(new { v = 1, role = "steam-service", status = "ready" });

        while (true)
        {
            var line = await Console.In.ReadLineAsync().ConfigureAwait(false);
            if (line == null) break;
            if (string.IsNullOrWhiteSpace(line)) continue;

            ServiceCommand? cmd;
            try
            {
                cmd = JsonSerializer.Deserialize<ServiceCommand>(line,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            }
            catch
            {
                writer.Send(new { v = 1, error = "bad-json" });
                continue;
            }
            if (cmd == null || string.IsNullOrEmpty(cmd.Command)) continue;

            switch (cmd.Command)
            {
                case "ping":
                    writer.Send(new { v = 1, eventType = "pong" });
                    break;
                case "shutdown":
                    writer.Send(new { v = 1, eventType = "exited" });
                    return;
                default:
                    writer.Send(new { v = 1, eventType = "error",
                        message = $"unknown command: {cmd.Command}" });
                    break;
            }
        }
    }
}
