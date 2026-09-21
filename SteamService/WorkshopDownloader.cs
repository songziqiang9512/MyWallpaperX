using System.Collections.Concurrent;
using System.Net.Http;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Buffers.Binary;
using System.Globalization;
using SteamKit2;
using SteamKit2.CDN;
using SteamKit2.Internal;

namespace SteamService;

// SK4.2：真实下载作业（SteamSession partial 第三部分）。
//
// 合同（§5.1/§5.2/§4.2）：
// - 链路：GetDetails → workshopdepot(PICS) → depot key → manifest request
//   code("public") → manifest → 有界 chunk 并行下载 → 逐 chunk Adler 校验 →
//   project.json 存在性检查 → stagedComplete terminal。
// - 路径合同：只写 App 下发的 stagingRoot 之内；绝对路径/逃逸/符号链接拒绝。
// - 预算：manifest 总字节 ≤8 GiB、文件数 ≤200k；chunk 超时 60s 有界。
// - 进度：downloadProgress 事件 ≤4Hz 合并；总量/已验证字节/阶段分别上报，
//   压缩字节不混入分母。
// - 取消：cancelDownload 触发 CTS，写入终止，terminal=cancelled；每
//   requestId 终态唯一由 TerminalTracker 守卫。
// - 只产出 staged 内容；入库/ready 由 SK4.3 的 App 侧事务负责。
internal sealed partial class SteamSession
{
    internal const int MaxActiveDownloadJobs = 2;
    internal const int MaxConcurrentDownloadChunks = 4;
    private const int DownloadWorkersPerJob = 4;
    private const long MaxStagedBytes = 8L * 1024 * 1024 * 1024;
    private const long DiskSafetyReserveBytes = 256L * 1024 * 1024;
    private const int MaxStagedFiles = 200_000;
    /// Steam CDN 实际 chunk ≤1 MiB；这是恶意/异常 manifest 的 OOM 围栏（§3 硬拒绝最小 unsafe unit）。
    private const long MaxChunkBytes = 64L * 1024 * 1024;
    /// §5.3：CDN 失败有 backoff 与上限；每个 chunk 至多重试 3 次有界网络类失败。
    internal const int MaxChunkDownloadAttempts = 3;
    internal const string StagingAcknowledgementCapability = "download-staging-ack-v2";
    internal const int StagingAcknowledgementTimeoutSeconds = 30;

    /// SK4.2 依赖的会话处理器；EnsureSession 统一创建（SteamSession partial 共享）。
    private SteamApps apps = null!;
    private SteamContent content = null!;

    private readonly object downloadGate = new();
    private readonly Dictionary<string, ActiveDownload> activeDownloads = new();
    private readonly SemaphoreSlim downloadChunkSlots = new(
        MaxConcurrentDownloadChunks,
        MaxConcurrentDownloadChunks);

    private sealed class ActiveDownload
    {
        public required string JobId;
        public required string RequestId;
        public required string StagingRoot;
        public string? StagingPath;
        public string? StagingManifestId;
        public string? StagingDevice;
        public string? StagingInode;
        public string? StagingBirthSeconds;
        public string? StagingBirthNanoseconds;
        public string? ResumeStagingPath;
        public ulong? ResumeManifestId;
        public int? ResumeStagingDevice;
        public ulong? ResumeStagingInode;
        public long? ResumeStagingBirthSeconds;
        public long? ResumeStagingBirthNanoseconds;
        public required ulong PublishedFileId;
        public required CancellationTokenSource Cancellation;
        public required AccountLease Account;
        public required SteamClient Source;
        public readonly DownloadProgressState Progress = new();
        public readonly TaskCompletionSource<bool> StagingAcknowledgement = new(
            TaskCreationOptions.RunContinuationsAsynchronously);
        public long ReservedStagingBytes; // guarded by downloadGate
        public bool TerminalDecided; // guarded by downloadGate, shared with cancellation acceptance
    }

