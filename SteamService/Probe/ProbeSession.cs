using SteamKit2;
using SteamKit2.CDN;
using SteamKit2.Internal;

namespace SteamService.Probe;

// 有界探针会话：一个 SteamClient 连接，支持匿名/令牌登录与统一消息调用。
// 探针专用；产品实现见后续 SK1/SK2 工作卡，不在此复用。
internal sealed class ProbeSession : IAsyncDisposable
{
    private readonly SteamClient client;
    private readonly CallbackManager callbacks;
    private readonly SteamUser user;
    private readonly SteamApps apps;
    private readonly SteamContent content;
    private readonly PublishedFile publishedFiles;
    private readonly CancellationTokenSource lifetime = new();
    private readonly Task callbackLoop;
    private TaskCompletionSource<bool>? connectedSource;
    private TaskCompletionSource<SteamUser.LoggedOnCallback>? loggedOnSource;

    public SteamClient Client => client;
    public SteamApps Apps => apps;
    public SteamContent Content => content;
    public PublishedFile PublishedFiles => publishedFiles;
    public bool IsLoggedOn { get; private set; }
    public bool IsAnonymous { get; private set; }
    public string SteamId { get; private set; } = "";
    public string AccountName { get; private set; } = "";

    public ProbeSession()
    {
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
        apps = client.GetHandler<SteamApps>()!;
        content = client.GetHandler<SteamContent>()!;
        publishedFiles = client.GetHandler<SteamUnifiedMessages>()!.CreateService<PublishedFile>();
        callbacks.Subscribe<SteamClient.ConnectedCallback>(OnConnected);
        callbacks.Subscribe<SteamClient.DisconnectedCallback>(OnDisconnected);
        callbacks.Subscribe<SteamUser.LoggedOnCallback>(OnLoggedOn);
        callbackLoop = PumpAsync();
    }

    public async Task ConnectAsync(CancellationToken ct)
    {
        Exception? lastError = null;
        for (var attempt = 1; attempt <= 3; attempt++)
        {
            ct.ThrowIfCancellationRequested();
            connectedSource = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            client.Connect();
            try
            {
                await connectedSource.Task
                    .WaitAsync(TimeSpan.FromSeconds(Budgets.ConnectTimeoutSeconds), ct)
                    .ConfigureAwait(false);
                return;
            }
            catch (Exception error) when (error is not OperationCanceledException || !ct.IsCancellationRequested)
            {
                lastError = error;
                try { client.Disconnect(); } catch { }
                if (attempt < 3) await Task.Delay(500 * attempt, ct).ConfigureAwait(false);
            }
        }
        throw new IOException($"Steam connect failed after 3 attempts: {lastError?.Message}");
    }

    public async Task LogOnAnonymousAsync(CancellationToken ct)
    {
        loggedOnSource = new TaskCompletionSource<SteamUser.LoggedOnCallback>(TaskCreationOptions.RunContinuationsAsynchronously);
        user.LogOnAnonymous();
        var result = await loggedOnSource.Task
            .WaitAsync(TimeSpan.FromSeconds(Budgets.LogOnTimeoutSeconds), ct)
            .ConfigureAwait(false);
        if (result.Result != EResult.OK)
        {
            throw new IOException($"anonymous logon failed: {result.Result}");
        }
        IsAnonymous = true;
        IsLoggedOn = true;
    }

    public async Task LogOnWithTokenAsync(string username, string refreshToken, CancellationToken ct)
    {
        loggedOnSource = new TaskCompletionSource<SteamUser.LoggedOnCallback>(TaskCreationOptions.RunContinuationsAsynchronously);
        user.LogOn(new SteamUser.LogOnDetails
        {
            Username = username,
            AccessToken = refreshToken,
            ShouldRememberPassword = true,
            LoginID = (uint)Random.Shared.Next(1, int.MaxValue),
        });
        var result = await loggedOnSource.Task
            .WaitAsync(TimeSpan.FromSeconds(Budgets.LogOnTimeoutSeconds), ct)
            .ConfigureAwait(false);
        if (result.Result != EResult.OK)
        {
            throw new IOException($"token logon failed: {result.Result}");
        }
        AccountName = username;
        SteamId = result.ClientSteamID?.ConvertToUInt64().ToString() ?? "";
        IsLoggedOn = true;
    }

    public sealed record UnifiedQueryPage(
        uint Total,
        string? NextCursor,
        IReadOnlyList<PublishedFileDetails> Files);

