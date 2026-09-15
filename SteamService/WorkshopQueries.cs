using SteamKit2;
using SteamKit2.Internal;

namespace SteamService;

// SK3.1 统一结构化查询（SteamSession partial 第二部分）。
//
// 合同（§4.1/§6）：
// - 所有列表/详情/订阅/收藏数据经本类统一 query 合同出站；consumerAppID
//   强制校验（非 431960 的条目被剔除并计数，不混入结果）。
// - 分页为页码型（SK0.1 实测：统一消息无 next_cursor），hasMore = received==pageSize。
// - 查询共享并发槽（MaxConcurrentQueries）；超出即排队，响应有界超时。
// - Swift 侧以 queryGeneration+requestId 丢弃陈旧页；helper 不设查询取消命令，
//   查询有界超时后必然出 terminal。
// - 已知能力缺口（SK0.1 实测）：`days`（趋势时间窗）被服务端静默忽略，
//   本类不发送该字段；`filetype`/年龄分级等尚未实证的筛选不开放。
internal sealed partial class SteamSession
{
    private const int MaxConcurrentQueries = 2;
    private const uint QueryPageSize = 30;
    private static readonly SemaphoreSlim QuerySlots = new(MaxConcurrentQueries, MaxConcurrentQueries);

    /// 统一排序键（SK0.1 实测可用的 query_type）。
    private static readonly Dictionary<string, uint> SortMap = new(StringComparer.Ordinal)
    {
        ["newest"] = 1,
        ["trend"] = 3,
        ["subscriptions"] = 9,
        ["votes"] = 11,
    };

