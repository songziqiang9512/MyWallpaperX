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
            if (args.Length > 1 && args[1] == "query") return SteamSession.RunQuerySelfTest();
            if (args.Length > 1 && args[1] == "download") return DownloadSelfTest.Run();
            if (args.Length > 1 && args[1] == "staging") return WorkshopStagingSelfTest.Run();
            if (args.Length > 1 && args[1] == "manifest") return WorkshopManifestSelfTest.Run();
            if (args.Length > 1 && args[1] == "auth")
            {
                return AuthSelfTest.Run();
            }
            return await ProtocolSelfTest.RunAsync(args.Length > 2 ? args[2..] : []).ConfigureAwait(false);
        }
        try { return await RunServiceAsync().ConfigureAwait(false); }
        finally { await steamSession.DisposeAsync().ConfigureAwait(false); }
    }

    // §6 服务循环：有界帧读取 → envelope 解码 → 命令 dispatch 分离。
    // 解析失败/超长帧有界关闭，不锁死；terminal 每 requestId 至多一个。
    // 异步命令（认证 + 查询族）的 terminal 由会话在完成时发送，循环不预占 requestId。
    private static readonly HashSet<string> AsyncCommands = new()
    {
        "loginPassword", "loginQR", "restoreSession",
        "queryBrowse", "queryDetails", "queryAuthor",
        "listSubscriptions", "listFavorites", "querySubscriptionStates",
        "setSubscription", "startDownload", "cancelDownload",
    };

    private static readonly SteamSession steamSession = new(writer, terminals);

    private static async Task<int> RunServiceAsync()
    {
        steamSession.ProcessEpoch = 1;
        writer.Send(ProtocolMessages.Ready(1, ["ping", "shutdown"]));

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
                        "", "protocolMismatch", "frame exceeded 1 MiB limit", 1));
                }
                return 0;
            }

            var decode = ProtocolDecode.Parse(frame);
            if (!decode.Ok)
            {
                writer.Send(ProtocolMessages.ResultError(
                    decode.RequestId ?? "", decode.ErrorCode!, ProtocolRedactor.Redact(decode.Error!), 1));
                // 协议失配后有界关闭：帧边界已不可信。
                return 1;
            }
            if (decode.Type != "request") continue;

            var requestId = decode.RequestId!;
            var admission = terminals.TryAccept(requestId, ProtocolLimits.IsControlCommand(decode.Command!));
            if (admission == TerminalTracker.Admission.Duplicate) continue;
            if (admission == TerminalTracker.Admission.AtCapacity)
            {
                if (terminals.TryBegin(requestId))
                    writer.Send(ProtocolMessages.ResultError(requestId, "rateLimited", "request capacity exceeded", 1));
                continue;
            }
            if (decode.Command is "loginPassword" or "loginQR" or "restoreSession" or "logout")
            {
                if (decode.AccountEpoch is not { } epoch || !steamSession.AdvanceAccountEpoch(epoch))
                {
                    if (terminals.TryBegin(requestId))
                        writer.Send(ProtocolMessages.ResultError(requestId, "cancelled", "stale account epoch", 1));
                    continue;
                }
            }
            if (AsyncCommands.Contains(decode.Command!))
            {
                try { DispatchAuthCommand(decode, requestId); }
                catch (ArgumentException error)
                {
                    if (terminals.TryBegin(requestId))
                        writer.Send(ProtocolMessages.ResultError(requestId, "protocolMismatch",
                            ProtocolRedactor.Redact(error.Message), 1));
                }
                continue;
            }
            if (!terminals.TryBegin(requestId))
            {
                writer.SendDiagnostic($"duplicate requestId suppressed: {requestId}");
                continue;
            }

            switch (decode.Command)
            {
                case "ping":
                    writer.Send(ProtocolMessages.ResultOk(requestId, new { pong = true }, 1));
                    break;
                case "shutdown":
                    writer.Send(ProtocolMessages.ResultOk(requestId, new { shuttingDown = true }, 1));
                    return 0;
                case "submitChallenge":
                {
                    var code = decode.PayloadString("code");
                    var attemptId = decode.AuthAttemptId;
                    if (code is { Length: > 0 } && attemptId is { Length: > 0 }
                        && steamSession.SubmitChallenge(attemptId, code))
                    {
                        writer.Send(ProtocolMessages.ResultOk(requestId, new { accepted = true }, 1));
                    }
                    else
                    {
                        writer.Send(ProtocolMessages.ResultOk(requestId, new { accepted = false }, 1));
                    }
                    break;
                }
                case "cancelAuthentication":
                {
                    var cancelled = decode.AuthAttemptId is { Length: > 0 } attemptId
                        && steamSession.CancelAuthentication(attemptId);
                    writer.Send(ProtocolMessages.ResultOk(requestId, new { cancelled }, 1));
                    break;
                }
                case "logout":
                    steamSession.Logout(requestId);
                    break;
                default:
                    writer.Send(ProtocolMessages.ResultError(
                        requestId, "protocolMismatch", $"unknown command: {decode.Command}", 1));
                    break;
            }
        }
    }

    private static void DispatchAuthCommand(ProtocolDecode decode, string requestId)
    {
        switch (decode.Command)
        {
            case "loginPassword":
            {
                var username = decode.PayloadString("username");
                var password = decode.PrivateString("password");
                if (string.IsNullOrEmpty(username) || string.IsNullOrEmpty(password))
                {
                    if (!terminals.TryBegin(requestId)) return;
                    writer.Send(ProtocolMessages.ResultError(
                        requestId, "protocolMismatch",
                        "loginPassword requires payload.username and private.password", 1));
                    return;
                }
                steamSession.BeginLoginPassword(requestId, username, password, decode.AuthAttemptId);
                return;
            }
            case "loginQR":
                steamSession.BeginLoginQR(requestId, decode.AuthAttemptId);
                return;
            case "restoreSession":
            {
                var token = decode.PrivateString("refreshToken");
                if (string.IsNullOrEmpty(token))
                {
                    if (!terminals.TryBegin(requestId)) return;
                    writer.Send(ProtocolMessages.ResultError(
                        requestId, "protocolMismatch",
                        "restoreSession requires private.refreshToken", 1));
                    return;
                }
                steamSession.BeginRestore(requestId, token, decode.PayloadString("accountName"), decode.AuthAttemptId);
                return;
            }
            case "queryBrowse":
                steamSession.BeginQueryBrowse(
                    requestId,
                    decode.PayloadString("sort") ?? "trend",
                    decode.PayloadUInt("page") ?? 1,
                    decode.PayloadStringArray("tags"),
                    decode.PayloadString("search"),
                    decode.PayloadStringArrayArray("tagGroups"));
                return;
            case "queryDetails":
            {
                var ids = decode.PayloadULongArray("ids");
                if (ids.Length == 0)
                {
                    if (!terminals.TryBegin(requestId)) return;
                    writer.Send(ProtocolMessages.ResultError(
                        requestId, "protocolMismatch", "queryDetails requires payload.ids", 1));
                    return;
                }
                steamSession.BeginQueryDetails(requestId, ids);
                return;
            }
            case "queryAuthor":
            {
                var creator = decode.PayloadString("creatorSteamId");
                if (creator == null || !ulong.TryParse(creator, out var creatorId) || creatorId == 0)
                {
                    if (!terminals.TryBegin(requestId)) return;
                    writer.Send(ProtocolMessages.ResultError(
                        requestId, "protocolMismatch", "queryAuthor requires payload.creatorSteamId", 1));
                    return;
                }
                steamSession.BeginQueryAuthor(requestId, creatorId, decode.PayloadUInt("page") ?? 1);
                return;
            }
            case "setSubscription":
            {
                var workshopId = decode.PayloadString("workshopId");
                var desiredState = decode.PayloadString("desiredState");
                if (workshopId == null || !ulong.TryParse(workshopId, out var subscribeId)
                    || (desiredState != "subscribe" && desiredState != "unsubscribe"))
                {
                    if (!terminals.TryBegin(requestId)) return;
                    writer.Send(ProtocolMessages.ResultError(
                        requestId, "protocolMismatch",
                        "setSubscription requires payload.workshopId and payload.desiredState=subscribe|unsubscribe", 1));
                    return;
                }
                steamSession.BeginSetSubscription(requestId, subscribeId, desiredState == "subscribe", decode.AccountEpoch);
                return;
            }
            case "startDownload":
            {
                var workshopId = decode.PayloadString("workshopId");
                var jobId = decode.StringField("jobId");
                var stagingRoot = decode.PayloadString("stagingRoot");
                var resumeStagingPath = decode.PayloadString("resumeStagingPath");
                var resumeManifestText = decode.PayloadString("resumeManifestId");
                ulong? resumeManifestId = null;
                var hasResumePath = !string.IsNullOrEmpty(resumeStagingPath);
                var hasResumeManifest = !string.IsNullOrEmpty(resumeManifestText);
                if (hasResumeManifest && ulong.TryParse(resumeManifestText, out var parsedManifest)
                    && parsedManifest > 0)
                {
                    resumeManifestId = parsedManifest;
                }
                if (workshopId == null || !ulong.TryParse(workshopId, out var downloadId)
                    || string.IsNullOrEmpty(jobId) || string.IsNullOrEmpty(stagingRoot)
                    || hasResumePath != hasResumeManifest
                    || hasResumeManifest && resumeManifestId == null
                    || hasResumePath && !Path.IsPathRooted(resumeStagingPath!))
                {
                    // 异步命令不预占 requestId，但校验失败的 terminal 在此发送：
                    // 经 TryBegin 保证重复 requestId 不双发 terminal（§6）。
                    if (!terminals.TryBegin(requestId)) return;
                    writer.Send(ProtocolMessages.ResultError(
                        requestId, "protocolMismatch",
                        "startDownload requires workshopId, jobId, stagingRoot and a complete valid resume identity", 1));
                    return;
                }
                steamSession.BeginStartDownload(requestId, jobId, downloadId, stagingRoot, decode.AccountEpoch,
                    resumeStagingPath, resumeManifestId);
                return;
            }
            case "cancelDownload":
            {
                // 同步收口的异步命令：TryBegin 保证每 requestId 至多一个 terminal。
                if (!terminals.TryBegin(requestId)) return;
                var cancelJobId = decode.StringField("jobId");
                var cancelled = cancelJobId != null && steamSession.CancelDownload(cancelJobId);
                writer.Send(ProtocolMessages.ResultOk(requestId, new { cancelled }, 1));
                return;
            }
            case "listSubscriptions":
                steamSession.BeginListSubscriptions(requestId, decode.PayloadUInt("page") ?? 1, decode.AccountEpoch);
                return;
            case "listFavorites":
                steamSession.BeginListFavorites(requestId, decode.PayloadUInt("page") ?? 1, decode.AccountEpoch);
                return;
            case "querySubscriptionStates":
            {
                var ids = decode.PayloadULongArray("ids");
                if (ids.Length == 0)
                {
                    if (!terminals.TryBegin(requestId)) return;
                    writer.Send(ProtocolMessages.ResultError(
                        requestId, "protocolMismatch", "querySubscriptionStates requires payload.ids", 1));
                    return;
                }
                steamSession.BeginQuerySubscriptionStates(requestId, ids, decode.AccountEpoch);
                return;
            }
        }
    }
}
