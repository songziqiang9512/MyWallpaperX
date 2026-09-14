using System.Diagnostics;
using System.Text.Json;

namespace SteamService.Probe;

internal sealed record ProbeHttpResult(int Status, JsonDocument Body, TimeSpan Elapsed)
{
    public JsonElement Root => Body.RootElement;
}

// 匿名公开 Web API 探针：ISteamRemoteStorage 查询/详情/集合，无 key。
internal static class ProbeWebApi
{
    public static async Task<ProbeHttpResult> PostFormAsync(
        string url,
        Dictionary<string, string> form,
        int timeoutSeconds,
        CancellationToken ct)
    {
        using var http = new HttpClient(new SocketsHttpHandler
        {
            PooledConnectionLifetime = TimeSpan.FromMinutes(5),
            AutomaticDecompression = System.Net.DecompressionMethods.All,
        })
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("MyWallpaperX-SK01-Probe/0.1");

        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(ct, timeout.Token);
        using var content = new FormUrlEncodedContent(form);
        using var slot = await ProbeHttpSlots.AcquireAsync(linked.Token).ConfigureAwait(false);
        var started = Stopwatch.StartNew();
        using var response = await http.PostAsync(url, content, linked.Token).ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(linked.Token).ConfigureAwait(false);
        return new ProbeHttpResult(
            (int)response.StatusCode,
            JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body),
            started.Elapsed);
    }

    public static string RemoteStorageUrl(string method) =>
        $"https://api.steampowered.com/ISteamRemoteStorage/{method}/v1/";

    // query_type 取值按 ERankingType 探测；cursor 为空时用 page=1。
    public static Dictionary<string, string> QueryFilesForm(
        int queryType,
        string? cursor,
        IReadOnlyList<string> requiredTags,
        string? searchText,
        int numPerPage,
        int? days,
        int? fileType,
        bool includeMetadata)
    {
        var form = new Dictionary<string, string>
        {
            ["query_type"] = queryType.ToString(),
            ["numperpage"] = numPerPage.ToString(),
            ["appid"] = Budgets.AppId.ToString(),
            ["return_vote_data"] = "false",
            ["return_tags"] = "true",
            ["return_metadata"] = includeMetadata ? "true" : "false",
        };
        if (cursor is { Length: > 0 })
        {
            form["cursor"] = cursor;
        }
        for (var i = 0; i < requiredTags.Count; i++)
        {
            form[$"requiredtags[{i}]"] = requiredTags[i];
        }
        if (!string.IsNullOrEmpty(searchText))
        {
            form["search_text"] = searchText;
        }
        if (days is > 0)
        {
            form["days"] = days.Value.ToString();
        }
        if (fileType is >= 0)
        {
            form["filetype"] = fileType.Value.ToString();
        }
        return form;
    }

    public static Dictionary<string, string> PublishedFileDetailsForm(IReadOnlyList<ulong> ids)
    {
        var form = new Dictionary<string, string> { ["itemcount"] = ids.Count.ToString() };
        for (var i = 0; i < ids.Count; i++)
        {
            form[$"publishedfileids[{i}]"] = ids[i].ToString();
        }
        return form;
    }

    public static Dictionary<string, string> CollectionDetailsForm(IReadOnlyList<ulong> ids)
    {
        var form = new Dictionary<string, string> { ["itemcount"] = ids.Count.ToString() };
        for (var i = 0; i < ids.Count; i++)
        {
            form[$"collectioncount[{i}]"] = ids[i].ToString();
        }
        return form;
    }
}
