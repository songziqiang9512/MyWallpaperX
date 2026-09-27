using System.Net;
using SteamKit2;
using SteamKit2.CDN;

namespace SteamService;

// One download owns this bounded candidate/token state. It never survives an
// account lease or publishes content; the existing downloader retains both owners.
internal sealed class WorkshopCdnTransfer : IDisposable
{
    internal const string Capability = "download-cdn-auth-retry-v1";
    internal const int MaxServers = 16;
    private readonly Server[] servers;
    private readonly Func<Server, CancellationToken, Task<(string Token, DateTime Expiration)>> requestToken;
    private readonly Action checkCurrent;
    private readonly Func<DateTime> utcNow;
    private readonly Func<TimeSpan, CancellationToken, Task> delay;
    private readonly SemaphoreSlim tokenGate = new(1, 1);
    private readonly Dictionary<Server, (string Token, DateTime Expiration)> tokens = new();
    private readonly object gate = new();
    private int serverIndex;

    internal WorkshopCdnTransfer(IEnumerable<Server> candidates,
        Func<Server, CancellationToken, Task<(string Token, DateTime Expiration)>> requestToken,
        Action checkCurrent, Func<DateTime>? utcNow = null,
        Func<TimeSpan, CancellationToken, Task>? delay = null)
    {
        servers = candidates
            .Where(s => ValidHost(s.Host) && ValidHost(s.VHost) && !s.UseAsProxy
                && s.Port is > 0 and <= 65535
                && (s.AllowedAppIds.Length == 0 || s.AllowedAppIds.Contains(ProtocolLimits.AppId))
                && (s.Type == "CDN" || s.Type == "SteamCache"))
            .OrderBy(s => s.WeightedLoad)
            .DistinctBy(s => (s.Host, s.VHost, s.Port, s.Protocol))
            .Take(MaxServers).ToArray();
        if (servers.Length == 0) throw new SteamRequestFailure("network", "Steam 未返回可用的内容下载节点，请稍后重试。");
        this.requestToken = requestToken;
        this.checkCurrent = checkCurrent;
        this.utcNow = utcNow ?? (() => DateTime.UtcNow);
        this.delay = delay ?? Task.Delay;
    }

    private static bool ValidHost(string? host) => !string.IsNullOrWhiteSpace(host)
        && host.Length <= 253 && Uri.CheckHostName(host) != UriHostNameType.Unknown;

    private string? CurrentToken(Server server)
    {
        lock (gate)
            return tokens.TryGetValue(server, out var cached) && cached.Expiration > utcNow().AddSeconds(30)
                ? cached.Token : null;
    }

    private async Task<string> RefreshTokenAsync(Server server, string? rejectedToken, CancellationToken ct)
    {
        await tokenGate.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            ct.ThrowIfCancellationRequested();
            checkCurrent();
            // Concurrent 403s share the token fetched after their rejected request.
            var cached = CurrentToken(server);
            if (cached != null && cached != rejectedToken) return cached;
            var result = await requestToken(server, ct).ConfigureAwait(false);
            ct.ThrowIfCancellationRequested();
            checkCurrent();
            if (string.IsNullOrWhiteSpace(result.Token) || result.Expiration <= utcNow())
                throw new SteamRequestFailure("accessDenied", "Steam 未提供有效的 CDN 授权。");
            lock (gate) tokens[server] = result;
            return result.Token;
        }
        finally { tokenGate.Release(); }
    }

    internal async Task<T> FetchAsync<T>(string stage,
        Func<Server, string?, Task<T>> fetch, CancellationToken ct)
    {
        // One retry loop: transient failures spend the shared budget; each node
        // can answer one auth challenge, but a repeated refusal is terminal.
        var challenged = new HashSet<Server>();
        int failures = 0, physicalAttempts = 0;
        bool needsToken = false;
        string? token = null;
        Server server;
        lock (gate) server = servers[serverIndex];
        while (true)
        {
            ct.ThrowIfCancellationRequested();
            checkCurrent();
            if (!needsToken) token = CurrentToken(server);
            var failureStage = needsToken ? "cdn-auth" : stage;
            try
            {
                if (needsToken) token = await RefreshTokenAsync(server, token, ct).ConfigureAwait(false);
                needsToken = false;
                ct.ThrowIfCancellationRequested();
                checkCurrent();
                failureStage = stage;
                physicalAttempts++;
                var result = await fetch(server, token).ConfigureAwait(false);
                ct.ThrowIfCancellationRequested();
                checkCurrent();
                return result;
            }
            catch (Exception error) when (!ct.IsCancellationRequested && IsTransferError(error))
            {
                if (failureStage == stage && error is HttpRequestException { StatusCode: HttpStatusCode.Forbidden }
                    && challenged.Add(server))
                {
                    needsToken = true;
                    continue;
                }
                if (++failures >= SteamSession.MaxChunkDownloadAttempts || !SteamSession.IsRetryableChunkFetch(error, ct))
                    throw new SteamRequestFailure(SteamSession.ClassifyDownloadError(error),
                        FailureMessage(failureStage, server, physicalAttempts, error));
                // Token service failures retry authentication on the same node.
                // Only content transfer failures rotate; late workers cannot skip a healthy node.
                if (!needsToken)
                    lock (gate)
                    {
                        if (ReferenceEquals(servers[serverIndex], server)) serverIndex = (serverIndex + 1) % servers.Length;
                        server = servers[serverIndex];
                    }
                await delay(RetryDelay(error, failures, utcNow()), ct).ConfigureAwait(false);
            }
        }
    }

    private static bool IsTransferError(Exception error) => error is HttpRequestException
        or InvalidDataException or IOException or System.Net.Sockets.SocketException or TimeoutException
        or OperationCanceledException or SteamRequestFailure;

    internal static TimeSpan RetryDelay(Exception error, int attempt, DateTime now)
    {
        var backoff = SteamSession.ChunkRetryBackoffDelay(attempt);
        if (error is SteamKitWebRequestException web)
        {
            var retry = web.Headers.RetryAfter;
            var requested = retry?.Delta ?? (retry?.Date - new DateTimeOffset(now));
            // Respect a bounded server hint, never pin a download on an untrusted delay.
            if (requested.HasValue && requested.Value > backoff)
                return TimeSpan.FromSeconds(Math.Min(30, requested.Value.TotalSeconds));
        }
        return backoff;
    }

    private static string FailureMessage(string stage, Server server, int attempts, Exception error)
    {
        var phase = stage switch { "manifest" => "下载清单", "cdn-auth" => "获取 CDN 授权", _ => "下载数据块" };
        var status = error is HttpRequestException { StatusCode: { } code } ? $"HTTP {(int)code}" : SteamSession.ClassifyDownloadError(error);
        var action = SteamSession.ClassifyDownloadError(error) switch
        {
            "authExpired" => "请使用工具栏重新登录 Steam 后重试。",
            "accessDenied" => "Steam 内容节点拒绝访问；请检查账号授权及代理设置后重试。",
            "rateLimited" => "Steam 暂时限制请求，请稍后重试。",
            "unsupportedContent" => "内容节点未提供该内容，请刷新条目后重试。",
            "integrity" => "内容校验失败，已停止本次下载。",
            _ => "请检查网络及代理设置，稍后重试。",
        };
        // Deliberately omit Exception.Message, URI paths/query strings and headers:
        // they can contain manifest request codes and CDN auth tokens.
        return $"{phase}失败（{status}，节点 {server.Host}，已尝试 {attempts} 次）。{action}";
    }

    public void Dispose() { tokenGate.Dispose(); tokens.Clear(); }
}
