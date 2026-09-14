using System.Buffers;
using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SteamService;

// §6 线协议：UTF-8 NDJSON，单帧上限 1 MiB；错误码 taxonomy 以
// script/tests/fixtures/steam-protocol/error-codes.json 为双端单一事实源。
// 64 位 ID（steamId/workshopId/manifestId）一律十进制字符串。
// 凭据只允许出现在 "private" 包装对象内；任何日志/诊断先经 ProtocolRedactor。
internal static class ProtocolLimits
{
    public const int Version = 1;
    public const int MaxFrameBytes = 1 * 1024 * 1024;
    public const int MaxPendingRequests = 256;
    public const int RequestTimeoutSeconds = 30;
    public const long OverlongDrainCapBytes = 8 * 1024 * 1024;
}

internal static class ProtocolErrorCodes
{
    public static readonly string[] Codes =
    [
        "network",
        "rateLimited",
        "authExpired",
        "invalidChallenge",
        "accessDenied",
        "unsupportedQuery",
        "unsupportedContent",
        "diskFull",
        "integrity",
        "cancelled",
        "protocolMismatch",
        "helperUnavailable",
    ];

    public static bool IsValid(string code)
    {
        foreach (var candidate in Codes)
        {
            if (candidate == code) return true;
        }
        return false;
    }
}

internal sealed record ProtocolError(string Code, string Message);

// 出站帧构造：只产 envelope 形状，不决定业务语义。
internal static class ProtocolMessages
{
    public static object Ready(int processEpoch, IReadOnlyList<string> capabilities) => new
    {
        v = ProtocolLimits.Version,
        type = "ready",
        protocol = ProtocolLimits.Version,
        helperVersion = HelperVersion,
        processEpoch,
        capabilities,
    };

    // SK1.2 握手身份：binary/protocol identity 由 client 核验。
    public static string HelperVersion =>
        typeof(ProtocolMessages).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";

    public static object ResultOk(string requestId, object? data, int processEpoch) => new
    {
        v = ProtocolLimits.Version,
        type = "result",
        requestId,
        processEpoch,
        ok = true,
        data,
    };

    public static object ResultError(string requestId, string code, string message, int processEpoch) => new
    {
        v = ProtocolLimits.Version,
        type = "result",
        requestId,
        processEpoch,
        ok = false,
        error = new { code, message },
    };

    public static object Event(string eventName, string? requestId, int? sequence, object? payload, int processEpoch) => new
    {
        v = ProtocolLimits.Version,
        type = "event",
        @event = eventName,
        requestId,
        sequence,
        processEpoch,
        payload,
    };

    public static object Request(string requestId, string command, int processEpoch, int accountEpoch, object? payload) => new
    {
        v = ProtocolLimits.Version,
        type = "request",
        requestId,
        command,
        processEpoch,
        accountEpoch,
        payload,
    };
}

// 入站解码：只校验 envelope 合同；命令语义由 dispatch 层处理，两者不得混合。
internal sealed class ProtocolDecode
{
    public bool Ok { get; private init; }
    public string? ErrorCode { get; private init; }
    public string? Error { get; private init; }
    public string Type { get; private init; } = "";
    public string? RequestId { get; private init; }
    public string? Command { get; private init; }
    public string? EventName { get; private init; }
    public JsonElement Root { get; private init; }

    public static ProtocolDecode Parse(string frame)
    {
        JsonElement root;
        try
        {
            using var document = JsonDocument.Parse(frame);
            root = document.RootElement.Clone();
        }
        catch (JsonException error)
        {
            return Fail("protocolMismatch", $"bad json: {error.Message}");
        }

        if (root.ValueKind != JsonValueKind.Object)
        {
            return Fail("protocolMismatch", "frame is not a json object");
        }
        if (!root.TryGetProperty("v", out var version) || version.ValueKind != JsonValueKind.Number || version.GetInt32() != ProtocolLimits.Version)
        {
            return Fail("protocolMismatch", "unsupported protocol version");
        }
        if (!root.TryGetProperty("type", out var typeEl) || typeEl.ValueKind != JsonValueKind.String)
        {
            return Fail("protocolMismatch", "missing frame type");
        }
        var type = typeEl.GetString() ?? "";
        switch (type)
        {
            case "request":
                if (!root.TryGetProperty("requestId", out var requestId) || requestId.ValueKind != JsonValueKind.String || requestId.GetString() is not { Length: > 0 })
                {
                    return Fail("protocolMismatch", "request without requestId");
                }
                if (!root.TryGetProperty("command", out var command) || command.ValueKind != JsonValueKind.String || command.GetString() is not { Length: > 0 })
                {
                    return Fail("protocolMismatch", "request without command");
                }
                return new ProtocolDecode
                {
                    Ok = true,
                    Type = type,
                    RequestId = requestId.GetString(),
                    Command = command.GetString(),
                    Root = root,
                };
            case "result":
                if (!root.TryGetProperty("requestId", out var resultId) || resultId.ValueKind != JsonValueKind.String)
                {
                    return Fail("protocolMismatch", "result without requestId");
                }
                if (!root.TryGetProperty("ok", out var ok) || ok.ValueKind != JsonValueKind.True && ok.ValueKind != JsonValueKind.False)
                {
                    return Fail("protocolMismatch", "result without ok flag");
                }
                if (ok.ValueKind == JsonValueKind.False &&
                    (!root.TryGetProperty("error", out var error) || error.ValueKind != JsonValueKind.Object ||
                     !error.TryGetProperty("code", out var code) || code.ValueKind != JsonValueKind.String ||
                     !ProtocolErrorCodes.IsValid(code.GetString() ?? "")))
                {
                    return Fail("protocolMismatch", "failed result without a taxonomy error code");
                }
                return new ProtocolDecode { Ok = true, Type = type, RequestId = resultId.GetString(), Root = root };
            case "event":
                if (!root.TryGetProperty("event", out var eventName) || eventName.ValueKind != JsonValueKind.String || eventName.GetString() is not { Length: > 0 })
                {
                    return Fail("protocolMismatch", "event without name");
                }
                return new ProtocolDecode { Ok = true, Type = type, EventName = eventName.GetString(), Root = root };
            case "ready":
                return new ProtocolDecode { Ok = true, Type = type, Root = root };
            default:
                return Fail("protocolMismatch", $"unknown frame type: {type}");
        }
    }