    public void BeginStartDownload(
        string requestId,
        string jobId,
        ulong publishedFileId,
        string stagingRoot,
        long? requestedEpoch,
        string? resumeStagingPath = null,
        ulong? resumeManifestId = null,
        int? resumeStagingDevice = null,
        ulong? resumeStagingInode = null,
        long? resumeStagingBirthSeconds = null,
        long? resumeStagingBirthNanoseconds = null)
    {
        ActiveDownload context;
        lock (gate)
        {
            AccountLease lease;
            try { lease = CaptureAccountLocked(requestedEpoch); }
            catch (AccountChangedException)
            {
                EmitQueryFailure(requestId, "accessDenied", "download requires current account", requestedEpoch);
                return;
            }
            lock (downloadGate)
            {
                if (!DownloadJobCapacityAvailableLocked())
                {
                    EmitQueryFailure(requestId, "rateLimited", "download job capacity reached", requestedEpoch);
                    return;
                }
                if (string.IsNullOrWhiteSpace(stagingRoot) || !Path.IsPathRooted(stagingRoot))
                {
                    EmitQueryFailure(requestId, "protocolMismatch", "stagingRoot must be an absolute path");
                    return;
                }
                context = new ActiveDownload
                {
                    JobId = jobId,
                    RequestId = requestId,
                    StagingRoot = stagingRoot,
                    ResumeStagingPath = resumeStagingPath,
                    ResumeManifestId = resumeManifestId,
                    ResumeStagingDevice = resumeStagingDevice,
                    ResumeStagingInode = resumeStagingInode,
                    ResumeStagingBirthSeconds = resumeStagingBirthSeconds,
                    ResumeStagingBirthNanoseconds = resumeStagingBirthNanoseconds,
                    PublishedFileId = publishedFileId,
                    Cancellation = new CancellationTokenSource(),
                    Account = lease,
                    Source = client!,
                };
                activeDownloads.Add(jobId, context);
            }
        }

        var cancellation = context.Cancellation;
        _ = Task.Run(async () =>
        {
            try
            {
                EmitDownloadProgress(context, "resolving");
                lock (gate) ValidateAccountLocked(context.Account);
                cancellation.Token.ThrowIfCancellationRequested();

                var detail = await GetDetailsInternalAsync(context.Source, publishedFileId, cancellation.Token)
                    .ConfigureAwait(false);
                if (detail.result != (uint)EResult.OK)
                {
                    throw SteamRequestFailure.FromResult((EResult)detail.result);
                }
                if (detail.consumer_appid != ProtocolLimits.AppId)
                {
                    throw new SteamRequestFailure("unsupportedContent", "item does not belong to Wallpaper Engine");
                }
                if (detail.hcontent_file == 0)
                {
                    throw new SteamRequestFailure("unsupportedContent", "item has no content manifest");
                }
                var stagingManifestId = detail.hcontent_file.ToString(CultureInfo.InvariantCulture);
                if (context.ResumeManifestId is ulong expectedManifest
                    && expectedManifest != detail.hcontent_file)
                {
                    throw new SteamRequestFailure("integrity", "staging manifest changed");
                }

                var depotId = await GetWorkshopDepotIdInternalAsync(context.Source, cancellation.Token).ConfigureAwait(false);
                var depotKey = await GetDepotDecryptionKeyInternalAsync(context.Source, depotId, cancellation.Token)
                    .ConfigureAwait(false);
                var requestCode = await GetManifestRequestCodeInternalAsync(context.Source, depotId, detail.hcontent_file, cancellation.Token)
                    .ConfigureAwait(false);
                var server = await GetContentServerInternalAsync(context.Source, cancellation.Token).ConfigureAwait(false);

                EmitDownloadProgress(context, "manifest");
                DepotManifest manifest;
                using (var manifestCdnClient = new SteamKit2.CDN.Client(context.Source))
                {
                    manifest = await AwaitPhysicalOperation(
                        manifestCdnClient.DownloadManifestAsync(depotId, detail.hcontent_file, requestCode, server, depotKey),
                        manifestCdnClient.Dispose,
                        TimeSpan.FromSeconds(ProtocolLimits.ManifestTimeoutSeconds), cancellation.Token)
                        .ConfigureAwait(false);
                }

                var files = manifest.Files ?? throw new InvalidDataException("manifest has no file list.");
                var admitted = WorkshopManifestValidation.Validate(files,
                    MaxStagedBytes, MaxStagedFiles, MaxChunkBytes, cancellation.Token);
                var manifestTotalBytes = admitted.Bytes;
                var totalChunks = admitted.Chunks;

                EmitDownloadProgress(context, "preparing", totalBytes: manifestTotalBytes, totalChunks: totalChunks);
                bool resuming = context.ResumeStagingPath != null;
                using var lease = resuming
                    ? WorkshopStagingLease.Resume(
                        stagingRoot,
                        context.ResumeStagingPath!,
                        context.ResumeStagingDevice!.Value,
                        context.ResumeStagingInode!.Value,
                        context.ResumeStagingBirthSeconds!.Value,
                        context.ResumeStagingBirthNanoseconds!.Value)
                    : new WorkshopStagingLease(stagingRoot);
                var staging = lease.Path;
                PublishStagingIdentity(
                    context,
                    staging,
                    stagingManifestId,
                    lease.Device.ToString(CultureInfo.InvariantCulture),
                    lease.Inode.ToString(CultureInfo.InvariantCulture),
                    lease.BirthSeconds.ToString(CultureInfo.InvariantCulture),
                    lease.BirthNanoseconds.ToString(CultureInfo.InvariantCulture));
                // Publish the exact helper-owned lease and stop before the first
                // content node/write until the App confirms durable JobStore identity.
                try
                {
                    EmitDownloadProgress(context, "allocated",
                        totalBytes: manifestTotalBytes, totalChunks: totalChunks);
                    await AwaitStagingAcknowledgementAsync(context, cancellation.Token)
                        .ConfigureAwait(false);
                }
                catch
                {
                    if (!resuming)
                    {
                        try { lease.RemoveUnacknowledgedIfEmpty(); }
                        catch (Exception cleanupError)
                        {
                            writer.SendDiagnostic($"unacknowledged staging cleanup failed: {cleanupError.Message}");
                        }
                    }
                    throw;
                }
                EmitDownloadProgress(context, "downloading",
                    totalBytes: manifestTotalBytes, totalChunks: totalChunks);

                var work = new ConcurrentQueue<(DepotManifest.FileData File, DepotManifest.ChunkData Chunk, string RelativePath)>();
                var missingFiles = new List<(string RelativePath, long Length)>();
                long missingBytes = 0;
                if (!resuming) ReserveStagingCapacity(context, manifestTotalBytes);
                foreach (var file in files)
                {
                    cancellation.Token.ThrowIfCancellationRequested();
                    if (file.Flags.HasFlag(EDepotFileFlag.Directory))
                    {
                        if (resuming) lease.ResumeDirectory(file.FileName);
                        else lease.CreateDirectory(file.FileName);
                        continue;
                    }
                    bool existing = resuming
                        ? lease.TryResumeFile(file.FileName, checked((long)file.TotalSize))
                        : false;
                    if (!resuming) lease.CreateFile(file.FileName, checked((long)file.TotalSize));
                    else if (!existing) missingFiles.Add((file.FileName, checked((long)file.TotalSize)));
                    foreach (var chunk in file.Chunks)
                    {
                        if (existing && IsStagedChunkValid(lease, file.FileName, chunk, cancellation.Token))
                        {
                            context.Progress.CompleteChunk(
                                checked((int)chunk.UncompressedLength),
                                update => SendDownloadProgress(context, update));
                        }
                        else
                        {
                            work.Enqueue((file, chunk, file.FileName));
                            missingBytes = checked(missingBytes + (long)chunk.UncompressedLength);
                        }
                    }
                }

                if (resuming)
                {
                    ReserveStagingCapacity(context, missingBytes);
                    foreach (var missing in missingFiles)
                        lease.CreateFile(missing.RelativePath, missing.Length);
                }

                var verifiedBytes = await DownloadChunksAsync(
                    context, lease, depotId, depotKey, server, work, totalChunks, cancellation.Token)
                    .ConfigureAwait(false);

                // §5.4：取消请求后不得再以成功收口（staged 未提交，取消优先）。
                cancellation.Token.ThrowIfCancellationRequested();
                EmitDownloadProgress(context, "validating",
                    totalBytes: manifestTotalBytes, totalChunks: totalChunks);
                string contentDigest;
                try { contentDigest = ValidateStagedFiles(files, lease, cancellation.Token); }
                catch (IOException error) { throw WorkshopStagingLease.ClassifyIO(error); }

                lease.VerifyPublicationPath();
                var projectJsonPresent = true; // root project.json was admitted and verified via its descriptor
                FinishDownloadSuccess(context, new
                {
                    receiptVersion = 2, contentDigest,
                    accountSteamId = context.Account.SteamId.ToString(),
                    jobId, stagedComplete = true, workshopId = publishedFileId.ToString(),
                    manifestId = detail.hcontent_file.ToString(), stagingPath = staging,
                    stagingDevice = context.StagingDevice, stagingInode = context.StagingInode,
                    stagingBirthSeconds = context.StagingBirthSeconds,
                    stagingBirthNanoseconds = context.StagingBirthNanoseconds,
                    verifiedBytes, totalBytes = manifestTotalBytes, projectJsonPresent,
                });
            }
            catch (Exception error) when (error is AccountChangedException ||
                                          error is OperationCanceledException && cancellation.IsCancellationRequested)
            {
                FinishSteamRequestFailure(context, "cancelled", "download cancelled");
            }
            catch (Exception error)
            {
                FinishSteamRequestFailure(context, ClassifyDownloadError(error), ProtocolRedactor.Redact(error.Message));
            }
            finally
            {
                lock (downloadGate)
                {
                    context.ReservedStagingBytes = 0;
                    activeDownloads.Remove(jobId);
                }
                context.Cancellation.Dispose();
            }
        }, CancellationToken.None);
    }

