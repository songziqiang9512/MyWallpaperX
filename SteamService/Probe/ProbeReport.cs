using System.Collections.Concurrent;

namespace SteamService.Probe;

// stdout 只输出机器可读 JSON 行；提示与交互一律走 stderr。
internal static class ProbeReport
{
    private static readonly object Gate = new();

    public static void Emit(object payload)
    {
        var json = System.Text.Json.JsonSerializer.Serialize(payload, ReportOptions);
        lock (Gate) Console.Out.WriteLine(json);
    }

    public static void Emit(object payload, string key, object value)
    {
        var json = System.Text.Json.JsonSerializer.Serialize(payload, ReportOptions);
        json = json.Insert(json.Length - 1, $",\"{key}\":{System.Text.Json.JsonSerializer.Serialize(value, ReportOptions)}");
        lock (Gate) Console.Out.WriteLine(json);
    }

    public static readonly System.Text.Json.JsonSerializerOptions ReportOptions = new()
    {
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
    };
}

// 限速共享槽：探针期间所有出站 HTTP 共享并发上限。
internal static class ProbeHttpSlots
{
    private static readonly SemaphoreSlim Slots = new(Budgets.MaxConcurrentHttpRequests, Budgets.MaxConcurrentHttpRequests);

    public static async Task<IDisposable> AcquireAsync(CancellationToken ct)
    {
        await Slots.WaitAsync(ct);
        return new SlotLease();
    }

    private sealed class SlotLease : IDisposable
    {
        public void Dispose() => Slots.Release();
    }
}