    public void BeginQueryBrowse(
        string requestId, string sort, uint page,
        IReadOnlyList<string> requiredTags, string? searchText)
    {
        // 输入校验前置：不合法排序不触发连接（typed unsupportedQuery）。
        if (!SortMap.TryGetValue(sort, out var queryType))
        {
            EmitQueryFailure(requestId, "unsupportedQuery", $"unknown sort: {sort}");
            return;
        }
        if (page == 0) page = 1;
        RunQueryAsync(requestId, async ct =>
        {
            var request = new CPublishedFile_QueryFiles_Request
            {
                appid = ProtocolLimits.AppId,
                query_type = queryType,
                numperpage = QueryPageSize,
                page = page,
                return_metadata = true,
                return_tags = true,
            };
            foreach (var tag in requiredTags.Where(t => !string.IsNullOrWhiteSpace(t)))
            {
                request.requiredtags.Add(tag);
            }
            if (!string.IsNullOrWhiteSpace(searchText))
            {
                request.search_text = searchText;
            }
            var response = await publishedFiles.QueryFiles(request)
                .ToTask()
                .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.QueryTimeoutSeconds), ct)
                .ConfigureAwait(false);
            var body = response.Body;
            var (items, wrongApp, errorEntries) = MapItems(body.publishedfiledetails);
            return new
            {
                page,
                total = body.total,
                hasMore = body.publishedfiledetails.Count >= (int)QueryPageSize,
                items,
                wrongAppDropped = wrongApp,
                partial = errorEntries.Count > 0 ? errorEntries : null,
            };
        });
    }

    public void BeginQueryDetails(string requestId, IReadOnlyList<ulong> ids)
    {
        if (ids.Count == 0 || ids.Count > 80)
        {
            EmitQueryFailure(requestId, "unsupportedQuery", "ids out of range");
            return;
        }
        RunQueryAsync(requestId, async ct =>
        {
            var request = new CPublishedFile_GetDetails_Request { appid = ProtocolLimits.AppId };
            foreach (var id in ids)
            {
                request.publishedfileids.Add(id);
            }
            var response = await publishedFiles.GetDetails(request)
                .ToTask()
                .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
                .ConfigureAwait(false);
            var (items, wrongApp, errorEntries) = MapItems(response.Body.publishedfiledetails);
            return new
            {
                items,
                wrongAppDropped = wrongApp,
                partial = errorEntries.Count > 0 ? errorEntries : null,
            };
        });
    }

    /// 作者工坊：GetUserFiles 以目标作者 steamid 查询（匿名可用性由 SK3.1 实测）。
    public void BeginQueryAuthor(string requestId, ulong creatorSteamId, uint page)
    {
        RunQueryAsync(requestId, async ct =>
        {
            var (total, files) = await GetUserFilesInternalAsync(creatorSteamId, "myfiles", page, idsOnly: false, ct)
                .ConfigureAwait(false);
            var (items, wrongApp, errorEntries) = MapItems(files);
            return new
            {
                page,
                total,
                hasMore = files.Count >= (int)QueryPageSize,
                items,
                wrongAppDropped = wrongApp,
                partial = errorEntries.Count > 0 ? errorEntries : null,
            };
        });
    }

    public void BeginListSubscriptions(string requestId, uint page)
    {
        RequireAccountForQuery(requestId, () => RunQueryAsync(requestId, async ct =>
        {
            var (total, files) = await GetUserFilesInternalAsync(OwnSteamId, "mysubscriptions", page, idsOnly: false, ct)
                .ConfigureAwait(false);
            var (items, wrongApp, errorEntries) = MapItems(files);
            return new
            {
                page,
                total,
                hasMore = files.Count >= (int)QueryPageSize,
                items,
                wrongAppDropped = wrongApp,
                partial = errorEntries.Count > 0 ? errorEntries : null,
            };
        }));
    }

    public void BeginListFavorites(string requestId, uint page)
    {
        RequireAccountForQuery(requestId, () => RunQueryAsync(requestId, async ct =>
        {
            var (total, files) = await GetUserFilesInternalAsync(OwnSteamId, "myfavorites", page, idsOnly: true, ct)
                .ConfigureAwait(false);
            // favorites ids_only 时仅回 ID 列表。
            var ids = files.Select(f => f.publishedfileid.ToString()).ToArray();
            return new
            {
                page,
                total,
                // hasMore 与 GetUserFiles 实际请求的 numperpage（QueryPageSize）一致；
                // 修复：原硬编码 50 与页大小 30 不符，满页时 hasMore 恒为 false。
                hasMore = files.Count >= (int)QueryPageSize,
                ids,
            };
        }));
    }

    public void BeginQuerySubscriptionStates(string requestId, IReadOnlyList<ulong> ids)
    {
        if (ids.Count == 0 || ids.Count > 100)
        {
            EmitQueryFailure(requestId, "unsupportedQuery", "ids out of range");
            return;
        }
        RequireAccountForQuery(requestId, () => RunQueryAsync(requestId, async ct =>
        {
            var request = new CPublishedFile_AreFilesInSubscriptionList_Request
            {
                appid = ProtocolLimits.AppId,
                listtype = 1,
            };
            foreach (var id in ids)
            {
                request.publishedfileids.Add(id);
            }
            var response = await publishedFiles.AreFilesInSubscriptionList(request)
                .ToTask()
                .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
                .ConfigureAwait(false);
            var states = response.Body.files.ToDictionary(f => f.publishedfileid.ToString(), f => f.inlist);
            return new { states };
        }));
    }

    /// 订阅写入（SK3.3）：desiredState 单次写；App 侧凭 terminal 后的对账
    /// 查询确认结果。仅登录会话可写；未登录由 RequireAccountForQuery 拒绝。
    public void BeginSetSubscription(string requestId, ulong publishedFileId, bool subscribe)
    {
        RequireAccountForQuery(requestId, () => RunQueryAsync(requestId, async ct =>
        {
            EResult result;
            if (subscribe)
            {
                var request = new CPublishedFile_Subscribe_Request
                {
                    publishedfileid = publishedFileId,
                    list_type = 1,
                    appid = checked((int)ProtocolLimits.AppId),
                    notify_client = true,
                    include_dependencies = true,
                };
                var response = await publishedFiles.Subscribe(request)
                    .ToTask()
                    .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
                    .ConfigureAwait(false);
                result = response.Result;
            }
            else
            {
                var request = new CPublishedFile_Unsubscribe_Request
                {
                    publishedfileid = publishedFileId,
                    list_type = 1,
                    appid = checked((int)ProtocolLimits.AppId),
                    notify_client = true,
                };
                var response = await publishedFiles.Unsubscribe(request)
                    .ToTask()
                    .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
                    .ConfigureAwait(false);
                result = response.Result;
            }
            if (result != EResult.OK)
            {
                throw new IOException($"subscription write failed: {result}");
            }
            return new
            {
                workshopId = publishedFileId.ToString(),
                desiredState = subscribe ? "subscribe" : "unsubscribe",
                confirmed = true,
            };
        }));
    }

    // ---- 内部 ----

    private ulong OwnSteamId =>
        ulong.TryParse(SteamId, out var id) ? id : throw new IOException("not signed in");

    private void RequireAccountForQuery(string requestId, Action run)
    {
        if (string.IsNullOrEmpty(SteamId))
        {
            EmitQueryFailure(requestId, "accessDenied", "not signed in");
            return;
        }
        run();
    }

    private void RunQueryAsync(string requestId, Func<CancellationToken, Task<object>> work)
    {
        _ = Task.Run(async () =>
        {
            await QuerySlots.WaitAsync().ConfigureAwait(false);
            try
            {
                using var timeout = new CancellationTokenSource(
                    TimeSpan.FromSeconds(ProtocolLimits.RequestTimeoutSeconds + 10));
                // 查询会话保证：连接 +（未登录时）匿名会话。统一消息在仅连接、
                // 无任何会话时作业会被服务端拒绝（SK3.1 实测）。
                await EnsureQuerySessionAsync(timeout.Token).ConfigureAwait(false);
                var payload = await work(timeout.Token).ConfigureAwait(false);
                if (terminals.TryBegin(requestId))
                {
                    writer.Send(ProtocolMessages.ResultOk(requestId, payload, ProcessEpoch));
                }
            }
            catch (OperationCanceledException)
            {
                EmitQueryFailure(requestId, "network", "query timed out");
            }
            catch (Exception error)
            {
                EmitQueryFailure(requestId, ClassifyQueryError(error), ProtocolRedactor.Redact(error.Message));
            }
            finally
            {
                QuerySlots.Release();
            }
        }, CancellationToken.None);
    }

    private void EmitQueryFailure(string requestId, string code, string message)
    {
        if (!terminals.TryBegin(requestId)) return;
        writer.Send(ProtocolMessages.ResultError(requestId, code, message, ProcessEpoch));
    }

    private static string ClassifyQueryError(Exception error)
    {
        var message = error.Message;
        if (message.Contains("RateLimited", StringComparison.OrdinalIgnoreCase)
            || message.Contains("rate limit", StringComparison.OrdinalIgnoreCase))
        {
            return "rateLimited";
        }
        if (error is InvalidOperationException or ArgumentException)
        {
            return "unsupportedQuery";
        }
        return "network";
    }

    /// 统一条目映射：consumerAppID 强校验；result!=1 进 partial 错误列表。
    private static (List<object> Items, int WrongApp, List<object> PartialErrors) MapItems(
        IEnumerable<PublishedFileDetails> files)
    {
        var items = new List<object>();
        var partialErrors = new List<object>();
        var wrongApp = 0;
        foreach (var file in files)
        {
            if (file.result != (uint)EResult.OK)
            {
                partialErrors.Add(new
                {
                    publishedfileid = file.publishedfileid.ToString(),
                    code = "unsupportedContent",
                    result = (int)file.result,
                });
                continue;
            }
            if (file.consumer_appid != ProtocolLimits.AppId)
            {
                wrongApp += 1;
                continue;
            }
            items.Add(new
            {
                publishedfileid = file.publishedfileid.ToString(),
                title = file.title,
                previewUrl = string.IsNullOrEmpty(file.preview_url) ? null : file.preview_url,
                fileSize = file.file_size,
                timeUpdated = file.time_updated,
                timeCreated = file.time_created,
                timeSubscribed = file.time_subscribed,
                consumerAppid = file.consumer_appid,
                fileType = file.file_type,
                hcontentFile = file.hcontent_file.ToString(),
                tags = file.tags?.Select(t => t.tag).Where(t => !string.IsNullOrEmpty(t)).Take(8).ToArray(),
            });
        }
        return (items, wrongApp, partialErrors);
    }

    private async Task<(uint Total, ICollection<PublishedFileDetails> Files)> GetUserFilesInternalAsync(
        ulong steamId, string type, uint page, bool idsOnly, CancellationToken ct)
    {
        if (page == 0) page = 1;
        var request = new CPublishedFile_GetUserFiles_Request
        {
            steamid = steamId,
            appid = ProtocolLimits.AppId,
            page = page,
            numperpage = QueryPageSize,
            type = type,
            ids_only = idsOnly,
        };
        var response = await publishedFiles.GetUserFiles(request)
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        return (response.Body.total, response.Body.publishedfiledetails);
    }
}