    public bool CancelDownload(string jobId)
    {
        lock (downloadGate)
        {
            if (!activeDownloads.TryGetValue(jobId, out var context) || context.TerminalDecided) return false;
            context.Cancellation.Cancel();
            return true;
        }
    }

    public bool AcknowledgeDownloadStaging(
        string jobId,
        string stagingPath,
        string manifestId,
        string stagingDevice,
        string stagingInode,
        string stagingBirthSeconds,
        string stagingBirthNanoseconds,
        long? requestedEpoch)
    {
        lock (downloadGate)
        {
            if (!activeDownloads.TryGetValue(jobId, out var context)
                || context.TerminalDecided || context.Cancellation.IsCancellationRequested
                || requestedEpoch == null || context.Account.Epoch != requestedEpoch
                || context.StagingPath != stagingPath
                || context.StagingManifestId != manifestId
                || context.StagingDevice != stagingDevice
                || context.StagingInode != stagingInode
                || context.StagingBirthSeconds != stagingBirthSeconds
                || context.StagingBirthNanoseconds != stagingBirthNanoseconds)
            {
                return false;
            }
            return context.StagingAcknowledgement.TrySetResult(true);
        }
    }

    private void PublishStagingIdentity(
        ActiveDownload context,
        string stagingPath,
        string manifestId,
        string stagingDevice,
        string stagingInode,
        string stagingBirthSeconds,
        string stagingBirthNanoseconds)
    {
        lock (downloadGate)
        {
            if (!activeDownloads.TryGetValue(context.JobId, out var active)
                || !ReferenceEquals(active, context) || context.TerminalDecided)
            {
                throw new SteamRequestFailure("integrity", "download staging owner changed");
            }
            context.Cancellation.Token.ThrowIfCancellationRequested();
            context.StagingPath = stagingPath;
            context.StagingManifestId = manifestId;
            context.StagingDevice = stagingDevice;
            context.StagingInode = stagingInode;
            context.StagingBirthSeconds = stagingBirthSeconds;
            context.StagingBirthNanoseconds = stagingBirthNanoseconds;
        }
    }

