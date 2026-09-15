using SteamKit2;
using SteamKit2.Internal;
using System.Globalization;
using System.Xml;
using System.Xml.Linq;

namespace SteamService;

internal sealed partial class SteamSession
{
    private static readonly HttpClient PublicProfiles = new(new SocketsHttpHandler {
        UseCookies = false, AllowAutoRedirect = false,
        PooledConnectionLifetime = TimeSpan.FromMinutes(10),
        ConnectTimeout = TimeSpan.FromSeconds(4)
    }) { Timeout = Timeout.InfiniteTimeSpan };
    private static readonly SemaphoreSlim PublicProfileSlots = new(2, 2);
    private static readonly object CreatorNameGate = new();
    private static readonly Dictionary<ulong, (string Name, DateTimeOffset Expires)> CreatorNames = new();

    // Only explicit detail enrichment reaches this path. Public nicknames never carry
    // account credentials and are keyed by creator ID, independently of login state.
    private async Task<IReadOnlyDictionary<ulong, string>> ResolveCreatorNamesAsync(
        IEnumerable<PublishedFileDetails> files, CancellationToken ct)
    {
        var ids = files.Where(f => f.result == (uint)EResult.OK && f.consumer_appid == ProtocolLimits.AppId)
            .Select(f => f.creator).Where(id => id != 0).Distinct().Take(80).ToArray();
        SteamClient source;
        bool anonymous;
        lock (gate) {
            source = client ?? throw new IOException("Steam connection unavailable.");
            anonymous = isAnonymous;
        }
        var names = new Dictionary<ulong, string>();
        lock (CreatorNameGate) {
            foreach (var id in ids)
                if (CreatorNames.TryGetValue(id, out var cached) && cached.Expires > DateTimeOffset.UtcNow)
                    names[id] = cached.Name;
        }
        var missing = ids.Where(id => !names.ContainsKey(id)).ToArray();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(6));
        try {
            if (anonymous) {
                var results = await Task.WhenAll(missing.Select(async id =>
                    (ID: id, Name: await PublicCreatorNameAsync(id, timeout.Token).ConfigureAwait(false)))).ConfigureAwait(false);
                foreach (var result in results)
                    if (result.Name != null) names[result.ID] = result.Name;
            } else if (missing.Length > 0) {
                var request = new CPlayer_GetPlayerLinkDetails_Request();
                request.steamids.AddRange(missing);
                AsyncJob<SteamUnifiedMessages.ServiceMethodResponse<CPlayer_GetPlayerLinkDetails_Response>> job;
                lock (gate) {
                    if (!ReferenceEquals(client, source)) throw new OperationCanceledException();
                    job = source.GetHandler<SteamUnifiedMessages>()!.CreateService<Player>().GetPlayerLinkDetails(request);
                }
                var result = await job.ToTask().WaitAsync(timeout.Token).ConfigureAwait(false);
                if (result.Result == EResult.OK) {
                    foreach (var account in result.Body.accounts) {
                        var data = account.public_data;
                        if (data != null && ids.Contains(data.steamid) && ValidCreatorName(data.persona_name) is { } name)
                            names[data.steamid] = name;
                    }
                }
            }
        } catch (OperationCanceledException) when (!ct.IsCancellationRequested) {
            // A missing nickname does not discard a valid wallpaper detail response.
        }
        catch (Exception error) when (error is IOException or SteamRequestFailure or AsyncJobFailedException) {
            // Optional public data failure must not reject the wallpaper itself.
        }
        ct.ThrowIfCancellationRequested();
        lock (gate) {
            if (!ReferenceEquals(client, source)) throw new OperationCanceledException("Steam connection changed.");
        }
        lock (CreatorNameGate) {
            foreach (var (id, name) in names) {
                if (!missing.Contains(id)) continue;
                if (!CreatorNames.ContainsKey(id) && CreatorNames.Count >= 512)
                    CreatorNames.Remove(CreatorNames.Keys.First());
                CreatorNames[id] = (name, DateTimeOffset.UtcNow.AddMinutes(30));
            }
        }
        return names;
    }

    private static async Task<string?> PublicCreatorNameAsync(ulong id, CancellationToken ct)
    {
        var acquired = false;
        try {
            await PublicProfileSlots.WaitAsync(ct).ConfigureAwait(false);
            acquired = true;
            using var response = await PublicProfiles.GetAsync(
                $"https://steamcommunity.com/profiles/{id.ToString(CultureInfo.InvariantCulture)}/?xml=1",
                HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode || response.Content.Headers.ContentLength > 131072) return null;
            await using var stream = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
            using var buffer = new MemoryStream();
            var bytes = new byte[8192];
            int count;
            while ((count = await stream.ReadAsync(bytes, ct).ConfigureAwait(false)) > 0) {
                if (buffer.Length + count > 131072) return null;
                buffer.Write(bytes, 0, count);
            }
            buffer.Position = 0;
            return ParsePublicCreatorName(buffer, id);
        } catch (Exception error) when (error is HttpRequestException or IOException or XmlException or OperationCanceledException) {
            return null;
        } finally {
            if (acquired) PublicProfileSlots.Release();
        }
    }

    internal static string? ParsePublicCreatorName(Stream xml, ulong expectedID)
    {
        using var reader = XmlReader.Create(xml, new XmlReaderSettings {
            DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = 131072
        });
        var root = XDocument.Load(reader).Root;
        if (root?.Name != "profile" || root.Element("steamID64")?.Value != expectedID.ToString(CultureInfo.InvariantCulture)) return null;
        return ValidCreatorName(root.Element("steamID")?.Value);
    }
    private static string? ValidCreatorName(string? raw) {
        var name = raw?.Trim();
        return string.IsNullOrEmpty(name) || name.Length > 128 ? null : name;
    }
}
