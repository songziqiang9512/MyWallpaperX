using System.Text;
using System.Text.Json;

namespace SteamService;

// SK1.1 离线协议自检：golden 消息 + 帧/脱敏/terminal 合同的全部正反例。
// 运行：dotnet SteamService.dll selftest protocol <fixturesDir>；stdout 输出 JSON 行。
// 泄密反例的哨兵值从 golden fixture 的 private 包装动态提取，源码不含凭据形状字面量。
internal static class ProtocolSelfTest
{
    public sealed record CheckResult(string Check, bool Ok, string Detail);

    public static async Task<int> RunAsync(string[] args)
    {
        var fixturesDir = args.Length > 0
            ? args[0]
            : Path.Combine("..", "script", "tests", "fixtures", "steam-protocol");
        var checks = new List<CheckResult>();
        void Check(string name, bool ok, string detail = "") => checks.Add(new CheckResult(name, ok, detail));

        // 1. 错误码 taxonomy 与共享 fixture 一致（双端单一事实源）。
        var codesPath = Path.Combine(fixturesDir, "error-codes.json");
        var codesDoc = JsonDocument.Parse(File.ReadAllText(codesPath));
        var fixtureCodes = codesDoc.RootElement.GetProperty("codes").EnumerateArray()
            .Select(c => c.GetString()!).ToArray();
        Check("error-codes-match-fixture",
            fixtureCodes.SequenceEqual(ProtocolErrorCodes.Codes),
            $"fixture={fixtureCodes.Length} code={ProtocolErrorCodes.Codes.Length}");

        // 2. 正向 golden 请求全部可解码。
        var requests = ReadLines(Path.Combine(fixturesDir, "requests.jsonl"));
        var allRequestsDecode = true;
        foreach (var line in requests)
        {
            var decode = ProtocolDecode.Parse(line);
            if (!decode.Ok || decode.Type != "request")
            {
                allRequestsDecode = false;
                Check($"request-decodes:{Truncate(line)}", false, decode.Error ?? "");
            }
        }
        Check("all-golden-requests-decode", allRequestsDecode);

        // 3. UInt64 最大值以十进制字符串无损往返。
        var maxIdRequest = requests.Single(line => line.Contains("18446744073709551615"));
        var maxDecode = ProtocolDecode.Parse(maxIdRequest);
        var maxId = maxDecode.Ok ? maxDecode.Root.GetProperty("payload").GetProperty("workshopId").GetString() : null;
        Check("uint64-max-id-roundtrip", maxId == "18446744073709551615", maxId ?? "null");

        // 4. 负向 golden 帧全部被拒且错误码正确。
        var negatives = ReadLines(Path.Combine(fixturesDir, "negative-frames.jsonl"));
        var allNegativesRejected = true;
        foreach (var wrapperLine in negatives)
        {
            using var wrapper = JsonDocument.Parse(wrapperLine);
            var frame = wrapper.RootElement.GetProperty("frame").GetString()!;
            var decode = ProtocolDecode.Parse(frame);
            var expected = wrapper.RootElement.GetProperty("expect").GetString();
            if (decode.Ok || decode.ErrorCode != expected)
            {
                allNegativesRejected = false;
                Check($"negative-rejects:{Truncate(frame)}", false, decode.Ok ? "accepted" : decode.ErrorCode ?? "");
            }
        }
        Check("all-negative-frames-rejected", allNegativesRejected);

        // 5. golden 响应：事件可解码、terminal 唯一、错误码在 taxonomy 内。
        var responses = ReadLines(Path.Combine(fixturesDir, "responses.jsonl"));
        var terminalIds = new HashSet<string>();
        var responsesValid = true;
        foreach (var line in responses)
        {
            var decode = ProtocolDecode.Parse(line);
            if (!decode.Ok)
            {
                responsesValid = false;
                Check($"response-decodes:{Truncate(line)}", false, decode.Error ?? "");
                continue;
            }
            if (decode.Type == "result")
            {
                if (!terminalIds.Add(decode.RequestId!))
                {
                    responsesValid = false;
                    Check("response-terminal-once", false, decode.RequestId ?? "");
                }
            }
        }
        Check("all-golden-responses-decode", responsesValid);

        // 6. 乱序进度：sequence 2 先于 1 到达不破坏 terminal 唯一性。
        var progressSequences = responses
            .Select(line => ProtocolDecode.Parse(line))
            .Where(decode => decode.Ok && decode.Type == "event" && decode.EventName == "downloadProgress")
            .Select(decode => decode.Root.GetProperty("sequence").GetInt32())
            .ToArray();
        Check("out-of-order-progress-present",
            progressSequences.SequenceEqual([2, 1]),
            string.Join(",", progressSequences));

        // 7. 帧读取：半包、多包、Unicode、超长。
        await TestFramingAsync(Check, requests);

        // 8. TerminalTracker 去重。
        var tracker = new TerminalTracker();
        Check("terminal-tracker-dedups", tracker.TryBegin("r1") && !tracker.TryBegin("r1") && tracker.TryBegin("r2"));

        // 9. 日志泄密反例：哨兵值取自 golden private 包装；红actor 抹掉后不得回显。
        var loginResult = responses.Single(line => line.Contains("\"private\""));
        using (var loginDoc = JsonDocument.Parse(loginResult))
        {
            var privateEl = loginDoc.RootElement.GetProperty("private");
            var refreshToken = privateEl.GetProperty("refreshToken").GetString()!;
            var guardData = privateEl.GetProperty("guardData").GetString()!;
            var secretText = $"{{\"refreshToken\":\"{refreshToken}\",\"nested\":{{\"guardData\":\"{guardData}\"}}}}";
            var redacted = ProtocolRedactor.Redact(secretText);
            Check("redactor-strips-secrets",
                !redacted.Contains(refreshToken) && !redacted.Contains(guardData) && redacted.Contains("<redacted>"),
                Truncate(redacted));
            Check("private-wrapper-preserved-in-protocol-frame",
                loginResult.Contains(refreshToken),
                "protocol frame keeps private payload; stderr/log paths must redact");
            var leakedResponses = responses
                .Where(line => !line.Contains("\"private\"") && ProtocolRedactor.Redact(line) != line)
                .Count();
            Check("no-secrets-outside-private-wrapper", leakedResponses == 0);
        }

        // 10. 出站帧形状：ready/pong/result/event。
        var readyJson = JsonSerializer.Serialize(ProtocolMessages.Ready(1, ["ping", "shutdown"]));
        Check("ready-shape",
            readyJson.Contains("\"type\":\"ready\"") && readyJson.Contains("\"protocol\":1"));
        var pongJson = JsonSerializer.Serialize(ProtocolMessages.ResultOk("req-ping-1", new { pong = true }, 1));
        Check("pong-shape",
            pongJson.Contains("\"type\":\"result\"") && pongJson.Contains("\"requestId\":\"req-ping-1\"") && pongJson.Contains("\"ok\":true"));
        var errorJson = JsonSerializer.Serialize(ProtocolMessages.ResultError("r", "network", "down", 1));
        Check("error-shape", errorJson.Contains("\"code\":\"network\""));
        var eventJson = JsonSerializer.Serialize(ProtocolMessages.Event("authState", "req-login-1", 0, new { state = "online" }, 1));
        Check("event-shape",
            eventJson.Contains("\"type\":\"event\"") && eventJson.Contains("\"event\":\"authState\"") && eventJson.Contains("\"sequence\":0"));

        // 11. 帧上限常量与 §6 冻结值一致。
        Check("limits-frozen",
            ProtocolLimits.MaxFrameBytes == 1_048_576 && ProtocolLimits.MaxPendingRequests == 256
            && ProtocolLimits.RequestTimeoutSeconds == 30);

        foreach (var result in checks)
        {
            Console.Out.WriteLine(JsonSerializer.Serialize(new
            {
                suite = "selftest-protocol",
                check = result.Check,
                ok = result.Ok,
                detail = result.Detail,
            }));
        }
        var failed = checks.Count(check => !check.Ok);
        Console.Out.WriteLine(JsonSerializer.Serialize(new
        {
            suite = "selftest-protocol",
            check = "summary",
            ok = failed == 0,
            detail = $"{checks.Count - failed}/{checks.Count} passed",
        }));
        return failed == 0 ? 0 : 1;
    }

