using System.Net;
using System.Net.Http.Headers;
using System.IO.Compression;
using SteamKit2;
using SteamKit2.CDN;

namespace SteamService;

internal static class CdnTransferSelfTest
{
    internal static async Task<int> RunAsync()
    {
        int count = 0;
        void Check(bool ok, string message)
        {
            if (!ok) throw new Exception("CDN regression: " + message);
            count++;
        }
        var now = new DateTime(2026, 9, 28, 0, 0, 0, DateTimeKind.Utc);
        var servers = new[] { ServerFor("a.example"), ServerFor("b.example") };
        var noDelay = new Func<TimeSpan, CancellationToken, Task>((_, ct) => { ct.ThrowIfCancellationRequested(); return Task.CompletedTask; });
        var tokenRequests = 0;
        Task<(string, DateTime)> Token(Server server, CancellationToken ct)
        { tokenRequests++; return Task.FromResult(("auth=secret-" + server.Host, now.AddHours(1))); }

        // Run SteamKit's actual HTTP manifest and chunk clients against an in-memory
        // handler: no login, socket, real content, filesystem or production tokens.
        foreach (var stage in new[] { "manifest", "chunk" })
        {
            var requests = new List<Uri>();
            int authBefore = tokenRequests;
            using var transfer = new WorkshopCdnTransfer(servers, Token, () => { }, () => now, noDelay);
            var manifestBytes = ZippedManifest();
            var configuration = SteamConfiguration.Create(builder => builder.WithHttpClientFactory(_ =>
                new HttpClient(new Handler(request =>
                {
                    requests.Add(request.RequestUri!);
                    if (requests.Count == 1) return new(HttpStatusCode.Forbidden);
                    return new(HttpStatusCode.OK) { Content = new ByteArrayContent(stage == "manifest" ? manifestBytes : [1, 2, 3]) };
                }))));
            var source = new SteamClient(configuration);
            using var cdn = new Client(source);
            if (stage == "manifest")
            {
                var result = await transfer.FetchAsync(stage,
                    (server, token) => cdn.DownloadManifestAsync(431960, 123, 456, server, cdnAuthToken: token), CancellationToken.None);
                Check(result.Files?.Count == 1 && result.Files[0].FileName == "project.json", "actual manifest decode");
            }
            else
            {
                var buffer = new byte[3];
                var chunk = new DepotManifest.ChunkData(new byte[20], 0, 0, 3, 3);
                var written = await transfer.FetchAsync(stage,
                    (server, token) => cdn.DownloadDepotChunkAsync(431960, chunk, server, buffer, cdnAuthToken: token), CancellationToken.None);
                Check(written == 3 && buffer.SequenceEqual(new byte[] { 1, 2, 3 }), "actual chunk bytes");
            }
            Check(requests.Count == 2 && requests.All(r => r.Host == "a.example"), "403 replays same host once");
            Check(requests[0].Query == "" && requests[1].Query == "?auth=secret-a.example", "token reaches SteamKit request");
            Check(tokenRequests == authBefore + 1, "one token fetch");
        }

        using (var transfer = new WorkshopCdnTransfer(servers, Token, () => { }, () => now, noDelay))
        {
            var hosts = new List<string>();
            int value = await transfer.FetchAsync("manifest", (server, _) =>
            {
                hosts.Add(server.Host!);
                if (hosts.Count == 1) throw Http(HttpStatusCode.ServiceUnavailable);
                return Task.FromResult(17);
            }, CancellationToken.None);
            Check(value == 17 && hosts.SequenceEqual(new[] { "a.example", "b.example" }), "503 changes node");
            hosts.Clear();
            await transfer.FetchAsync("chunk", (server, _) => { hosts.Add(server.Host!); return Task.FromResult(1); }, CancellationToken.None);
            Check(hosts.SequenceEqual(new[] { "b.example" }), "chunks use healthy manifest node");
        }

        // Each node owns its challenge. A failed authorized node must not consume
        // the next node's opportunity to authenticate, including token-service timeouts.
        foreach (bool tokenTimeout in new[] { false, true })
        {
            var hosts = new List<string>();
            var authHosts = new List<string>();
            using var transfer = new WorkshopCdnTransfer(servers, (server, ct) =>
            {
                authHosts.Add(server.Host!);
                if (tokenTimeout && authHosts.Count == 1) throw new TimeoutException();
                return Token(server, ct);
            }, () => { }, () => now, noDelay);
            var value = await transfer.FetchAsync("manifest", (server, token) =>
            {
                hosts.Add(server.Host!);
                if (token == null) throw Http(HttpStatusCode.Forbidden);
                if (server.Host == "a.example") throw Http(HttpStatusCode.ServiceUnavailable);
                return Task.FromResult(23);
            }, CancellationToken.None);
            Check(value == 23 && hosts.Count == 4
                && authHosts.SequenceEqual(tokenTimeout ? new[] { "a.example", "a.example", "b.example" }
                    : new[] { "a.example", "b.example" }), "node-local auth after transient failure");
        }

        using (var transfer = new WorkshopCdnTransfer([servers[0]], (_, _) => throw new TimeoutException(),
            () => { }, () => now, noDelay))
        {
            int calls = 0;
            try
            {
                await transfer.FetchAsync<int>("manifest", (_, _) => { calls++; throw Http(HttpStatusCode.Forbidden); }, CancellationToken.None);
                Check(false, "permanent token timeout succeeded");
            }
            catch (SteamRequestFailure error)
            { Check(error.Code == "network" && calls == 1 && error.Message.Contains("获取 CDN 授权"), "token timeout preserves phase and host"); }
        }

        foreach (var status in new[] { HttpStatusCode.ServiceUnavailable, HttpStatusCode.Forbidden,
            HttpStatusCode.Unauthorized, HttpStatusCode.NotFound, HttpStatusCode.TooManyRequests })
        {
            using var transfer = new WorkshopCdnTransfer(servers, Token, () => { }, () => now, noDelay);
            int calls = 0;
            try
            {
                await transfer.FetchAsync<int>("manifest", (_, _) => { calls++; throw Http(status); }, CancellationToken.None);
                Check(false, "persistent HTTP error succeeded");
            }
            catch (SteamRequestFailure error)
            {
                Check(error.Code == SteamSession.ClassifyDownloadError(Http(status)), "terminal HTTP classification");
                Check(error.Message.Contains($"HTTP {(int)status}") && error.Message.Contains("下载清单")
                    && error.Message.Contains(".example") && !error.Message.Contains("SECRET"), "safe persisted diagnosis");
                Check(calls == (status == HttpStatusCode.Forbidden ? 2 : status is HttpStatusCode.ServiceUnavailable
                    or HttpStatusCode.TooManyRequests ? 3 : 1), "bounded status-specific attempts");
            }
        }

        // Explicit refusal from the token service is terminal, without another host.
        using (var transfer = new WorkshopCdnTransfer(servers,
            (_, _) => throw SteamRequestFailure.FromResult(EResult.AccessDenied), () => { }, () => now, noDelay))
        {
            int calls = 0;
            try { await transfer.FetchAsync<int>("chunk", (_, _) => { calls++; throw Http(HttpStatusCode.Forbidden); }, CancellationToken.None); Check(false, "token denial succeeded"); }
            catch (SteamRequestFailure error) { Check(error.Code == "accessDenied" && calls == 1 && error.Message.Contains("获取 CDN 授权"), "token denial fails closed"); }
        }

        using (var transfer = new WorkshopCdnTransfer(servers, Token, () => { }, () => now, noDelay))
        {
            int calls = 0;
            try { await transfer.FetchAsync<int>("chunk", (_, _) => { calls++; throw new InvalidDataException("SECRET"); }, CancellationToken.None); Check(false, "corrupt chunk succeeded"); }
            catch (SteamRequestFailure error) { Check(calls == 1 && error.Code == "integrity" && !error.Message.Contains("SECRET"), "integrity never retried"); }
        }
        using (var cancel = new CancellationTokenSource())
        using (var transfer = new WorkshopCdnTransfer(servers, Token, () => { }, () => now,
            (_, ct) => { cancel.Cancel(); ct.ThrowIfCancellationRequested(); return Task.CompletedTask; }))
        {
            int calls = 0;
            try { await transfer.FetchAsync<int>("chunk", (_, _) => { calls++; throw Http(HttpStatusCode.ServiceUnavailable); }, cancel.Token); Check(false, "cancelled retry succeeded"); }
            catch (OperationCanceledException) { Check(calls == 1, "cancellation interrupts backoff"); }
        }

        var foreign = ServerFor("foreign.example");
        typeof(Server).GetProperty(nameof(Server.AllowedAppIds))!.SetValue(foreign, new uint[] { 123 });
        var proxy = ServerFor("proxy.example");
        typeof(Server).GetProperty(nameof(Server.UseAsProxy))!.SetValue(proxy, true);
        using (var transfer = new WorkshopCdnTransfer(new[] { foreign, proxy, servers[0] }, Token, () => { }, () => now, noDelay))
        {
            var selected = await transfer.FetchAsync("chunk", (s, token) =>
            {
                Check(token == null, "a new job cannot inherit another job's token");
                return Task.FromResult(s.Host);
            }, CancellationToken.None);
            Check(selected == "a.example", "foreign-app and proxy-only endpoints excluded");
        }

        // Simultaneous unauthenticated responses wait on a single token request.
        var tokenReady = new TaskCompletionSource<(string, DateTime)>(TaskCreationOptions.RunContinuationsAsynchronously);
        int concurrentTokens = 0, unauthenticated = 0;
        using (var transfer = new WorkshopCdnTransfer(servers, (_, _) => { Interlocked.Increment(ref concurrentTokens); return tokenReady.Task; },
            () => { }, () => now, noDelay))
        {
            var reads = Enumerable.Range(0, 4).Select(_ => transfer.FetchAsync("chunk", (_, token) =>
            {
                if (token == null) { Interlocked.Increment(ref unauthenticated); throw Http(HttpStatusCode.Forbidden); }
                return Task.FromResult(token);
            }, CancellationToken.None)).ToArray();
            Check(unauthenticated == 4 && concurrentTokens == 1, "concurrent auth single flight");
            tokenReady.SetResult(("auth=shared", now.AddMinutes(5)));
            Check((await Task.WhenAll(reads)).All(t => t == "auth=shared") && concurrentTokens == 1, "shared token publication");
        }

        // Expiry, cancellation while awaiting auth, and stale account after response.
        using (var transfer = new WorkshopCdnTransfer(servers, Token, () => { }, () => now, noDelay))
        {
            int before = tokenRequests;
            var lateResponse = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var late = transfer.FetchAsync("chunk", async (_, token) =>
            {
                if (token == null) { await lateResponse.Task; throw Http(HttpStatusCode.Forbidden); }
                return token;
            }, CancellationToken.None);
            await transfer.FetchAsync("chunk", (_, token) => token == null
                ? throw Http(HttpStatusCode.Forbidden) : Task.FromResult(token), CancellationToken.None);
            lateResponse.SetResult();
            Check(await late == "auth=secret-a.example" && tokenRequests == before + 1,
                "late 403 retains its rejected token snapshot and shares refresh");
        }

        using (var transfer = new WorkshopCdnTransfer([.. servers, ServerFor("c.example")], Token, () => { }, () => now, noDelay))
        {
            int calls = 0, before = tokenRequests;
            try
            {
                await transfer.FetchAsync<int>("chunk", (_, token) =>
                { calls++; throw Http(token == null ? HttpStatusCode.Forbidden : HttpStatusCode.ServiceUnavailable); }, CancellationToken.None);
                Check(false, "exhausted nodes succeeded");
            }
            catch (SteamRequestFailure error)
            {
                Check(error.Code == "network" && calls == 6 && tokenRequests == before + 3,
                    "auth replay cannot reset the shared transient budget");
            }
        }

        using (var transfer = new WorkshopCdnTransfer(servers, Token, () => { }, () => now, noDelay))
        {
            int before = tokenRequests;
            async Task Read() => await transfer.FetchAsync("chunk", (_, token) => token == null
                ? throw Http(HttpStatusCode.Forbidden) : Task.FromResult(1), CancellationToken.None);
            await Read(); await Read();
            Check(tokenRequests == before + 1, "unexpired token reused");
            now = now.AddHours(2);
            await Read();
            Check(tokenRequests == before + 2, "expired token refreshed");
        }
        using (var cancel = new CancellationTokenSource())
        using (var transfer = new WorkshopCdnTransfer(servers, (_, ct) =>
        { cancel.Cancel(); return Task.FromResult(("auth=late", now.AddHours(1))); }, () => { }, () => now, noDelay))
        {
            int calls = 0;
            try { await transfer.FetchAsync<int>("chunk", (_, _) => { calls++; throw Http(HttpStatusCode.Forbidden); }, cancel.Token); Check(false, "cancelled auth replay"); }
            catch (OperationCanceledException) { Check(calls == 1, "no send after auth cancellation"); }
        }
        bool current = true;
        using (var transfer = new WorkshopCdnTransfer(servers, Token,
            () => { if (!current) throw new InvalidOperationException("stale account"); }, () => now, noDelay))
        {
            try { await transfer.FetchAsync("chunk", (_, _) => { current = false; return Task.FromResult(1); }, CancellationToken.None); Check(false, "stale response accepted"); }
            catch (InvalidOperationException) { Check(true, "stale account response rejected"); }
        }

        var retry = Http(HttpStatusCode.TooManyRequests);
        retry.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromHours(1));
        Check(WorkshopCdnTransfer.RetryDelay(retry, 1, now) == TimeSpan.FromSeconds(30), "Retry-After bounded");
        retry.Headers.RetryAfter = new RetryConditionHeaderValue(new DateTimeOffset(now.AddSeconds(7)));
        Check(WorkshopCdnTransfer.RetryDelay(retry, 1, now) == TimeSpan.FromSeconds(7), "Retry-After date");

