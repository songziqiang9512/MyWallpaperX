using System.Text.Json;
using SteamKit2;
using SteamKit2.Internal;

namespace SteamService;

internal sealed partial class SteamSession
{
    internal static int RunQuerySelfTest()
    {
        int count = 0;
        void Check(bool ok) { if (!ok) throw new Exception("query selftest failed"); count++; }
        foreach (var (result, code) in new[] { (EResult.AccessDenied, "accessDenied"),
            (EResult.RateLimitExceeded, "rateLimited"), (EResult.Timeout, "network"),
            (EResult.FileNotFound, "unsupportedContent") })
        {
            try { RequireQuerySuccess(result); Check(false); }
            catch (SteamRequestFailure error) { Check(ClassifyQueryError(error) == code); }
        }
        RequireQuerySuccess(EResult.OK); count++;
        var valid = new PublishedFileDetails { publishedfileid = 123, creator = 76561198000000000,
            result = 1, consumer_appid = 431960, title = "test" };
        for (int i = 0; i < 12; i++) valid.tags.Add(new() { tag = "tag" + i });
        var mapped = MapItems([valid, new PublishedFileDetails { publishedfileid = 456, result = 9 },
            new PublishedFileDetails { publishedfileid = 789, result = 1, consumer_appid = 1 }]);
        Check(mapped.Items.Count == 1 && mapped.WrongApp == 1 && mapped.PartialErrors.Count == 1);
        using var item = JsonDocument.Parse(JsonSerializer.Serialize(mapped.Items[0]));
        Check(item.RootElement.GetProperty("tags").GetArrayLength() == 12);
        Check(item.RootElement.GetProperty("creatorSteamId").GetString() == "76561198000000000");
        Check(item.RootElement.TryGetProperty("description", out _)
            && item.RootElement.TryGetProperty("subscriptions", out _));
        using var partial = JsonDocument.Parse(JsonSerializer.Serialize(mapped.PartialErrors[0]));
        Check(partial.RootElement.GetProperty("publishedfileid").GetString() == "456");
        Check(!SortMap.ContainsKey("updated"));
        Console.WriteLine($"query results/partial IDs/full tags: {count}/{count} PASS (offline)");
        return 0;
    }
}
