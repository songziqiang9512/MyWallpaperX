using System.Collections.Concurrent;
using SteamKit2;
using SteamKit2.Authentication;
using SteamKit2.Internal;

namespace SteamService;

// SK2.1 认证 attempt 簿记（纯逻辑，可离线测试）。
// 合同：同一时刻至多一个活动 attempt；开始新 attempt 立即作废旧 attempt；
// 被作废/已终结的 attempt 不再发事件、不再写令牌（迟到的扫码/验证码一律抑制）。
internal sealed class AuthAttemptBook
{
    internal sealed class Attempt
    {
        public required string AttemptId { get; init; }
        public required string RequestId { get; init; }
        public required string Mode { get; init; }
        public int Sequence { get; set; }
        public bool IsDead { get; set; }
        public string? DeathReason { get; set; }
    }

    private readonly object gate = new();
    private readonly Dictionary<string, Attempt> attempts = new();
    private string? activeAttemptId;
    private int attemptCounter;

    /// 创建新 attempt；旧活动 attempt 被作废（调用方负责取消其轮询）。
    public Attempt Begin(string requestId, string mode)
    {
        lock (gate)
        {
            attemptCounter += 1;
            var attempt = new Attempt
            {
                AttemptId = $"auth-{attemptCounter}",
                RequestId = requestId,
                Mode = mode,
            };
            attempts[attempt.AttemptId] = attempt;
            if (activeAttemptId is { } previous && previous != attempt.AttemptId
                && attempts.TryGetValue(previous, out var old))
            {
                old.IsDead = true;
                old.DeathReason = "superseded";
            }
            activeAttemptId = attempt.AttemptId;
            return attempt;
        }
    }

    public bool CanEmit(string attemptId)
    {
        lock (gate)
        {
            return activeAttemptId == attemptId
                && attempts.TryGetValue(attemptId, out var attempt)
                && !attempt.IsDead;
        }
    }

    /// 以 attemptId 结束活动 attempt；返回是否仍是活动者（迟到终结被抑制）。
    public bool TryFinish(string attemptId, string reason)
    {
        lock (gate)
        {
            if (activeAttemptId != attemptId || !attempts.TryGetValue(attemptId, out var attempt))
            {
                return false;
            }
            attempt.IsDead = true;
            attempt.DeathReason = reason;
            activeAttemptId = null;
            return true;
        }
    }

    public void Reset()
    {
        lock (gate)
        {
            attempts.Clear();
            activeAttemptId = null;
        }
    }
}

/// Guard 分型认证器：邮箱码/设备码/手机确认各自独立事件；Submit 注入验证码；
/// Cancel 取消等待。事件只在 attempt 仍活动时经 report 发出。
internal sealed class AttemptAuthenticator : IAuthenticator
{
    private readonly Action<string, string?, bool?> report;
    private readonly Func<bool> attemptAlive;
    private readonly object gate = new();
    private TaskCompletionSource<string>? pendingCode;
    private bool waitingForDeviceConfirmation;

    public bool IsWaitingForDeviceConfirmation
    {
        get { lock (gate) return waitingForDeviceConfirmation; }
    }

    public AttemptAuthenticator(Action<string, string?, bool?> report, Func<bool> attemptAlive)
    {
        this.report = report;
        this.attemptAlive = attemptAlive;
    }

    public Task<string> GetDeviceCodeAsync(bool previousCodeWasIncorrect)
    {
        return WaitForCode("awaitingDeviceCode", null, previousCodeWasIncorrect);
    }

    public Task<string> GetEmailCodeAsync(string email, bool previousCodeWasIncorrect)
    {
        return WaitForCode("awaitingEmailCode", email, previousCodeWasIncorrect);
    }

    public Task<bool> AcceptDeviceConfirmationAsync()
    {
        lock (gate) waitingForDeviceConfirmation = true;
        if (attemptAlive()) report("awaitingDeviceConfirmation", null, null);
        return Task.FromResult(true);
    }

    public bool Submit(string code)
    {
        TaskCompletionSource<string>? source;
        lock (gate)
        {
            source = pendingCode;
            pendingCode = null;
            waitingForDeviceConfirmation = false;
        }
        return source?.TrySetResult(code) == true;
    }