        // Failure of one worker stops its siblings but waits for their physical drain.
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var draining = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        int workerIndex = 0;
        var failure = new InvalidDataException("checksum");
        var workers = SteamSession.RunChunkWorkersAsync(2, async ct =>
        {
            if (Interlocked.Increment(ref workerIndex) == 1) { await entered.Task; throw failure; }
            entered.SetResult();
            try { await Task.Delay(Timeout.InfiniteTimeSpan, ct); }
            catch (OperationCanceledException) { draining.SetResult(); await release.Task; throw; }
        }, CancellationToken.None);
        await draining.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Check(!workers.IsCompleted, "worker terminal waits for drain");
        release.SetResult();
        try { await workers; Check(false, "worker failure swallowed"); }
        catch (InvalidDataException error) { Check(ReferenceEquals(error, failure), "original worker failure preserved"); }
        return count;
    }

    private static SteamKitWebRequestException Http(HttpStatusCode status)
    {
        using var response = new HttpResponseMessage(status);
        return new SteamKitWebRequestException("SECRET URI token must not be persisted", response);
    }

    private static Server ServerFor(string host)
    {
        Server server = new DnsEndPoint(host, 443);
        // SteamKit's server constructor is directory-owned. Set only fixture input.
        typeof(Server).GetProperty(nameof(Server.Type))!.SetValue(server, "CDN");
        return server;
    }

    private static byte[] ZippedManifest()
    {
        var manifest = (DepotManifest)Activator.CreateInstance(typeof(DepotManifest), nonPublic: true)!;
        typeof(DepotManifest).GetProperty(nameof(DepotManifest.CreationTime))!.SetValue(manifest, DateTime.UnixEpoch);
        typeof(DepotManifest).GetProperty(nameof(DepotManifest.Files))!.SetValue(manifest,
            new List<DepotManifest.FileData> { new("project.json", new byte[20], 0, 0, new byte[20], "", false, 0) });
        using var bytes = new MemoryStream();
        using (var zip = new ZipArchive(bytes, ZipArchiveMode.Create, leaveOpen: true))
        using (var entry = zip.CreateEntry("manifest").Open()) manifest.Serialize(entry);
        return bytes.ToArray();
    }

    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        { ct.ThrowIfCancellationRequested(); return Task.FromResult(respond(request)); }
    }
}