    private static ProtocolDecode Fail(string code, string message) => new()
    {
        Ok = false,
        ErrorCode = code,
        Error = message,
    };
}

// terminal 去重：每个 requestId 只允许一个 result；重复发送被拦截而非双发。
internal sealed class TerminalTracker
{
    private readonly ConcurrentDictionary<string, byte> terminals = new();

    public bool TryBegin(string requestId) => terminals.TryAdd(requestId, 0);

    public bool IsTerminal(string requestId) => terminals.ContainsKey(requestId);

    public void Reset() => terminals.Clear();
}

// 进度序号：发送侧保证每 requestId 单调；接收侧容忍乱序，terminal 一到即封口。
internal sealed class ProgressSequencer
{
    private readonly ConcurrentDictionary<string, int> lastSequence = new();

    public int Next(string requestId) => lastSequence.AddOrUpdate(requestId, 1, (_, value) => value + 1);

    public void Remove(string requestId) => lastSequence.TryRemove(requestId, out _);
}

internal static partial class ProtocolRedactor
{
    public static string Redact(string text) => SecretPattern().Replace(text, "$1\":\"<redacted>\"");

    [GeneratedRegex("\"(access_token|accessToken|refresh_token|refreshToken|guard_data|guardData|password|steamLoginSecure|secret)\"\\s*:\\s*\"[^\"]*\"", RegexOptions.IgnoreCase)]
    private static partial Regex SecretPattern();
}

// 有界帧读取：流式按 \\n 分帧，半包/多包天然正确；超长帧排空到下一边界后有界报错，
// 不锁死读取循环。UTF-8 多字节跨读由整帧解码保证。
internal sealed class FrameReader
{
    public enum ReadOutcome { Frame, Eof, Overlong }

    private readonly Stream stream;
    private readonly byte[] buffer = new byte[64 * 1024];
    private byte[] pending = [];
    private bool draining;

    public FrameReader(Stream stream) => this.stream = stream;

    public ReadOutcome LastOutcome { get; private set; }

    public async Task<string?> ReadFrameAsync(CancellationToken ct)
    {
        if (draining)
        {
            if (!await DrainToNewlineAsync(ct).ConfigureAwait(false))
            {
                LastOutcome = ReadOutcome.Eof;
                return null;
            }
            draining = false;
        }

        while (true)
        {
            ct.ThrowIfCancellationRequested();
            var newline = Array.IndexOf(pending, (byte)'\n');
            if (newline >= 0)
            {
                if (newline > ProtocolLimits.MaxFrameBytes)
                {
                    pending = pending[(newline + 1)..];
                    LastOutcome = ReadOutcome.Overlong;
                    return null;
                }
                var decoded = Encoding.UTF8.GetString(pending, 0, newline);
                pending = pending[(newline + 1)..];
                LastOutcome = ReadOutcome.Frame;
                return decoded;
            }
            if (pending.Length > ProtocolLimits.MaxFrameBytes)
            {
                // 边界不可信：丢弃并排空到下一个换行。
                pending = [];
                draining = true;
                LastOutcome = ReadOutcome.Overlong;
                return null;
            }

            var read = await stream.ReadAsync(buffer, ct).ConfigureAwait(false);
            if (read == 0)
            {
                var hadPartial = pending.Length > 0;
                pending = [];
                LastOutcome = hadPartial ? ReadOutcome.Overlong : ReadOutcome.Eof;
                return null;
            }
            if (pending.Length == 0)
            {
                pending = buffer[..read];
            }
            else
            {
                var merged = new byte[pending.Length + read];
                Array.Copy(pending, merged, pending.Length);
                Array.Copy(buffer, 0, merged, pending.Length, read);
                pending = merged;
            }
        }
    }

    // 排空到下一帧边界；返回 false 表示 EOF。pending 内或后续读取中寻找换行。
    private async Task<bool> DrainToNewlineAsync(CancellationToken ct)
    {
        long drained = 0;
        while (true)
        {
            ct.ThrowIfCancellationRequested();
            var newline = Array.IndexOf(pending, (byte)'\n');
            if (newline >= 0)
            {
                pending = pending[(newline + 1)..];
                return true;
            }
            if (drained > ProtocolLimits.OverlongDrainCapBytes)
            {
                pending = [];
                return true;
            }
            var read = await stream.ReadAsync(buffer, ct).ConfigureAwait(false);
            if (read == 0) return false;
            drained += read;
        }
    }
}
