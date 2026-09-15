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
                return_children = true,
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
            RequireQuerySuccess(response.Result);
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
            var request = new CPublishedFile_GetDetails_Request
            {
                appid = ProtocolLimits.AppId,
                includetags = true,
                includemetadata = true,
                includechildren = true,
            };
            foreach (var id in ids)
            {
                request.publishedfileids.Add(id);
            }
            var response = await publishedFiles.GetDetails(request)
                .ToTask()
                .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
                .ConfigureAwait(false);
            RequireQuerySuccess(response.Result);
            var (items, wrongApp, errorEntries) = MapItems(response.Body.publishedfiledetails);
            return new
            {
                page = 0, total = ids.Count, hasMore = false,
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

    public void BeginListSubscriptions(string requestId, uint page, long? requestedEpoch)
    {
        RequireAccountForQuery(requestId, requestedEpoch, lease => RunQueryAsync(requestId, async ct =>
        {
            var (total, files) = await GetUserFilesInternalAsync(lease.SteamId, "mysubscriptions", page, idsOnly: false, ct, lease)
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
        }, lease));
    }

    public void BeginListFavorites(string requestId, uint page, long? requestedEpoch)
    {
        RequireAccountForQuery(requestId, requestedEpoch, lease => RunQueryAsync(requestId, async ct =>
        {
            var (total, files) = await GetUserFilesInternalAsync(lease.SteamId, "myfavorites", page, idsOnly: true, ct, lease)
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
        }, lease));
    }

    public void BeginQuerySubscriptionStates(string requestId, IReadOnlyList<ulong> ids, long? requestedEpoch)
    {
        if (ids.Count == 0 || ids.Count > 100)
        {
            EmitQueryFailure(requestId, "unsupportedQuery", "ids out of range");
            return;
        }
        RequireAccountForQuery(requestId, requestedEpoch, lease => RunQueryAsync(requestId, async ct =>
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
            var response = await SendForAccount(lease, () => publishedFiles.AreFilesInSubscriptionList(request), ct)
                .ToTask()
                .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
                .ConfigureAwait(false);
            RequireQuerySuccess(response.Result);
            var states = response.Body.files.ToDictionary(f => f.publishedfileid.ToString(), f => f.inlist);
            return new { states };
        }, lease));
    }

    /// 订阅写入（SK3.3）：desiredState 单次写；App 侧凭 terminal 后的对账
    /// 查询确认结果。仅登录会话可写；未登录由 RequireAccountForQuery 拒绝。
    public void BeginSetSubscription(string requestId, ulong publishedFileId, bool subscribe, long? requestedEpoch)
    {
        RequireAccountForQuery(requestId, requestedEpoch, lease => RunQueryAsync(requestId, async ct =>
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
                var response = await SendForAccount(lease, () => publishedFiles.Subscribe(request), ct)
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
                var response = await SendForAccount(lease, () => publishedFiles.Unsubscribe(request), ct)
                    .ToTask()
                    .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
                    .ConfigureAwait(false);
                result = response.Result;
            }
            if (result != EResult.OK)
            {
                throw SteamRequestFailure.FromResult(result);
            }
            return new
            {
                workshopId = publishedFileId.ToString(),
                desiredState = subscribe ? "subscribe" : "unsubscribe",
                confirmed = true,
            };
        }, lease));
    }

    // ---- 内部 ----

    // Immutable admission identity. No queued private operation reads a later account.
    internal sealed record AccountLease(long Epoch, long Connection, ulong SteamId, CancellationToken Disconnected);

    private AccountLease CaptureAccountLocked(long? requestedEpoch)
    {
        if (requestedEpoch != accountEpoch || !isLoggedIn || !ulong.TryParse(steamId, out var id))
            throw new AccountChangedException();
        return new(accountEpoch, connectionGeneration, id, lifetime?.Token ?? CancellationToken.None);
    }

    private void ValidateAccountLocked(AccountLease lease)
    {
        if (CaptureAccountLocked(lease.Epoch) != lease) throw new AccountChangedException();
    }

    private sealed class AccountChangedException : Exception { }

    private T SendForAccount<T>(AccountLease lease, Func<T> send, CancellationToken ct)
    {
        lock (gate)
        {
            ct.ThrowIfCancellationRequested();
            ValidateAccountLocked(lease);
            return send(); // synchronous SteamKit enqueue and account transition share gate
        }
    }

    private void RequireAccountForQuery(string requestId, long? requestedEpoch, Action<AccountLease> run)
    {
        lock (gate)
        {
            try { run(CaptureAccountLocked(requestedEpoch)); }
            catch (AccountChangedException)
            {
                EmitQueryFailure(requestId, "accessDenied", "account is not online for this epoch", requestedEpoch);
            }
        }
    }

    private void RunQueryAsync(string requestId, Func<CancellationToken, Task<object>> work, AccountLease? lease = null)
    {
        _ = Task.Run(async () =>
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
                lease?.Disconnected ?? CancellationToken.None);
            timeout.CancelAfter(TimeSpan.FromSeconds(ProtocolLimits.RequestTimeoutSeconds));
            var acquired = false;
            try
            {
                await QuerySlots.WaitAsync(timeout.Token).ConfigureAwait(false);
                acquired = true;
                // 查询会话保证：连接 +（未登录时）匿名会话。统一消息在仅连接、
                // 无任何会话时作业会被服务端拒绝（SK3.1 实测）。
                if (lease == null) await EnsureQuerySessionAsync(timeout.Token).ConfigureAwait(false);
                else { lock (gate) ValidateAccountLocked(lease); }
                var payload = await work(timeout.Token).ConfigureAwait(false);
                lock (gate)
                {
                    if (lease != null) ValidateAccountLocked(lease);
                    if (terminals.TryBegin(requestId))
                        writer.Send(ProtocolMessages.ResultOk(requestId, payload, ProcessEpoch, lease?.Epoch));
                }
            }
            catch (AccountChangedException)
            {
                EmitQueryFailure(requestId, "cancelled", "account changed", lease?.Epoch);
            }
            catch (OperationCanceledException)
            {
                EmitQueryFailure(requestId,
                    lease?.Disconnected.IsCancellationRequested == true ? "cancelled" : "network",
                    lease?.Disconnected.IsCancellationRequested == true ? "account changed" : "query timed out", lease?.Epoch);
            }
            catch (Exception error)
            {
                EmitQueryFailure(requestId, ClassifyQueryError(error), ProtocolRedactor.Redact(error.Message), lease?.Epoch);
            }
            finally
            {
                if (acquired) QuerySlots.Release();
            }
        }, CancellationToken.None);
    }

    private void EmitQueryFailure(string requestId, string code, string message, long? epoch = null)
    {
        if (!terminals.TryBegin(requestId)) return;
        writer.Send(ProtocolMessages.ResultError(requestId, code, message, ProcessEpoch, epoch));
    }

    private static string ClassifyQueryError(Exception error)
    {
        if (error is SteamRequestFailure failure) return failure.Code;
        if (error is InvalidDataException) return "protocolMismatch";
        if (error is InvalidOperationException or ArgumentException)
        {
            return "unsupportedQuery";
        }
        return "network";
    }

    internal static void RequireQuerySuccess(EResult result)
    {
        if (result != EResult.OK) throw SteamRequestFailure.FromResult(result);
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
                creatorSteamId = file.creator == 0 ? null : file.creator.ToString(),
                title = file.title,
                description = file.file_description,
                previewUrl = string.IsNullOrEmpty(file.preview_url) ? null : file.preview_url,
                fileSize = file.file_size,
                timeUpdated = file.time_updated,
                timeCreated = file.time_created,
                timeSubscribed = file.time_subscribed,
                consumerAppid = file.consumer_appid,
                visibility = (int)file.visibility,
                banned = file.banned,
                banReason = string.IsNullOrEmpty(file.ban_reason) ? null : file.ban_reason,
                subscriptions = file.subscriptions,
                favorited = file.favorited,
                lifetimeSubscriptions = file.lifetime_subscriptions,
                lifetimeFavorited = file.lifetime_favorited,
                views = file.views,
                dependencyIds = file.children?
                    .Select(child => child.publishedfileid)
                    .Where(id => id != 0)
                    .Distinct()
                    .Select(id => id.ToString())
                    .ToArray() ?? [],
                fileType = file.file_type,
                hcontentFile = file.hcontent_file.ToString(),
                tags = file.tags?.Select(t => t.tag).Where(t => !string.IsNullOrEmpty(t)).ToArray(),
            });
        }
        return (items, wrongApp, partialErrors);
    }

    private async Task<(uint Total, ICollection<PublishedFileDetails> Files)> GetUserFilesInternalAsync(
        ulong steamId, string type, uint page, bool idsOnly, CancellationToken ct, AccountLease? lease = null)
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
            return_children = !idsOnly,
        };
        var job = lease == null ? publishedFiles.GetUserFiles(request)
            : SendForAccount(lease, () => publishedFiles.GetUserFiles(request), ct);
        var response = await job.ToTask()
            .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        RequireQuerySuccess(response.Result);
        return (response.Body.total, response.Body.publishedfiledetails);
    }
}