    private static async Task AwaitStagingAcknowledgementAsync(
        ActiveDownload context,
        CancellationToken cancellation,
        TimeSpan? timeout = null)
    {
        try
        {
            await context.StagingAcknowledgement.Task.WaitAsync(
                timeout ?? TimeSpan.FromSeconds(StagingAcknowledgementTimeoutSeconds), cancellation)
                .ConfigureAwait(false);
        }
        catch (TimeoutException)
        {
            throw new SteamRequestFailure("integrity", "staging acknowledgement timed out");
        }
    }

    private bool DownloadJobCapacityAvailableLocked() => activeDownloads.Count < MaxActiveDownloadJobs;

    private void ReserveStagingCapacity(ActiveDownload context, long requiredBytes)
    {
        lock (downloadGate)
        {
            long availableBytes;
            try { availableBytes = AvailableDiskBytes(context.StagingRoot); }
            catch (UnauthorizedAccessException)
            {
                throw new SteamRequestFailure("accessDenied", "staging disk capacity access denied");
            }
            catch (IOException)
            {
                throw new SteamRequestFailure("helperUnavailable", "staging disk capacity unavailable");
            }
            long reservedBytes = 0;
            foreach (var active in activeDownloads.Values)
            {
                if (!ReferenceEquals(active, context))
                    reservedBytes = checked(reservedBytes + active.ReservedStagingBytes);
            }
            if (!CanReserveDiskBytes(requiredBytes, availableBytes, reservedBytes))
                throw new WorkshopStagingLease.Failure(
                    "diskFull", "insufficient staging space; partial download retained");
            context.ReservedStagingBytes = requiredBytes;
        }
    }

