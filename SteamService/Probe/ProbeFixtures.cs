using System.Text.Json;
using System.Text.RegularExpressions;

namespace SteamService.Probe;

// 把探针响应裁剪成最小可复用 fixture 并脱敏（账号/令牌/主机细节不入库）。
internal static partial class ProbeFixtures
{
    public static string Sanitize(string raw)
    {
        var text = TokenPattern().Replace(raw, "\"$1\":\"<redacted>\"");
        text = SteamIdPattern().Replace(text, "\"$1\":\"76560000000000000\"");
        text = AccountNamePattern().Replace(text, "\"$1\":\"probe-account\"");
        text = UrlTokenPattern().Replace(text, "$1<redacted>");
        return text;
    }

    public static void Write(string fixturesDir, string name, string rawJson)
    {
        Directory.CreateDirectory(fixturesDir);
        var path = Path.Combine(fixturesDir, name);
        File.WriteAllText(path, Sanitize(rawJson) + "\n");
        Console.Error.WriteLine($"fixture written: {path}");
    }

    // 从 QueryFiles 响应裁出最小形状：total/next_cursor/首条详情的稳定字段。
    public static string MinimalQueryFiles(JsonElement root, int queryType, string? cursor)
    {
        var response = root.GetProperty("response");
        var first = response.GetProperty("publishedfiledetails")[0];
        var minimal = new
        {
            fixture = "queryfiles-v1",
            queryType,
            requestCursor = cursor,
            total = response.TryGetProperty("total", out var total) ? total.GetInt64() : -1,
            nextCursor = response.TryGetProperty("next_cursor", out var next) ? next.GetString() : null,
            sampleItem = new
            {
                publishedfileid = first.GetProperty("publishedfileid").GetString(),
                result = first.GetProperty("result").GetInt32(),
                consumer_appid = first.TryGetProperty("consumer_appid", out var app) ? app.GetUInt32() : 0,
                filetype = first.TryGetProperty("file_type", out var ft) ? ft.GetInt32() : -1,
                file_size = first.TryGetProperty("file_size", out var size) ? size.GetString() : null,
                time_created = first.TryGetProperty("time_created", out var tc) ? tc.GetUInt32() : 0,
                time_updated = first.TryGetProperty("time_updated", out var tu) ? tu.GetUInt32() : 0,
                subscriptions = first.TryGetProperty("subscriptions", out var subs) ? subs.GetUInt32() : 0,
                tags = first.TryGetProperty("tags", out var tags)
                    ? tags.EnumerateArray().Select(t => t.GetProperty("tag").GetString()).Take(8).ToArray()
                    : Array.Empty<string?>(),
            },
        };
        return JsonSerializer.Serialize(minimal, new JsonSerializerOptions { WriteIndented = true });
    }

    public static string MinimalPublishedFileDetails(JsonElement root, string endpoint)
    {
        var first = root.GetProperty("response")
            .GetProperty("publishedfiledetails")[0];
        var minimal = new
        {
            fixture = endpoint,
            publishedfileid = first.GetProperty("publishedfileid").GetString(),
            result = first.GetProperty("result").GetInt32(),
            consumer_appid = first.TryGetProperty("consumer_appid", out var app) ? app.GetUInt32() : 0,
            creator_appid = first.TryGetProperty("creator_appid", out var creator) ? creator.GetUInt32() : 0,
            file_type = first.TryGetProperty("file_type", out var ft) ? ft.GetInt32() : -1,
            file_size = first.TryGetProperty("file_size", out var size) ? size.GetString() : null,
            hcontent_file = first.TryGetProperty("hcontent_file", out var hf) ? hf.GetString() : null,
            time_updated = first.TryGetProperty("time_updated", out var tu) ? tu.GetUInt32() : 0,
            consumer_shortcutid = first.TryGetProperty("consumer_shortcutid", out var cs) ? cs.GetUInt32() : 0,
            hasPreviewUrl = first.TryGetProperty("preview_url", out var _) ? true : false,
        };
        return JsonSerializer.Serialize(minimal, new JsonSerializerOptions { WriteIndented = true });
    }

    [GeneratedRegex("\"(access_token|refresh_token|guard_data|token|steamLoginSecure)\"\\s*:\\s*\"[^\"]*\"", RegexOptions.IgnoreCase)]
    private static partial Regex TokenPattern();

    [GeneratedRegex("\"(steamid)\"\\s*:\\s*\"(\\d{17})\"")]
    private static partial Regex SteamIdPattern();

    [GeneratedRegex("\"(account_pulldown|personaname|account_name|accountname)\"\\s*:\\s*\"[^\"]*\"")]
    private static partial Regex AccountNamePattern();

    [GeneratedRegex("(challenge_url\\\"?\\s*[:=]\\s*\\\"?https?://login.steampowered.com/[^\"]*)")]
    private static partial Regex UrlTokenPattern();
}
