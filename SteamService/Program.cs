using System.Text.Json;
using System.Text.Json.Serialization;

namespace SteamService;

internal sealed class ProtocolWriter
{
    private readonly object gate = new();

    public void Send(object payload)
    {
        var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions
        {
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        });
        lock (gate) { Console.Out.WriteLine(json); Console.Out.Flush(); }
    }

    public void SendDiagnostic(string text)
    {
        Console.Error.WriteLine(ProtocolRedactor.Redact(text));
    }
}

internal static class Program
{
    private static readonly ProtocolWriter writer = new();
    private static readonly TerminalTracker terminals = new();

    private static async Task<int> Main(string[] args)
    {
        // SK0.1 探针模式：独立于产品 NDJSON 服务循环，仅开发验证使用。
        if (args.Length > 0 && args[0] == "probe")
        {
            return await Probe.ProbeHost.RunAsync(args[1..]).ConfigureAwait(false);
        }
        if (args.Length > 0 && args[0] == "selftest")
        {
            return await ProtocolSelfTest.RunAsync(args.Length > 1 ? args[2..] : []).ConfigureAwait(false);
        }
        return await RunServiceAsync().ConfigureAwait(false);
    }

    // §6 服务循环：有界帧读取 → envelope 解码 → 命令 dispatch 分离。
    // 解析失败/超长帧有界关闭，不锁死；terminal 每 requestId 至多一个。
    private static async Task<int> RunServiceAsync()
    {
        var processEpoch = 1;
        writer.Send(ProtocolMessages.Ready(processEpoch, ["ping", "shutdown"]));

        using var stdin = Console.OpenStandardInput();
        var reader = new FrameReader(stdin);
        while (true)
        {
            string? frame;
            try
            {
                frame = await reader.ReadFrameAsync(CancellationToken.None).ConfigureAwait(false);
            }
            catch (Exception error)
            {
                writer.SendDiagnostic($"frame read failed: {error.Message}");
                return 1;
            }
            if (frame == null)
            {
                // EOF 或超长帧：有界结束；超长帧向对端回报协议错误。
                if (reader.LastOutcome == FrameReader.ReadOutcome.Overlong)
                {
                    writer.Send(ProtocolMessages.ResultError(
                        "", "protocolMismatch", "frame exceeded 1 MiB limit", processEpoch));
                }
                return 0;
            }

            var decode = ProtocolDecode.Parse(frame);
            if (!decode.Ok)
            {
                writer.Send(ProtocolMessages.ResultError(
                    decode.RequestId ?? "", decode.ErrorCode!, ProtocolRedactor.Redact(decode.Error!), processEpoch));
                // 协议失配后有界关闭：帧边界已不可信。
                return 1;
            }
            if (decode.Type != "request") continue;

            var requestId = decode.RequestId!;
            if (!terminals.TryBegin(requestId))
            {
                writer.SendDiagnostic($"duplicate requestId suppressed: {requestId}");
                continue;
            }

            switch (decode.Command)
            {
                case "ping":
                    writer.Send(ProtocolMessages.ResultOk(requestId, new { pong = true }, processEpoch));
                    break;
                case "shutdown":
                    writer.Send(ProtocolMessages.ResultOk(requestId, new { shuttingDown = true }, processEpoch));
                    return 0;
                default:
                    writer.Send(ProtocolMessages.ResultError(
                        requestId, "protocolMismatch", $"unknown command: {decode.Command}", processEpoch));
                    break;
            }
        }
    }
}