    private static long AvailableDiskBytes(string path)
    {
        var full = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var drive = DriveInfo.GetDrives()
            .Where(candidate =>
            {
                var root = candidate.RootDirectory.FullName.TrimEnd(Path.DirectorySeparatorChar)
                    + Path.DirectorySeparatorChar;
                return full.StartsWith(root, StringComparison.Ordinal);
            })
            .OrderByDescending(candidate => candidate.RootDirectory.FullName.Length)
            .FirstOrDefault() ?? throw new IOException("staging volume unavailable");
        return drive.AvailableFreeSpace;
    }

    internal static long AvailableDiskBytesForTest(string path) => AvailableDiskBytes(path);

    internal static bool CanReserveDiskBytes(long requiredBytes, long availableBytes, long alreadyReservedBytes) =>
        requiredBytes >= 0 && requiredBytes <= MaxStagedBytes
            && availableBytes >= 0 && alreadyReservedBytes >= 0
            && alreadyReservedBytes <= availableBytes
            && requiredBytes <= availableBytes - alreadyReservedBytes
            && DiskSafetyReserveBytes <= availableBytes - alreadyReservedBytes - requiredBytes;

    private void FinishDownloadSuccess(ActiveDownload context, object receipt)
    {
        lock (gate)
        lock (downloadGate)
        {
            context.Cancellation.Token.ThrowIfCancellationRequested();
            ValidateAccountLocked(context.Account);
            context.TerminalDecided = true;
            // The original startDownload terminal is the App's physical-drain
            // acknowledgement. Retire ownership before publishing it so a next
            // job cannot race this finally block and observe a false busy state.
            activeDownloads.Remove(context.JobId);
            if (terminals.TryBegin(context.RequestId))
                writer.Send(ProtocolMessages.ResultOk(context.RequestId, receipt, ProcessEpoch, context.Account.Epoch));
        }
    }

    private void FinishSteamRequestFailure(ActiveDownload context, string code, string message)
    {
        lock (downloadGate)
        {
            // An accepted cancel wins until the terminal decision. Success uses the same lock.
            if (context.Cancellation.IsCancellationRequested) { code = "cancelled"; message = "download cancelled"; }
            context.TerminalDecided = true;
            activeDownloads.Remove(context.JobId);
            if (terminals.TryBegin(context.RequestId))
                writer.Send(ProtocolMessages.ResultError(context.RequestId, code, message, ProcessEpoch, context.Account.Epoch));
        }
    }

    private void EmitDownloadProgress(ActiveDownload context, string stage,
        long? totalBytes = null, int? totalChunks = null)
    {
        context.Progress.Publish(stage, totalBytes, totalChunks, update => SendDownloadProgress(context, update));
    }

    private void SendDownloadProgress(ActiveDownload context, DownloadProgressState.Snapshot update)
    {
        writer.Send(new
        {
            v = ProtocolLimits.Version, type = "event", @event = "downloadProgress",
            requestId = context.RequestId, processEpoch = ProcessEpoch, accountEpoch = context.Account.Epoch,
            jobId = context.JobId, sequence = update.Sequence, stage = update.Stage,
            stagingPath = context.StagingPath, manifestId = context.StagingManifestId,
            stagingDevice = context.StagingDevice, stagingInode = context.StagingInode,
            stagingBirthSeconds = context.StagingBirthSeconds,
            stagingBirthNanoseconds = context.StagingBirthNanoseconds,
            totalBytes = update.TotalBytes, verifiedBytes = update.VerifiedBytes,
            totalChunks = update.TotalChunks, verifiedChunks = update.VerifiedChunks,
        });
    }

