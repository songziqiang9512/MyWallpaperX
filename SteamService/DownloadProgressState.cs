using SteamKit2;

namespace SteamService;

// Counters, coalescing, sequence allocation and publication have one owner.
internal sealed class DownloadProgressState
{
    internal sealed record Snapshot(int Sequence, string Stage, long? TotalBytes, long VerifiedBytes,
        int? TotalChunks, int VerifiedChunks);
    private readonly object gate = new();
    private int sequence, chunks;
    private long bytes, lastTick;
    private long? totalBytes;
    private int? totalChunks;
    internal long VerifiedBytes { get { lock (gate) return bytes; } }

    internal void Publish(string stage, long? total, int? count, Action<Snapshot> send)
    {
        lock (gate)
        {
            if (total.HasValue) totalBytes = total;
            if (count.HasValue) totalChunks = count;
            send(new(++sequence, stage, totalBytes, bytes, totalChunks, chunks));
        }
    }

    internal void CompleteChunk(int written, Action<Snapshot> send)
    {
        lock (gate)
        {
            if (written <= 0 || totalBytes == null || totalChunks == null ||
                written > totalBytes - bytes || chunks >= totalChunks)
                throw new InvalidDataException("progress exceeds admitted manifest");
            bytes += written;
            chunks++;
            var tick = Environment.TickCount64;
            if (lastTick != 0 && tick - lastTick < 250 && chunks != totalChunks) return;
            lastTick = tick;
            send(new(++sequence, "chunks", totalBytes, bytes, totalChunks, chunks));
        }
    }
}

internal sealed class SteamRequestFailure(string code, string message) : Exception(message)
{
    internal string Code { get; } = code;
    internal static SteamRequestFailure FromResult(EResult result) => new(result switch
    {
        EResult.RateLimitExceeded or EResult.LimitExceeded => "rateLimited",
        EResult.AccessDenied or EResult.InsufficientPrivilege => "accessDenied",
        EResult.Timeout or EResult.NoConnection or EResult.ServiceUnavailable or EResult.Busy => "network",
        _ => "unsupportedContent",
    }, $"Steam request failed ({result})");
}