    public void Cancel()
    {
        TaskCompletionSource<string>? source;
        lock (gate)
        {
            source = pendingCode;
            pendingCode = null;
            waitingForDeviceConfirmation = false;
        }
        source?.TrySetCanceled();
    }

    private Task<string> WaitForCode(string state, string? emailDomain, bool previousCodeWasIncorrect)
    {
        var source = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (gate) pendingCode = source;
        if (attemptAlive())
        {
            report(state, emailDomain, previousCodeWasIncorrect ? true : null);
        }
        else
        {
            source.TrySetCanceled();
        }
        return source.Task;
    }
}

// SK2.1：helper 内唯一 Steam 会话。密码/QR 共用连接与 attempt 合同；
// 凭据只经 stdin 帧的 private 包装，不落 argv/env；任何日志先经 ProtocolRedactor。
// 只由显式 attempt（loginPassword/loginQR）或显式 restoreSession 驱动登录，
// 不存在任何自动登录路径。异步认证命令的 request terminal 由本类负责发送。
// SK3.1：查询方法在 WorkshopQueries.cs（partial 第二部分）。
internal sealed partial class SteamSession : IAsyncDisposable
{
    private readonly ProtocolWriter writer;
    private readonly TerminalTracker terminals;
    private readonly AuthAttemptBook attemptBook = new();
    private readonly object gate = new();

    private SteamClient? client;
    private CallbackManager? callbacks;
    private SteamUser? user;
    private PublishedFile publishedFiles = null!;
    private CancellationTokenSource? lifetime = new();
    private readonly SemaphoreSlim connectGate = new(1, 1);
    private readonly SemaphoreSlim sessionGate = new(1, 1);
    private Task? callbackLoop;
    private TaskCompletionSource<bool>? connectedSource;
    private TaskCompletionSource<SteamUser.LoggedOnCallback>? loggedOnSource;

    private bool isLoggedIn;
    private bool isAnonymous;
    private string steamId = "";
    private string accountName = "";

    private sealed class AuthAttemptContext
    {
        public required AuthAttemptBook.Attempt Book;
        public required CancellationTokenSource Cancellation;
        public AttemptAuthenticator? Authenticator;
    }

    private AuthAttemptContext? activeAuthContext;

    public int ProcessEpoch { get; set; } = 1;

    public string? SteamId => steamId.Length > 0 ? steamId : null;
    public bool IsLoggedIn => isLoggedIn;

    /// 仅供离线自检观察；产品路径不得使用。
    internal string? TestActiveAttemptId
    {
        get
        {
            lock (gate)
            {
                return activeAuthContext?.Book.AttemptId;
            }
        }
    }

    public SteamSession(ProtocolWriter writer, TerminalTracker terminals)
    {
        this.writer = writer;
        this.terminals = terminals;
    }

    // ---- 命令入口（业务 dispatch 调用；异步命令的 terminal 由本类发送） ----

    public void BeginLoginPassword(string requestId, string username, string password)
    {
        var (book, context) = BeginAttempt(requestId, "password");
        var cancellation = context.Cancellation;
        _ = Task.Run(async () =>
        {
            try
            {
                EmitAuthState(book, requestId, "connecting");
                await EnsureConnectedAsync(cancellation.Token).ConfigureAwait(false);
                var authenticator = new AttemptAuthenticator(
                    (state, email, incorrect) => EmitAuthState(book, requestId, state,
                        emailDomain: email, previousCodeWasIncorrect: incorrect),
                    () => attemptBook.CanEmit(book.AttemptId));
                context.Authenticator = authenticator;
                EmitAuthState(book, requestId, "authenticating");
                var session = await client!.Authentication
                    .BeginAuthSessionViaCredentialsAsync(new AuthSessionDetails
                    {
                        Username = username,
                        Password = password,
                        IsPersistentSession = true,
                        Authenticator = authenticator,
                        DeviceFriendlyName = "MyWallpaperX SteamService",
                    })
                    .WaitAsync(TimeSpan.FromMinutes(5), cancellation.Token)
                    .ConfigureAwait(false);
                var pollResult = await PollWithGuardRetryAsync(session, authenticator, cancellation.Token)
                    .ConfigureAwait(false);
                if (!attemptBook.CanEmit(book.AttemptId))
                {
                    // 迟到验证码成功：不登录、不写令牌；请求侧仅补发 cancelled 终态。
                    FinishCancelled(book, requestId);
                    return;
                }
                await LogOnWithTokenAsync(pollResult.AccountName, pollResult.RefreshToken, cancellation.Token)
                    .ConfigureAwait(false);
                FinishSuccess(book, requestId, pollResult.AccountName, pollResult.RefreshToken,
                    pollResult.AccessToken, pollResult.NewGuardData);
            }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
            {
                FinishCancelled(book, requestId);
            }
            catch (Exception error)
            {
                FinishFailed(book, requestId, ClassifyAuthError(error), ProtocolRedactor.Redact(error.Message));
            }
        }, CancellationToken.None);
    }