    internal static string ClassifyDownloadError(Exception error) => error switch
    {
        SteamRequestFailure failure => failure.Code,
        WorkshopStagingLease.Failure failure => failure.Code,
        WorkshopManifestValidation.Rejected => "unsupportedContent",
        InvalidDataException => "integrity",
        UnauthorizedAccessException => "accessDenied",
        TimeoutException or OperationCanceledException or IOException => "network",
        _ => "unsupportedContent",
    };

}

// ---- 会话原语与 chunk 下载/校验（partial 续） ----
internal sealed partial class SteamSession
{
    private async Task<PublishedFileDetails> GetDetailsInternalAsync(SteamClient source, ulong publishedFileId, CancellationToken ct)
    {
        var request = new CPublishedFile_GetDetails_Request { appid = ProtocolLimits.AppId };
        request.publishedfileids.Add(publishedFileId);
        ct.ThrowIfCancellationRequested();
        var response = await source.GetHandler<SteamUnifiedMessages>()!.CreateService<PublishedFile>().GetDetails(request)
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        if (response.Result != EResult.OK) throw SteamRequestFailure.FromResult(response.Result);
        return response.Body.publishedfiledetails.FirstOrDefault(item => item.publishedfileid == publishedFileId)
            ?? throw new SteamRequestFailure("unsupportedContent", "GetDetails returned no entry.");
    }

    private async Task<uint> GetWorkshopDepotIdInternalAsync(SteamClient source, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        var tokens = await source.GetHandler<SteamApps>()!.PICSGetAccessTokens([ProtocolLimits.AppId], [])
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        var request = new SteamApps.PICSRequest(ProtocolLimits.AppId);
        if (tokens.AppTokens.TryGetValue(ProtocolLimits.AppId, out var token)) request.AccessToken = token;
        ct.ThrowIfCancellationRequested();
        var response = await source.GetHandler<SteamApps>()!.PICSGetProductInfo([request], [])
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        var info = response.Results?.Select(r => r.Apps)
            .FirstOrDefault(a => a.ContainsKey(ProtocolLimits.AppId))
            ?? throw new IOException("PICS product info unavailable.");
        var depot = info[ProtocolLimits.AppId].KeyValues["depots"]["workshopdepot"].AsUnsignedInteger();
        return depot != 0 ? depot : throw new IOException("workshopdepot missing.");
    }

    private async Task<byte[]> GetDepotDecryptionKeyInternalAsync(SteamClient source, uint depotId, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        var result = await source.GetHandler<SteamApps>()!.GetDepotDecryptionKey(depotId, ProtocolLimits.AppId)
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        if (result.Result != EResult.OK)
        {
            throw SteamRequestFailure.FromResult(result.Result);
        }
        return result.DepotKey;
    }

    private async Task<ulong> GetManifestRequestCodeInternalAsync(SteamClient source, uint depotId, ulong manifestId, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        var code = await source.GetHandler<SteamContent>()!.GetManifestRequestCode(depotId, ProtocolLimits.AppId, manifestId, "public")
            .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        return code != 0 ? code : throw new SteamRequestFailure("accessDenied", "manifest request code unavailable.");
    }

    private async Task<Server> GetContentServerInternalAsync(SteamClient source, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        var servers = await source.GetHandler<SteamContent>()!.GetServersForSteamPipe()
            .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        var eligible = servers
            .Where(s => !string.IsNullOrWhiteSpace(s.Host)
                && (s.AllowedAppIds.Length == 0 || s.AllowedAppIds.Contains(ProtocolLimits.AppId))
                && (s.Type == "CDN" || s.Type == "SteamCache"))
            .OrderBy(s => s.WeightedLoad)
            .ToList();
        return eligible.Count > 0
            ? eligible[0]
            : throw new IOException("no eligible content server.");
    }

    private async Task<long> DownloadChunksAsync(
        ActiveDownload context,
        WorkshopStagingLease lease,
        uint depotId,
        byte[] depotKey,
        Server server,
        ConcurrentQueue<(DepotManifest.FileData File, DepotManifest.ChunkData Chunk, string RelativePath)> work,
        int totalChunks,
        CancellationToken ct)
    {
        var workers = Enumerable.Range(0, Math.Min(DownloadWorkersPerJob, Math.Max(1, totalChunks)))
            .Select(_ => Task.Run(() => ChunkWorkerAsync(
                context, lease, depotId, depotKey, server, work, ct)))
            .ToArray();
        await Task.WhenAll(workers).ConfigureAwait(false);
        return context.Progress.VerifiedBytes;
    }

