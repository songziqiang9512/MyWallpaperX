using System.Text.Json;
using SteamKit2.Internal;

namespace SteamService.Probe;

// SK0.1 探针调度。全部子命令独立于产品 IPC；matrix 覆盖匿名能力边界并产出 fixture。
internal static class ProbeHost
{
    private const string QueryFilesUrl = "queryfiles";
    private const string DetailsUrl = "getpublishedfiledetails";
    private const string CollectionUrl = "getcollectiondetails";

    /// 路径守卫：绝对路径、规整化后不含 .. 段、且限定在仓库根或系统临时根
    /// 之下。探针只写 fixture 与隔离 state，不写任意位置。
    private static string ResolveProbeDirectory(string value, string? repoRoot, string tempRoot)
    {
        if (!Path.IsPathRooted(value))
        {
            throw new ArgumentException($"probe output directory must be absolute: {value}");
        }
        var full = Path.GetFullPath(value);
        if (full.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar).Contains(".."))
        {
            throw new ArgumentException($"probe output directory must not contain '..': {value}");
        }
        var roots = new List<string>();
        if (repoRoot != null) roots.Add(Path.GetFullPath(repoRoot));
        roots.Add(tempRoot);
        // macOS 的 /tmp 与 /private/tmp 互为符号链接，显式覆盖两个形态。
        roots.Add(Path.GetFullPath("/private/tmp"));
        roots.Add(Path.GetFullPath("/tmp"));
        if (roots.Any(root => full.StartsWith(root, StringComparison.Ordinal)))
        {
            return full;
        }
        throw new ArgumentException($"probe output directory outside repository/temp roots: {value}");
    }

    private static string? FindRepositoryRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir.FullName, "MyWallpaperX.xcodeproj", "project.pbxproj")))
            {
                return dir.FullName;
            }
            dir = dir.Parent;
        }
        return null;
    }

    public static async Task<int> RunAsync(string[] args)
    {
        string? fixturesDir = null;
        string? stateDir = null;
        var positional = new List<string>();
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == "--fixtures" && i + 1 < args.Length) fixturesDir = args[++i];
            else if (args[i] == "--state" && i + 1 < args.Length) stateDir = args[++i];
            else positional.Add(args[i]);
        }
        // 路径守卫：目录必须绝对、规整化后不含 .. 逃逸，且限定在仓库根或
        // 系统临时根之下（探针只写 fixture 与隔离 state，不写任意位置）。
        var repoRoot = FindRepositoryRoot();
        var tempRoot = Path.GetFullPath(Path.GetTempPath());
        if (fixturesDir != null) fixturesDir = ResolveProbeDirectory(fixturesDir, repoRoot, tempRoot);
        if (stateDir != null) stateDir = ResolveProbeDirectory(stateDir, repoRoot, tempRoot);
        if (stateDir != null) ProbeAuth.StateDir = stateDir;

        var command = positional.Count > 0 ? positional[0] : "help";
        using var cts = new CancellationTokenSource(TimeSpan.FromMinutes(20));
        try
        {
            switch (command)
            {
                case "help":
                case "--help":
                    PrintHelp();
                    return 0;
                case "query":
                    return await RunQueryAsync(positional.Skip(1).ToList(), fixturesDir, cts.Token).ConfigureAwait(false);
                case "details":
                    return await RunDetailsAsync(positional.Skip(1).ToList(), fixturesDir, cts.Token).ConfigureAwait(false);
                case "auth-password":
                    if (positional.Count < 2) throw new ArgumentException("usage: probe auth-password <username>");
                    await ProbeAuth.RunPasswordAsync(positional[1], cts.Token).ConfigureAwait(false);
                    return 0;
                case "auth-qr":
                    await ProbeAuth.RunQrAsync(cts.Token).ConfigureAwait(false);
                    return 0;
                case "restore":
                    await ProbeAuth.RunRestoreAsync(cts.Token).ConfigureAwait(false);
                    return 0;
                case "subscriptions":
                    return await RunSubscriptionsAsync(fixturesDir, cts.Token).ConfigureAwait(false);
                case "uquery":
                    return await RunUnifiedQueryAsync(positional.Skip(1).ToList(), cts.Token).ConfigureAwait(false);
                case "matrix":
                    return await RunMatrixAsync(fixturesDir, cts.Token).ConfigureAwait(false);
                default:
                    Console.Error.WriteLine($"unknown probe command: {command}");
                    PrintHelp();
                    return 2;
            }
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            ProbeReport.Emit(new { probe = command, stage = "failed", error = error.Message });
            return 1;
        }
    }

    private static void PrintHelp()
    {
        Console.Error.WriteLine("""
            SteamService SK0.1 probe commands:
              probe query [queryType] [--days N] [--search TEXT]   anonymous QueryFiles, 3 pages + dedup
              probe details <publishedFileId>                      anonymous GetPublishedFileDetails
              probe auth-password <username>                       password + guard flow, saves session
              probe auth-qr                                        QR challenge flow, saves session
              probe restore                                        silent restore from saved session
              probe subscriptions                                  logged-on: mysubscriptions/myfavorites pages
              probe uquery [queryType] [--anonymous] [--tag A] [--exclude-tag A] [--taggroup A+B] [--match-any] [--search TEXT] [--days N]
                                                                   unified-message QueryFiles, 3 pages; tag hit stats
              probe matrix [--fixtures DIR]                        anonymous capability matrix + fixtures
            options: --state DIR (default /tmp/mwx-sk01-probe), --fixtures DIR
            stdout is JSON lines; prompts go to stderr. Tokens never printed.
            """);
    }

    private static readonly int[] ProbeQueryTypes = [1, 3, 9, 11];

    private static async Task<int> RunQueryAsync(
        List<string> args, string? fixturesDir, CancellationToken ct)
    {
        int? queryTypeArg = null;
        int? days = null;
        string? search = null;
        for (var i = 0; i < args.Count; i++)
        {
            if (int.TryParse(args[i], out var q)) queryTypeArg = q;
            else if (args[i] == "--days" && i + 1 < args.Count && int.TryParse(args[++i], out var d)) days = d;
            else if (args[i] == "--search" && i + 1 < args.Count) search = args[++i];
        }
        var types = queryTypeArg is { } t ? [t] : ProbeQueryTypes;
        foreach (var queryType in types)
        {
            var report = await QueryThreePagesAsync(queryType, days, search, ct).ConfigureAwait(false);
            if (fixturesDir != null && report.Pages.Count > 0)
            {
                ProbeFixtures.Write(fixturesDir, $"queryfiles-q{queryType}-page1.json",
                    ProbeFixtures.MinimalQueryFiles(report.Pages[0].Body.Root, queryType, null));
            }
        }
        return 0;
    }

    private sealed record PageResult(int Page, ProbeHttpResult Body, string? NextCursor, long Total, int Received, bool WrongApp);

    private static async Task<(long Total, List<PageResult> Pages)> QueryThreePagesAsync(
        int queryType, int? days, string? search, CancellationToken ct)
    {
        string? cursor = null;
        var pages = new List<PageResult>();
        var seen = new HashSet<string>();
        long total = -1;
        for (var page = 1; page <= 3; page++)
        {
            var form = ProbeWebApi.QueryFilesForm(queryType, cursor, [], search, Budgets.QueryPageSize, days, null, true);
            var result = await ProbeWebApi.PostFormAsync(ProbeWebApi.RemoteStorageUrl(QueryFilesUrl), form,
                Budgets.QueryTimeoutSeconds, ct).ConfigureAwait(false);
            var root = result.Root;
            if (!root.TryGetProperty("response", out var response))
            {
                ProbeReport.Emit(new { probe = "query", queryType, page, status = "no-response-object", http = result.Status, elapsedMs = result.Elapsed.Milliseconds });
                break;
            }
            total = response.TryGetProperty("total", out var totalEl) ? totalEl.GetInt64() : -1;
            cursor = response.TryGetProperty("next_cursor", out var nextEl) ? nextEl.GetString() : null;
            var details = response.TryGetProperty("publishedfiledetails", out var items)
                ? items
                : throw new IOException("response missing publishedfiledetails");
            var received = details.GetArrayLength();
            var wrongApp = 0;
            foreach (var item in details.EnumerateArray())
            {
                var id = item.GetProperty("publishedfileid").GetString() ?? "";
                seen.Add(id);
                if (item.TryGetProperty("consumer_appid", out var app) && app.ValueKind == JsonValueKind.Number && app.GetUInt32() != Budgets.AppId)
                {
                    wrongApp++;
                }
            }
            ProbeReport.Emit(new
            {
                probe = "query",
                queryType,
                page,
                status = "ok",
                http = result.Status,
                total,
                received,
                uniqueSoFar = seen.Count,
                wrongAppItems = wrongApp,
                hasNextCursor = !string.IsNullOrEmpty(cursor),
                elapsedMs = (int)result.Elapsed.TotalMilliseconds,
            });
            pages.Add(new PageResult(page, result, cursor, total, received, wrongApp > 0));
            if (string.IsNullOrEmpty(cursor)) break;
            await Task.Delay(400, ct).ConfigureAwait(false);
        }
        ProbeReport.Emit(new { probe = "query", queryType, status = "summary", uniqueAfterThreePages = seen.Count, total });
        return (total, pages);
    }

    private static async Task<int> RunDetailsAsync(
        List<string> args, string? fixturesDir, CancellationToken ct)
    {
        if (args.Count == 0 || !ulong.TryParse(args[0], out var id))
        {
            throw new ArgumentException("usage: probe details <publishedFileId>");
        }
        var form = ProbeWebApi.PublishedFileDetailsForm([id]);
        var result = await ProbeWebApi.PostFormAsync(ProbeWebApi.RemoteStorageUrl(DetailsUrl), form,
            Budgets.DetailsTimeoutSeconds, ct).ConfigureAwait(false);
        var first = result.Root.GetProperty("response").GetProperty("publishedfiledetails")[0];
        ProbeReport.Emit(new
        {
            probe = "details",
            status = "ok",
            http = result.Status,
            publishedfileid = first.GetProperty("publishedfileid").GetString(),
            result = first.GetProperty("result").GetInt32(),
            consumer_appid = first.TryGetProperty("consumer_appid", out var app) && app.ValueKind == JsonValueKind.Number ? app.GetUInt32() : 0,
            file_size = first.TryGetProperty("file_size", out var size) ? size.GetString() : null,
            hasHcontentFile = first.TryGetProperty("hcontent_file", out var hf) && hf.ValueKind == JsonValueKind.String && hf.GetString()!.Length > 0,
            elapsedMs = (int)result.Elapsed.TotalMilliseconds,
        });
        if (fixturesDir != null)
        {
            ProbeFixtures.Write(fixturesDir, "publishedfiledetails-anonymous.json",
                ProbeFixtures.MinimalPublishedFileDetails(result.Root, "iSteamRemoteStorage-GetPublishedFileDetails-v1"));
        }
        return 0;
    }

    private static async Task<int> RunSubscriptionsAsync(string? fixturesDir, CancellationToken ct)
    {
        var saved = ProbeAuth.LoadSavedSession()
            ?? throw new IOException("no saved session; run auth-password or auth-qr first.");
        await using var session = new ProbeSession();
        await session.ConnectAsync(ct).ConfigureAwait(false);
        await session.LogOnWithTokenAsync(saved.AccountName, saved.RefreshToken, ct).ConfigureAwait(false);
        ProbeReport.Emit(new { probe = "subscriptions", stage = "logged-on", steamId = session.SteamId });

        foreach (var (type, idsOnly) in new[] { ("mysubscriptions", false), ("myfavorites", true) })
        {
            uint page = 1;
            var seen = new HashSet<string>();
            long total = -1;
            for (var fetched = 0; fetched < 3; fetched++, page++)
            {
                var (totalResult, files) = await session.GetUserFilesAsync(type, page, 50, idsOnly, ct).ConfigureAwait(false);
                total = totalResult;
                foreach (var file in files)
                {
                    seen.Add(file.publishedfileid.ToString());
                }
                ProbeReport.Emit(new
                {
                    probe = "subscriptions",
                    list = type,
                    page,
                    total,
                    received = files.Count,
                    uniqueSoFar = seen.Count,
                });
                if (files.Count == 0) break;
                await Task.Delay(400, ct).ConfigureAwait(false);
            }
            if (fixturesDir != null)
            {
                ProbeFixtures.Write(fixturesDir, $"getuserfiles-{type}.json",
                    $$"""{"fixture":"CPublishedFile_GetUserFiles","list":"{{type}}","total":{{total}},"uniqueIdsPage1to3":{{seen.Count}}}""");
            }
        }

        // 订阅状态只读核对：对第一页订阅 ID 调 AreFilesInSubscriptionList。
        var (subTotal, subFiles) = await session.GetUserFilesAsync("mysubscriptions", 1, 50, false, ct).ConfigureAwait(false);
        var ids = subFiles.Take(50).Select(f => f.publishedfileid).ToList();
        if (ids.Count > 0)
        {
            var states = await session.GetSubscriptionStatesAsync(ids, ct).ConfigureAwait(false);
            var inList = states.Values.Count(v => v);
            ProbeReport.Emit(new { probe = "subscriptions", stage = "states-check", requested = ids.Count, inList });
        }
        else
        {
            ProbeReport.Emit(new { probe = "subscriptions", stage = "states-check", requested = 0, note = "no subscribed items; skipped" });
        }
        return 0;
    }

    // SK4.2 撤旧：probe download 命令与 ProbeDownloader 已删除——depot 下载链
    // 由产品 WorkshopDownloader（startDownload 命令）承担，探针不再保留第二实现。

    // 匿名能力矩阵：公开查询 3 排序 × 3 页 + 详情 + 匿名会话 GetDetails + 下载链。
    // 匿名/登录会话统一消息查询探针：CPublishedFile.QueryFiles over SteamKit client。
    private static async Task<int> RunUnifiedQueryAsync(List<string> args, CancellationToken ct)
    {
        var anonymous = args.Remove("--anonymous");
        int? queryTypeArg = null;
        int? days = null;
        string? search = null;
        var tags = new List<string>();
        var excludedTags = new List<string>();
        var tagGroups = new List<IReadOnlyList<string>>();
        var matchAnyTags = args.Remove("--match-any");
        for (var i = 0; i < args.Count; i++)
        {
            if (int.TryParse(args[i], out var q)) queryTypeArg = q;
            else if (args[i] == "--days" && i + 1 < args.Count && int.TryParse(args[++i], out var d)) days = d;
            else if (args[i] == "--search" && i + 1 < args.Count) search = args[++i];
            else if (args[i] == "--tag" && i + 1 < args.Count) tags.Add(args[++i]);
            else if (args[i] == "--exclude-tag" && i + 1 < args.Count) excludedTags.Add(args[++i]);
            else if (args[i] == "--taggroup" && i + 1 < args.Count)
                tagGroups.Add(args[++i].Split('+').Where(part => part.Length > 0).ToList());
        }
        var types = queryTypeArg is { } t ? [t] : ProbeQueryTypes;
        await using var session = new ProbeSession();
        await session.ConnectAsync(ct).ConfigureAwait(false);
        if (anonymous)
        {
            await session.LogOnAnonymousAsync(ct).ConfigureAwait(false);
        }
        else
        {
            var saved = ProbeAuth.LoadSavedSession()
                ?? throw new IOException("no saved session; use --anonymous or run auth first.");
            await session.LogOnWithTokenAsync(saved.AccountName, saved.RefreshToken, ct).ConfigureAwait(false);
        }
        foreach (var queryType in types)
        {
            string? cursor = null;
            var seen = new HashSet<string>();
            for (var page = 1; page <= 3; page++)
            {
                var pageResult = await session.QueryFilesAsync(queryType, cursor, (uint)page, tags, search,
                    Budgets.QueryPageSize, (uint?)days, ct,
                    matchAnyTags: matchAnyTags,
                    excludedTags: excludedTags,
                    tagGroups: tagGroups).ConfigureAwait(false);
                var tagStats = TagStats(pageResult.Files, tags, excludedTags, tagGroups);
                foreach (var file in pageResult.Files)
                {
                    seen.Add(file.publishedfileid.ToString());
                }
                ProbeReport.Emit(new
                {
                    probe = "uquery",
                    anonymous = session.IsAnonymous,
                    queryType,
                    page,
                    total = pageResult.Total,
                    received = pageResult.Files.Count,
                    uniqueSoFar = seen.Count,
                    matchAnyTags,
                    tagStats,
                    hasNextCursor = !string.IsNullOrEmpty(pageResult.NextCursor),
                    firstTitle = pageResult.Files.Count > 0 ? pageResult.Files[0].title : null,
                });
                cursor = pageResult.NextCursor;
                if (pageResult.Files.Count < Budgets.QueryPageSize) break;
                await Task.Delay(400, ct).ConfigureAwait(false);
            }
        }
        return 0;
    }

    /// 标签命中统计：核对服务端过滤语义（AND/OR/组）——有 requiredtags 时
    /// 全命中行占比应为 100%（AND）或部分（OR 未生效）；taggroups 逐组报告
    /// 组内任意命中占比。每项都统计 requiredtags 的 anyHit/allHit。
    private static object TagStats(
        IReadOnlyList<PublishedFileDetails> files,
        IReadOnlyList<string> requiredTags,
        IReadOnlyList<string> excludedTags,
        IReadOnlyList<IReadOnlyList<string>> tagGroups)
    {
        if (requiredTags.Count == 0 && excludedTags.Count == 0 && tagGroups.Count == 0) return null;
        var itemTags = files.Select(file => new HashSet<string>(
            file.tags.Select(tag => tag.tag ?? ""),
            StringComparer.OrdinalIgnoreCase)).ToList();
        var anyHit = itemTags.Count(itemTags => requiredTags.Any(req => itemTags.Contains(req)));
        var allHit = itemTags.Count(itemTags => requiredTags.All(req => itemTags.Contains(req)));
        var excludedViolations = excludedTags.Count == 0
            ? 0
            : itemTags.Count(itemTags => excludedTags.Any(req => itemTags.Contains(req)));
        var groups = tagGroups.Select((group, index) => new
        {
            group = index,
            anyHit = itemTags.Count(itemTags => group.Any(req => itemTags.Contains(req))),
            allHit = itemTags.Count(itemTags => group.All(req => itemTags.Contains(req))),
        });
        return new { anyHit, allHit, counted = itemTags.Count, excludedViolations, groups };
    }

    private static async Task<int> RunMatrixAsync(string? fixturesDir, CancellationToken ct)
    {
        fixturesDir ??= Path.Combine(ProbeAuth.StateDir, "fixtures");
        ProbeReport.Emit(new { probe = "matrix", stage = "start", fixturesDir });

        ulong sampleId = 0;
        await using (var session = new ProbeSession())
        {
            await session.ConnectAsync(ct).ConfigureAwait(false);
            await session.LogOnAnonymousAsync(ct).ConfigureAwait(false);

            foreach (var queryType in ProbeQueryTypes)
            {
                string? cursor = null;
                var seen = new HashSet<string>();
                for (var page = 1; page <= 3; page++)
                {
                    var pageResult = await session.QueryFilesAsync(queryType, cursor, (uint)page, [], null,
                        Budgets.QueryPageSize, null, ct).ConfigureAwait(false);
                    foreach (var file in pageResult.Files)
                    {
                        seen.Add(file.publishedfileid.ToString());
                    }
                    ProbeReport.Emit(new
                    {
                        probe = "matrix",
                        stage = "uquery",
                        queryType,
                        page,
                        total = pageResult.Total,
                        received = pageResult.Files.Count,
                        uniqueSoFar = seen.Count,
                    });
                    cursor = pageResult.NextCursor;
                    if (pageResult.Files.Count < Budgets.QueryPageSize) break;
                    await Task.Delay(400, ct).ConfigureAwait(false);
                }
            }

            var sampleQuery = await session.QueryFilesAsync(1, null, 1, [], null, 1, null, ct)
                .ConfigureAwait(false);
            if (sampleQuery.Files.Count == 0) throw new IOException("matrix found no sample item.");
            sampleId = sampleQuery.Files[0].publishedfileid;

            if (fixturesDir != null)
            {
                var page1 = await session.QueryFilesAsync(1, null, 1, [], null, Budgets.QueryPageSize, null, ct)
                    .ConfigureAwait(false);
                if (page1.Files.Count > 0)
                {
                    ProbeFixtures.Write(fixturesDir, "unified-queryfiles-page1.json",
                        JsonSerializer.Serialize(new
                        {
                            fixture = "CPublishedFile_QueryFiles",
                            anonymous = true,
                            queryType = 1,
                            total = page1.Total,
                            hasNextCursor = !string.IsNullOrEmpty(page1.NextCursor),
                            sampleItem = new
                            {
                                page1.Files[0].publishedfileid,
                                page1.Files[0].result,
                                page1.Files[0].consumer_appid,
                                file_type = page1.Files[0].file_type,
                                file_size = page1.Files[0].file_size,
                                time_updated = page1.Files[0].time_updated,
                                hcontent_file = page1.Files[0].hcontent_file,
                            },
                        }, new JsonSerializerOptions { WriteIndented = true }));
                }
            }

            var detail = await session.GetDetailsAsync(sampleId, ct).ConfigureAwait(false);
            ProbeReport.Emit(new
            {
                probe = "matrix",
                stage = "unified-getdetails",
                anonymous = true,
                found = detail != null,
                result = detail != null ? (int)detail.result : -1,
                hasManifest = detail is { hcontent_file: > 0 },
                fileSize = detail?.file_size ?? 0,
            });
            if (fixturesDir != null && detail != null)
            {
                ProbeFixtures.Write(fixturesDir, "unified-getdetails-anonymous.json",
                    JsonSerializer.Serialize(new
                    {
                        fixture = "CPublishedFile_GetDetails",
                        anonymous = true,
                        detail.publishedfileid,
                        detail.result,
                        detail.consumer_appid,
                        detail.file_type,
                        detail.file_size,
                        detail.hcontent_file,
                        detail.time_updated,
                        hasPreviewUrl = !string.IsNullOrEmpty(detail.preview_url),
                    }, new JsonSerializerOptions { WriteIndented = true }));
            }
        }

        // SK4.2 撤旧：matrix 的匿名下载探针已移除（depot 链归产品
        // WorkshopDownloader；SK0.1 事实：匿名 depot key AccessDenied）。

        // Web API 匿名详情（对照路由）：确认 GetPublishedFileDetails 是否仍匿名可用。
        try
        {
            var form = ProbeWebApi.PublishedFileDetailsForm([sampleId]);
            var result = await ProbeWebApi.PostFormAsync(ProbeWebApi.RemoteStorageUrl(DetailsUrl), form,
                Budgets.DetailsTimeoutSeconds, ct).ConfigureAwait(false);
            var first = result.Root.GetProperty("response").GetProperty("publishedfiledetails")[0];
            ProbeReport.Emit(new
            {
                probe = "matrix",
                stage = "web-details",
                anonymous = true,
                http = result.Status,
                result = first.GetProperty("result").GetInt32(),
            });
            if (fixturesDir != null)
            {
                ProbeFixtures.Write(fixturesDir, "publishedfiledetails-anonymous.json",
                    ProbeFixtures.MinimalPublishedFileDetails(result.Root, "iSteamRemoteStorage-GetPublishedFileDetails-v1"));
            }
        }
        catch (Exception error)
        {
            ProbeReport.Emit(new { probe = "matrix", stage = "web-details-failed", error = error.Message });
        }

        ProbeReport.Emit(new { probe = "matrix", stage = "done" });
        return 0;
    }
}