    public void BeginLoginQR(string requestId)
    {
        var (book, context) = BeginAttempt(requestId, "qr");
        var cancellation = context.Cancellation;
        _ = Task.Run(async () =>
        {
            try
            {
                EmitAuthState(book, requestId, "connecting");
                await EnsureConnectedAsync(cancellation.Token).ConfigureAwait(false);
                var session = await client!.Authentication
                    .BeginAuthSessionViaQRAsync(new AuthSessionDetails
                    {
                        IsPersistentSession = true,
                        DeviceFriendlyName = "MyWallpaperX SteamService",
                    })
                    .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.RequestTimeoutSeconds), cancellation.Token)
                    .ConfigureAwait(false);
                session.ChallengeURLChanged = () =>
                    EmitAuthState(book, requestId, "qrChallenge", challengeUrl: session.ChallengeURL);
                EmitAuthState(book, requestId, "qrChallenge", challengeUrl: session.ChallengeURL);
                var pollResult = await session.PollingWaitForResultAsync(cancellation.Token).ConfigureAwait(false);
                if (!attemptBook.CanEmit(book.AttemptId))
                {
                    // 迟到扫码成功：不登录、不写令牌；请求侧仅补发 cancelled 终态。
                    FinishCancelled(book, requestId);
                    return;
                }
                await LogOnWithTokenAsync(pollResult.AccountName, pollResult.RefreshToken, cancellation.Token)
                    .ConfigureAwait(false);
                FinishSuccess(book, requestId, pollResult.AccountName, pollResult.RefreshToken,
                    pollResult.AccessToken, pollResult.NewGuardData);
            }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
            {
                FinishCancelled(book, requestId);
            }
            catch (Exception error)
            {
                FinishFailed(book, requestId, ClassifyAuthError(error), ProtocolRedactor.Redact(error.Message));
            }
        }, CancellationToken.None);
    }

    public void BeginRestore(string requestId, string restoredToken, string? accountNameHint)
    {
        var (book, context) = BeginAttempt(requestId, "restore");
        var cancellation = context.Cancellation;
        _ = Task.Run(async () =>
        {
            try
            {
                EmitAuthState(book, requestId, "connecting");
                await EnsureConnectedAsync(cancellation.Token).ConfigureAwait(false);
                await LogOnWithTokenAsync(accountNameHint ?? "", restoredToken, cancellation.Token)
                    .ConfigureAwait(false);
                FinishSuccess(book, requestId, accountNameHint ?? "", restoredToken,
                    resultAccessToken: null, newGuardData: null);
            }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
            {
                FinishCancelled(book, requestId);
            }
            catch (Exception error)
            {
                FinishFailed(book, requestId, ClassifyAuthError(error), ProtocolRedactor.Redact(error.Message));
            }
        }, CancellationToken.None);
    }

    /// 提交验证码：仅当前活动 attempt 接受；无活动/已死 attempt 返回 false。
    public bool SubmitChallenge(string authAttemptId, string code)
    {
        lock (gate)
        {
            if (activeAuthContext?.Book.AttemptId != authAttemptId) return false;
            return activeAuthContext.Authenticator?.Submit(code) == true;
        }
    }

    /// 取消：立即作废 attempt（此后扫码成功也不写令牌/不发事件），轮询有界收口。
    public bool CancelAuthentication(string? authAttemptId)
    {
        AuthAttemptContext? context;
        lock (gate)
        {
            var book = activeAuthContext?.Book;
            if (book == null) return false;
            if (authAttemptId != null && book.AttemptId != authAttemptId) return false;
            context = activeAuthContext;
            activeAuthContext = null;
        }
        attemptBook.TryFinish(context!.Book.AttemptId, "cancelled");
        context.Authenticator?.Cancel();
        try { context.Cancellation.Cancel(); } catch (ObjectDisposedException) { }
        return true;
    }

    public void Logout(string requestId)
    {
        CancelAuthentication(null);
        if (isLoggedIn)
        {
            try { user!.LogOff(); } catch { }
        }
        isLoggedIn = false;
        steamId = "";
        accountName = "";
        attemptBook.Reset();
        // dispatch 层已为该 requestId 持有唯一 terminal 槽，此处直接发送。
        writer.Send(ProtocolMessages.ResultOk(requestId, new { loggedOut = true }, ProcessEpoch));
    }

    // ---- attempt 生命周期 ----

    private (AuthAttemptBook.Attempt Book, AuthAttemptContext Context) BeginAttempt(string requestId, string mode)
    {
        lock (gate)
        {
            // 旧 attempt（如有）立即作废：切方式/重试不得并存两条认证流。
            if (activeAuthContext != null)
            {
                CancelAuthentication(null);
            }
            var book = attemptBook.Begin(requestId, mode);
            var context = new AuthAttemptContext
            {
                Book = book,
                Cancellation = new CancellationTokenSource(),
            };
            activeAuthContext = context;
            return (book, context);
        }
    }

    private void ClearContextIfCurrent(string attemptId)
    {
        lock (gate)
        {
            if (activeAuthContext?.Book.AttemptId == attemptId)
            {
                activeAuthContext = null;
            }
        }
    }

    private void EmitAuthState(AuthAttemptBook.Attempt book, string requestId, string state,
        string? challengeUrl = null, string? emailDomain = null, bool? previousCodeWasIncorrect = null)
    {
        if (!attemptBook.CanEmit(book.AttemptId)) return;
        lock (book)
        {
            book.Sequence += 1;
            // 认证状态字段置于事件顶层（与 golden responses.jsonl 合同一致）。
            writer.Send(new
            {
                v = ProtocolLimits.Version,
                type = "event",
                @event = "authState",
                requestId,
                sequence = book.Sequence,
                processEpoch = ProcessEpoch,
                state,
                authAttemptId = book.AttemptId,
                challengeUrl,
                emailDomain,
                previousCodeWasIncorrect,
            });
        }
    }

    private void FinishSuccess(
        AuthAttemptBook.Attempt book, string requestId, string realAccountName,
        string resultRefreshToken, string? resultAccessToken, string? newGuardData)
    {
        if (!attemptBook.TryFinish(book.AttemptId, "online")) return;
        ClearContextIfCurrent(book.AttemptId);
        if (!terminals.TryBegin(requestId)) return;
        // 令牌与真实账号名只在 result 的 private 包装内出站；展示名另行掩码
        // （持久化需要真实名做 restore 的 Username 提示，掩码名仅供 UI）。
        writer.Send(new
        {
            v = ProtocolLimits.Version,
            type = "result",
            requestId,
            processEpoch = ProcessEpoch,
            ok = true,
            data = new
            {
                state = "online",
                steamId,
                accountName = MaskAccount(accountName),
            },
            @private = new
            {
                refreshToken = resultRefreshToken,
                accessToken = resultAccessToken,
                guardData = newGuardData,
                accountName = realAccountName,
            },
        });
    }

    private void FinishCancelled(AuthAttemptBook.Attempt book, string requestId)
    {
        attemptBook.TryFinish(book.AttemptId, "cancelled");
        ClearContextIfCurrent(book.AttemptId);
        // 终态只由 per-requestId 槽位守卫：取消路径（cancelAuthentication 已把
        // attempt 标死）也必须给 App 的 pending 请求一个 cancelled 终态。
        if (!terminals.TryBegin(requestId)) return;
        writer.Send(ProtocolMessages.ResultError(requestId, "cancelled", "authentication cancelled", ProcessEpoch));
    }

    private void FinishFailed(AuthAttemptBook.Attempt book, string requestId, string code, string message)
    {
        attemptBook.TryFinish(book.AttemptId, code);
        ClearContextIfCurrent(book.AttemptId);
        if (!terminals.TryBegin(requestId)) return;
        writer.Send(ProtocolMessages.ResultError(requestId, code, message, ProcessEpoch));
    }

    private static string MaskAccount(string name) =>
        string.IsNullOrEmpty(name) ? ""
        : name.Length <= 2 ? "**"
        : name[..2] + "***";

    // 失败分型：默认 network（§3.3 网络失败不删令牌）；仅明确拒绝才 authExpired。
    private static string ClassifyAuthError(Exception error)
    {
        var message = error.Message;
        if (message.Contains("InvalidPassword", StringComparison.OrdinalIgnoreCase))
        {
            return "accessDenied";
        }
        // 令牌被服务端明确拒绝（过期/撤销/无效/账号不存在）。
        if (message.Contains("token logon rejected", StringComparison.OrdinalIgnoreCase))
        {
            return "authExpired";
        }
        return "network";
    }

    private static async Task<AuthPollResult> PollWithGuardRetryAsync(
        CredentialsAuthSession session, AttemptAuthenticator authenticator, CancellationToken ct)
    {
        try
        {
            return await session.PollingWaitForResultAsync(ct).ConfigureAwait(false);
        }
        catch (AsyncJobFailedException) when (authenticator.IsWaitingForDeviceConfirmation)
        {
            // 手机确认等待期间服务端 poll 可能超时失败；有界重试而不是让认证流假死。
            var failures = 0;
            var interval = session.PollingInterval < TimeSpan.FromSeconds(1)
                ? TimeSpan.FromSeconds(1)
                : session.PollingInterval;
            while (true)
            {
                await Task.Delay(interval, ct).ConfigureAwait(false);
                try
                {
                    var result = await session.PollAuthSessionStatusAsync().WaitAsync(ct).ConfigureAwait(false);
                    if (result != null) return result;
                    failures = 0;
                }
                catch (AsyncJobFailedException) when (failures < 5)
                {
                    failures += 1;
                }
            }
        }
    }

    // ---- 连接与登录 ----

    private void EnsureSession()
    {
        if (client != null) return;
        var configuration = SteamConfiguration.Create(b => b.WithHttpClientFactory(_ => new HttpClient(
            new SocketsHttpHandler
            {
                PooledConnectionLifetime = TimeSpan.FromMinutes(10),
                ConnectTimeout = TimeSpan.FromSeconds(20),
            })
        {
            Timeout = Timeout.InfiniteTimeSpan,
        }));
        client = new SteamClient(configuration);
        callbacks = new CallbackManager(client);
        user = client.GetHandler<SteamUser>()!;
        publishedFiles = client.GetHandler<SteamUnifiedMessages>()!.CreateService<PublishedFile>();
        callbacks.Subscribe<SteamClient.ConnectedCallback>(OnConnected);
        callbacks.Subscribe<SteamClient.DisconnectedCallback>(OnDisconnected);
        callbacks.Subscribe<SteamUser.LoggedOnCallback>(OnLoggedOn);
        callbackLoop = PumpAsync();
    }

    private async Task EnsureConnectedAsync(CancellationToken ct)
    {
        EnsureSession();
        if (client!.IsConnected) return;
        // 单飞连接：并发查询共享一次连接建立，避免互踩 Disconnect。
        await connectGate.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            if (client.IsConnected) return;
            Exception? lastError = null;
            for (var attempt = 1; attempt <= 3; attempt++)
            {
                ct.ThrowIfCancellationRequested();
                connectedSource = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                client.Connect();
                try
                {
                    await connectedSource.Task
                        .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.ConnectTimeoutSeconds), ct)
                        .ConfigureAwait(false);
                    return;
                }
                catch (Exception error) when (error is not OperationCanceledException || !ct.IsCancellationRequested)
                {
                    lastError = error;
                    try { client.Disconnect(); } catch { }
                    if (attempt < 3)
                    {
                        await Task.Delay(500 * attempt, ct).ConfigureAwait(false);
                    }
                }
            }
            throw new IOException($"Steam connect failed: {lastError?.Message}");
        }
        finally
        {
            connectGate.Release();
        }
    }

    private async Task LogOnWithTokenAsync(string accountNameIn, string token, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(token))
        {
            throw new IOException("no refresh token returned by Steam.");
        }
        loggedOnSource = new TaskCompletionSource<SteamUser.LoggedOnCallback>(TaskCreationOptions.RunContinuationsAsynchronously);
        user!.LogOn(new SteamUser.LogOnDetails
        {
            Username = accountNameIn,
            AccessToken = token,
            ShouldRememberPassword = true,
            LoginID = (uint)Random.Shared.Next(1, int.MaxValue),
        });
        var result = await loggedOnSource.Task
            .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.RequestTimeoutSeconds), ct)
            .ConfigureAwait(false);
        if (result.Result != EResult.OK)
        {
            // 明确拒绝（过期/撤销/无效/账号不存在）与瞬态失败分开表述：
            // App 侧只对 rejected 删令牌，瞬态失败保留令牌下次再试（§3.3）。
            if (result.Result is EResult.InvalidPassword or EResult.Expired or EResult.Revoked
                or EResult.AccountNotFound or EResult.AccountLoginDeniedThrottle)
            {
                throw new IOException($"token logon rejected: {result.Result}");
            }
            throw new IOException($"token logon failed: {result.Result}");
        }
        accountName = accountNameIn;
        steamId = result.ClientSteamID?.ConvertToUInt64().ToString() ?? "";
        isLoggedIn = true;
        if (steamId.Length == 0)
        {
            throw new IOException("logged on without a resolvable SteamID.");
        }
    }

    /// 查询会话保证：已连接 +（未登录时）匿名会话；单飞串行化，幂等。
    private async Task EnsureQuerySessionAsync(CancellationToken ct)
    {
        EnsureSession();
        if (client!.IsConnected && (isLoggedIn || isAnonymous)) return;
        await sessionGate.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            if (client.IsConnected && (isLoggedIn || isAnonymous)) return;
            await EnsureConnectedAsync(ct).ConfigureAwait(false);
            if (isLoggedIn || isAnonymous) return;
            loggedOnSource = new TaskCompletionSource<SteamUser.LoggedOnCallback>(TaskCreationOptions.RunContinuationsAsynchronously);
            user!.LogOnAnonymous();
            var result = await loggedOnSource.Task
                .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.LogOnTimeoutSeconds), ct)
                .ConfigureAwait(false);
            if (result.Result != EResult.OK)
            {
                throw new IOException($"anonymous logon failed: {result.Result}");
            }
            isAnonymous = true;
        }
        finally
        {
            sessionGate.Release();
        }
    }

    private async Task PumpAsync()    {
        try
        {
            while (!lifetime!.IsCancellationRequested)
            {
                await callbacks!.RunWaitCallbackAsync(lifetime.Token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception error)
        {
            writer.SendDiagnostic($"steam callback pump stopped: {error.Message}");
        }
    }

    private void OnConnected(SteamClient.ConnectedCallback callback) => connectedSource?.TrySetResult(true);

    private void OnDisconnected(SteamClient.DisconnectedCallback callback)
    {
        connectedSource?.TrySetException(new IOException("Steam connection closed."));
    }

    private void OnLoggedOn(SteamUser.LoggedOnCallback callback) => loggedOnSource?.TrySetResult(callback);

    public async ValueTask DisposeAsync()
    {
        CancelAuthentication(null);
        if (client is { IsConnected: true })
        {
            if (isLoggedIn)
            {
                try { user!.LogOff(); } catch { }
            }
            client.Disconnect();
        }
        lifetime?.Cancel();
        if (callbackLoop != null)
        {
            try { await callbackLoop.ConfigureAwait(false); } catch { }
        }
        lifetime?.Dispose();
    }
}