    private async Task ChunkWorkerAsync(
        ActiveDownload context,
        WorkshopStagingLease lease,
        uint depotId,
        byte[] depotKey,
        Server server,
        ConcurrentQueue<(DepotManifest.FileData File, DepotManifest.ChunkData Chunk, string RelativePath)> work,
        CancellationToken ct)
    {
        using var workerClient = new SteamKit2.CDN.Client(context.Source);
        // §5.3：CDN 失败有 backoff 与上限。超时/传输取消已由 AwaitPhysicalOperation
        // 释放当前 CDN 连接，因此 worker 持有可替换的当前客户端；重试上限
        // MaxChunkDownloadAttempts，权限/完整性类失败不重试（§5.3 不无限换服务器）。
        SteamKit2.CDN.Client client = workerClient;
        try
        {
            while (work.TryDequeue(out var item))
            {
                ct.ThrowIfCancellationRequested();
                await WithDownloadChunkSlot(async () =>
                {
                    ct.ThrowIfCancellationRequested();
                    var buffer = new byte[item.Chunk.UncompressedLength];
                    int written;
                    for (int attempt = 1; ; attempt++)
                    {
                        try
                        {
                            written = await AwaitPhysicalOperation(
                                client.DownloadDepotChunkAsync(depotId, item.Chunk, server, buffer, depotKey),
                                client.Dispose,
                                TimeSpan.FromSeconds(ProtocolLimits.ChunkTimeoutSeconds), ct).ConfigureAwait(false);
                            break;
                        }
                        catch (Exception error) when (attempt < MaxChunkDownloadAttempts
                            && IsRetryableChunkFetch(error, ct))
                        {
                            var previous = client;
                            client = new SteamKit2.CDN.Client(context.Source);
                            if (!ReferenceEquals(previous, workerClient)) previous.Dispose();
                            await Task.Delay(ChunkRetryBackoffDelay(attempt), ct).ConfigureAwait(false);
                        }
                    }
                    if (written != (int)item.Chunk.UncompressedLength)
                    {
                        throw new InvalidDataException($"short chunk read: {written}/{item.Chunk.UncompressedLength}");
                    }
                    // §5.4 取消语义：停止取新 chunk，但已到手的写入要排空完成，
                    // 不撕裂已校验的 chunk（staging 为本地盘，单 chunk 写入有界）。
                    using (var handle = lease.OpenFile(item.RelativePath, write: true))
                    {
                        try
                        {
                            await RandomAccess.WriteAsync(handle, buffer.AsMemory(0, written), (long)item.Chunk.Offset,
                                CancellationToken.None).ConfigureAwait(false);
                        }
                        catch (IOException error) { throw WorkshopStagingLease.ClassifyIO(error); }
                    }
                    lock (downloadGate)
                        context.ReservedStagingBytes = RemainingReservation(context.ReservedStagingBytes, written);
                    context.Progress.CompleteChunk(written, update => SendDownloadProgress(context, update));
                    return written;
                }, ct).ConfigureAwait(false);
            }
        }
        finally
        {
            if (!ReferenceEquals(client, workerClient)) client.Dispose();
        }
    }

    /// Only bounded network-class chunk fetch failures are retried; access denied
    /// must surface as a session/permission decision and integrity as a terminal.
    internal static bool IsRetryableChunkFetch(Exception error, CancellationToken ct)
    {
        if (ct.IsCancellationRequested) return false;
        return error switch
        {
            SteamRequestFailure failure => failure.Code is "network" or "rateLimited",
            WorkshopStagingLease.Failure or InvalidDataException => false,
            TimeoutException or OperationCanceledException or IOException
                or HttpRequestException or SocketException => true,
            _ => false,
        };
    }

    internal static TimeSpan ChunkRetryBackoffDelay(int attempt) => TimeSpan.FromMilliseconds(attempt switch
    {
        1 => 500,
        _ => 2000,
    });

    internal static long RemainingReservation(long reserved, long written) =>
        written >= 0 && written <= reserved ? reserved - written
            : throw new InvalidDataException("staging reservation accounting mismatch");