    private static async Task TestFramingAsync(Action<string, bool, string> check, string[] frames)
    {
        // 多包：一次写入全部帧 + Unicode 帧。
        var payload = string.Join("", frames.Select(f => f + "\n")) + "中文帧✅\n";
        var payloadBytes = Encoding.UTF8.GetBytes(payload);
        using (var multi = new ChunkedStream([payloadBytes]))
        {
            var reader = new FrameReader(multi);
            var decoded = new List<string?>();
            for (var i = 0; i <= frames.Length; i++)
            {
                decoded.Add(await reader.ReadFrameAsync(CancellationToken.None));
            }
            check("multi-packet-frames",
                decoded.Take(frames.Length).All(frame => frame != null)
                && decoded[^1] == "中文帧✅"
                && decoded.Count == frames.Length + 1,
                $"{decoded.Count} frames");
        }

        // 半包：3 字节微块逐段喂入，覆盖 UTF-8 多字节被拆开的情况。
        var singleFrame = Encoding.UTF8.GetBytes(frames[0] + "\n");
        var microChunks = singleFrame.Select((b, index) => (b, index))
            .GroupBy(pair => pair.index / 3)
            .Select(group => group.Select(pair => pair.b).ToArray())
            .ToArray();
        using (var half = new ChunkedStream(microChunks))
        {
            var reader = new FrameReader(half);
            var frame = await reader.ReadFrameAsync(CancellationToken.None);
            check("half-packet-utf8-frame", frame == frames[0], frame is null ? "null" : Truncate(frame));
        }

        // 超长帧：有界报错（不锁死），排空后下一帧仍可读。
        var overlong = Encoding.UTF8.GetBytes(new string('x', ProtocolLimits.MaxFrameBytes + 4096) + "\n" + frames[0] + "\n");
        using (var over = new ChunkedStream([overlong]))
        {
            var reader = new FrameReader(over);
            var frame = await reader.ReadFrameAsync(CancellationToken.None);
            check("overlong-frame-bounded",
                frame == null && reader.LastOutcome == FrameReader.ReadOutcome.Overlong,
                reader.LastOutcome.ToString());
            var next = await reader.ReadFrameAsync(CancellationToken.None);
            check("reader-recovers-after-drain", next == frames[0], next ?? "null");
        }
    }

    // 分段到达的流包装：模拟半包/多包到达节奏。
    private sealed class ChunkedStream(IReadOnlyList<byte[]> chunks) : Stream
    {
        private int chunkIndex;
        private int offsetInChunk;

        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }

        public override int Read(byte[] buffer, int offset, int count)
        {
            while (chunkIndex < chunks.Count && offsetInChunk >= chunks[chunkIndex].Length)
            {
                chunkIndex++;
                offsetInChunk = 0;
            }
            if (chunkIndex >= chunks.Count) return 0;
            var source = chunks[chunkIndex];
            var take = Math.Min(count, source.Length - offsetInChunk);
            Array.Copy(source, offsetInChunk, buffer, offset, take);
            offsetInChunk += take;
            return take;
        }

        public override void Flush() { }
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    }

    private static string[] ReadLines(string path) => File.ReadAllLines(path)
        .Where(line => line.Trim().Length > 0)
        .ToArray();

    private static string Truncate(string text) => text.Length <= 48 ? text : text[..48] + "…";
}