    public async Task<UnifiedQueryPage> QueryFilesAsync(
        int queryType, string? cursor, uint? page, IReadOnlyList<string> requiredTags,
        string? searchText, uint numPerPage, uint? days, CancellationToken ct,
        bool matchAnyTags = false,
        IReadOnlyList<string>? excludedTags = null,
        IReadOnlyList<IReadOnlyList<string>>? tagGroups = null)
    {
        var request = new CPublishedFile_QueryFiles_Request
        {
            appid = Budgets.AppId,
            query_type = (uint)queryType,
            numperpage = numPerPage,
            return_metadata = true,
            return_tags = true,
        };
        foreach (var tag in requiredTags)
        {
            request.requiredtags.Add(tag);
        }
        if (matchAnyTags)
        {
            request.match_all_tags = false;
        }
        if (excludedTags != null)
        {
            foreach (var tag in excludedTags)
            {
                request.excludedtags.Add(tag);
            }
        }
        if (tagGroups != null)
        {
            foreach (var group in tagGroups)
            {
                var entry = new CPublishedFile_QueryFiles_Request.TagGroup();
                foreach (var tag in group)
                {
                    entry.tags.Add(tag);
                }
                request.taggroups.Add(entry);
            }
        }
        if (!string.IsNullOrEmpty(searchText))
        {
            request.search_text = searchText;
        }
        if (days is > 0)
        {
            request.days = days.Value;
        }
        if (!string.IsNullOrEmpty(cursor))
        {
            request.cursor = cursor;
        }
        else if (page is > 0)
        {
            request.page = page.Value;
        }
        var response = await publishedFiles.QueryFiles(request)
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(Budgets.QueryTimeoutSeconds), ct)
            .ConfigureAwait(false);
        return new UnifiedQueryPage(
            response.Body.total,
            response.Body.next_cursor,
            response.Body.publishedfiledetails);
    }

    public async Task<PublishedFileDetails?> GetDetailsAsync(
        ulong publishedFileId, CancellationToken ct)
    {
        var request = new CPublishedFile_GetDetails_Request { appid = Budgets.AppId };
        request.publishedfileids.Add(publishedFileId);
        var response = await publishedFiles.GetDetails(request)
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(Budgets.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        return response.Body.publishedfiledetails.FirstOrDefault(item => item.publishedfileid == publishedFileId);
    }

    public async Task<(uint Total, IReadOnlyList<PublishedFileDetails> Files)>
        GetUserFilesAsync(string type, uint page, uint numPerPage, bool idsOnly, CancellationToken ct)
    {
        RequireUserLogon();
        var request = new CPublishedFile_GetUserFiles_Request
        {
            steamid = ulong.Parse(SteamId),
            appid = Budgets.AppId,
            page = page,
            numperpage = numPerPage,
            type = type,
            ids_only = idsOnly,
        };
        var response = await publishedFiles.GetUserFiles(request)
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(Budgets.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        return (response.Body.total, response.Body.publishedfiledetails);
    }

    public async Task<IReadOnlyDictionary<ulong, bool>> GetSubscriptionStatesAsync(
        IReadOnlyList<ulong> ids, CancellationToken ct)
    {
        RequireUserLogon();
        var request = new CPublishedFile_AreFilesInSubscriptionList_Request { appid = Budgets.AppId, listtype = 1 };
        request.publishedfileids.AddRange(ids);
        var response = await publishedFiles.AreFilesInSubscriptionList(request)
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(Budgets.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        var states = new Dictionary<ulong, bool>();
        foreach (var item in response.Body.files)
        {
            states[item.publishedfileid] = item.inlist;
        }
        return states;
    }

    public async Task<uint> GetWorkshopDepotIdAsync(CancellationToken ct)
    {
        var tokens = await apps.PICSGetAccessTokens([Budgets.AppId], [])
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(Budgets.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        var request = new SteamApps.PICSRequest(Budgets.AppId);
        if (tokens.AppTokens.TryGetValue(Budgets.AppId, out var token)) request.AccessToken = token;
        var response = await apps.PICSGetProductInfo([request], [])
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(Budgets.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        var info = response.Results?.Select(r => r.Apps)
            .FirstOrDefault(a => a.TryGetValue(Budgets.AppId, out _))
            ?? throw new IOException("PICS product info unavailable for Wallpaper Engine.");
        var depot = info[Budgets.AppId].KeyValues["depots"]["workshopdepot"].AsUnsignedInteger();
        if (depot == 0) throw new IOException("workshopdepot missing from PICS product info.");
        return depot;
    }

    public async Task<byte[]> GetDepotDecryptionKeyAsync(uint depotId, CancellationToken ct)
    {
        var result = await apps.GetDepotDecryptionKey(depotId, Budgets.AppId)
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(Budgets.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        if (result.Result != EResult.OK)
        {
            throw new IOException($"depot decryption key denied: {result.Result}");
        }
        return result.DepotKey;
    }

    public async Task<ulong> GetManifestRequestCodeAsync(uint depotId, ulong manifestId, CancellationToken ct)
    {
        var code = await content.GetManifestRequestCode(depotId, Budgets.AppId, manifestId, Budgets.PublicBranch)
            .WaitAsync(TimeSpan.FromSeconds(Budgets.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        if (code == 0) throw new IOException("manifest request code unavailable (branch=public).");
        return code;
    }

    public async Task<Server> GetContentServerAsync(CancellationToken ct)
    {
        var servers = await content.GetServersForSteamPipe()
            .WaitAsync(TimeSpan.FromSeconds(Budgets.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        var eligible = servers
            .Where(s => !string.IsNullOrWhiteSpace(s.Host)
                && (s.AllowedAppIds.Length == 0 || s.AllowedAppIds.Contains(Budgets.AppId))
                && (s.Type == "CDN" || s.Type == "SteamCache"))
            .OrderBy(s => s.WeightedLoad)
            .ToList();
        return eligible.Count > 0
            ? eligible[0]
            : throw new IOException("no eligible SteamPipe content server.");
    }

    private void RequireUserLogon()
    {
        if (!IsLoggedOn || IsAnonymous)
        {
            throw new InvalidOperationException("probe command requires a logged-on user session.");
        }
    }

    private async Task PumpAsync()
    {
        try
        {
            while (!lifetime.IsCancellationRequested)
            {
                await callbacks.RunWaitCallbackAsync(lifetime.Token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception error)
        {
            Console.Error.WriteLine($"probe callback pump stopped: {error.Message}");
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
        if (client.IsConnected)
        {
            if (IsLoggedOn && !IsAnonymous)
            {
                try { user.LogOff(); } catch { }
            }
            client.Disconnect();
        }
        lifetime.Cancel();
        try { await callbackLoop.ConfigureAwait(false); } catch { }
        lifetime.Dispose();
    }
}