    // WaitAsync only cancels the waiter. Disposing the CDN transport requests
    // network cancellation; the original task still owns decryption buffers and
    // must finish before the chunk slot or download terminal can be released.
    internal static async Task<T> AwaitPhysicalOperation<T>(
        Task<T> operation, Action cancelTransport, TimeSpan timeout, CancellationToken ct)
    {
        try { return await operation.WaitAsync(timeout, ct).ConfigureAwait(false); }
        catch (Exception error) when (error is TimeoutException or OperationCanceledException)
        {
            try { cancelTransport(); }
            finally
            {
                try { await operation.ConfigureAwait(false); }
                catch { /* Observe physical termination; preserve the original cancellation/timeout. */ }
            }
            throw;
        }
    }

    internal static string ValidateStagedFiles(
        IReadOnlyList<DepotManifest.FileData> files, WorkshopStagingLease lease, CancellationToken ct)
    {
        using var tree = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        // Canonical NFC UTF-8 path order; cross-language receipt digest v2.
        foreach (var file in files.Where(f => !f.Flags.HasFlag(EDepotFileFlag.Directory))
            .OrderBy(f => Convert.ToHexString(Encoding.UTF8.GetBytes(f.FileName.Replace('\\', '/').Normalize())), StringComparer.Ordinal))
        {
            ct.ThrowIfCancellationRequested();
            using var stream = new FileStream(lease.OpenFile(file.FileName, write: false), FileAccess.Read);
            if ((ulong)stream.Length != file.TotalSize) throw new InvalidDataException("staged file length mismatch");
            using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            foreach (var chunk in file.Chunks.OrderBy(c => c.Offset))
            {
                ct.ThrowIfCancellationRequested();
                if (!IsChunkValid(stream, chunk, ct, hash))
                {
                    throw new InvalidDataException($"chunk validation failed: {file.FileName} @ {chunk.Offset}");
                }
            }
            var path = Encoding.UTF8.GetBytes(file.FileName.Replace('\\', '/').Normalize());
            var header = new byte[4];
            BinaryPrimitives.WriteUInt32LittleEndian(header, (uint)path.Length);
            tree.AppendData(header);
            tree.AppendData(path);
            var size = new byte[8];
            BinaryPrimitives.WriteUInt64LittleEndian(size, file.TotalSize);
            tree.AppendData(size);
            tree.AppendData(hash.GetHashAndReset());
        }
        return Convert.ToHexString(tree.GetHashAndReset()).ToLowerInvariant();
    }

    internal static bool IsChunkValid(Stream stream, DepotManifest.ChunkData chunk, CancellationToken ct, IncrementalHash hash)
    {
        if (chunk.UncompressedLength == 0) return true;
        if (chunk.Offset > (ulong)stream.Length || chunk.UncompressedLength > (ulong)stream.Length - chunk.Offset) return false;
        var buffer = new byte[chunk.UncompressedLength];
        stream.Position = (long)chunk.Offset;
        var read = 0;
        while (read < buffer.Length)
        {
            ct.ThrowIfCancellationRequested();
            int count;
            try { count = stream.Read(buffer, read, Math.Min(64 * 1024, buffer.Length - read)); }
            catch (IOException error) { throw WorkshopStagingLease.ClassifyIO(error); }
            if (count == 0) return false;
            read += count;
        }
        ct.ThrowIfCancellationRequested();
        hash.AppendData(buffer);
        return DepotChunk.AdlerHash(buffer) == chunk.Checksum;
    }

    private static bool IsStagedChunkValid(
        WorkshopStagingLease lease,
        string relativePath,
        DepotManifest.ChunkData chunk,
        CancellationToken ct)
    {
        using var stream = new FileStream(lease.OpenFile(relativePath, write: false), FileAccess.Read);
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        return IsChunkValid(stream, chunk, ct, hash);
    }

    private async Task<T> WithDownloadChunkSlot<T>(Func<Task<T>> body, CancellationToken ct)
    {
        await downloadChunkSlots.WaitAsync(ct).ConfigureAwait(false);
        try { return await body().ConfigureAwait(false); }
        finally { downloadChunkSlots.Release(); }
    }

    internal async Task<T> WithDownloadChunkSlotForTest<T>(Func<Task<T>> body, CancellationToken ct) =>
        await WithDownloadChunkSlot(body, ct).ConfigureAwait(false);
}
