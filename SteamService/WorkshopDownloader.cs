using System.Collections.Concurrent;
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
    private const int DownloadWorkersPerJob = 4;
    private const long MaxStagedBytes = 8L * 1024 * 1024 * 1024;
    private const int MaxStagedFiles = 200_000;
    private static readonly TimeSpan ProgressCoalesceInterval = TimeSpan.FromMilliseconds(250);

    /// SK4.2 依赖的会话处理器；EnsureSession 统一创建（SteamSession partial 共享）。
    private SteamApps apps = null!;
    private SteamContent content = null!;

    private readonly object downloadGate = new();
    private readonly Dictionary<string, ActiveDownload> activeDownloads = new();

    private sealed class ActiveDownload
    {
        public required string JobId;
        public required string RequestId;
        public required string StagingRoot;
        public required ulong PublishedFileId;
        public required CancellationTokenSource Cancellation;
        public int Sequence;
        public long LastProgressTick;
    }

    public void BeginStartDownload(string requestId, string jobId, ulong publishedFileId, string stagingRoot)
    {
        ActiveDownload context;
        lock (downloadGate)
        {
            if (activeDownloads.Values.Any(d => d.JobId == jobId))
            {
                EmitQueryFailure(requestId, "unsupportedQuery", "jobId already downloading");
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
                PublishedFileId = publishedFileId,
                Cancellation = new CancellationTokenSource(),
            };
            activeDownloads.Add(jobId, context);
        }

        var cancellation = context.Cancellation;
        _ = Task.Run(async () =>
        {
            try
            {
                EmitDownloadProgress(context, "resolving");
                await EnsureQuerySessionAsync(cancellation.Token).ConfigureAwait(false);

                var detail = await GetDetailsInternalAsync(publishedFileId, cancellation.Token)
                    .ConfigureAwait(false);
                if (detail.result != (uint)EResult.OK)
                {
                    throw new IOException($"GetDetails failed: {(EResult)detail.result}");
                }
                if (detail.consumer_appid != ProtocolLimits.AppId)
                {
                    EmitQueryFailure(requestId, "unsupportedContent", "item does not belong to Wallpaper Engine");
                    return;
                }
                if (detail.hcontent_file == 0)
                {
                    EmitQueryFailure(requestId, "unsupportedContent", "item has no content manifest");
                    return;
                }

                var depotId = await GetWorkshopDepotIdInternalAsync(cancellation.Token).ConfigureAwait(false);
                var depotKey = await GetDepotDecryptionKeyInternalAsync(depotId, cancellation.Token)
                    .ConfigureAwait(false);
                var requestCode = await GetManifestRequestCodeInternalAsync(depotId, detail.hcontent_file, cancellation.Token)
                    .ConfigureAwait(false);
                var server = await GetContentServerInternalAsync(cancellation.Token).ConfigureAwait(false);

                EmitDownloadProgress(context, "manifest");
                DepotManifest manifest;
                using (var manifestCdnClient = new SteamKit2.CDN.Client(client))
                {
                    manifest = await manifestCdnClient
                        .DownloadManifestAsync(depotId, detail.hcontent_file, requestCode, server, depotKey)
                        .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.ManifestTimeoutSeconds), cancellation.Token)
                        .ConfigureAwait(false);
                }

                var files = manifest.Files ?? throw new IOException("manifest has no file list.");
                if (files.Count == 0 || files.Count > MaxStagedFiles)
                {
                    throw new IOException($"manifest file count {files.Count} out of budget.");
                }

                var staging = ResolveContainedPath(stagingRoot, publishedFileId.ToString());
                Directory.CreateDirectory(staging);

                long manifestTotalBytes = 0;
                int totalChunks = 0;
                var work = new ConcurrentQueue<(DepotManifest.FileData File, DepotManifest.ChunkData Chunk, string Target)>();
                foreach (var file in files)
                {
                    if (file.Flags.HasFlag(EDepotFileFlag.Symlink))
                    {
                        throw new IOException("manifest contains symlink; refusing per path contract.");
                    }
                    var target = ResolveContainedPath(staging, file.FileName);
                    if (file.Flags.HasFlag(EDepotFileFlag.Directory))
                    {
                        Directory.CreateDirectory(target);
                        continue;
                    }
                    var parent = Path.GetDirectoryName(target);
                    if (!string.IsNullOrEmpty(parent)) Directory.CreateDirectory(parent);
                    using (var resize = new FileStream(target, FileMode.OpenOrCreate, FileAccess.Write, FileShare.ReadWrite))
                    {
                        resize.SetLength((long)file.TotalSize);
                    }
                    manifestTotalBytes += (long)file.TotalSize;
                    foreach (var chunk in file.Chunks)
                    {
                        totalChunks += 1;
                        work.Enqueue((file, chunk, target));
                    }
                }
                if (manifestTotalBytes > MaxStagedBytes)
                {
                    throw new IOException($"manifest total {manifestTotalBytes} bytes exceeds budget {MaxStagedBytes}.");
                }

                var verifiedBytes = await DownloadChunksAsync(
                    context, depotId, depotKey, work, totalChunks, cancellation.Token)
                    .ConfigureAwait(false);

                EmitDownloadProgress(context, "validating",
                    totalBytes: manifestTotalBytes, verifiedBytes: verifiedBytes, totalChunks: totalChunks);
                ValidateStagedFiles(files, staging);

                var projectJsonPath = Path.Combine(staging, "project.json");
                var projectJsonPresent = File.Exists(projectJsonPath);
                if (terminals.TryBegin(requestId))
                {
                    writer.Send(ProtocolMessages.ResultOk(requestId, new
                    {
                        stagedComplete = true,
                        workshopId = publishedFileId.ToString(),
                        manifestId = detail.hcontent_file.ToString(),
                        stagingPath = staging,
                        verifiedBytes = verifiedBytes,
                        totalBytes = manifestTotalBytes,
                        projectJsonPresent,
                    }, ProcessEpoch));
                }
            }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
            {
                if (terminals.TryBegin(requestId))
                {
                    writer.Send(ProtocolMessages.ResultError(requestId, "cancelled", "download cancelled", ProcessEpoch));
                }
            }
            catch (Exception error)
            {
                if (terminals.TryBegin(requestId))
                {
                    writer.Send(ProtocolMessages.ResultError(
                        requestId, ClassifyDownloadError(error), ProtocolRedactor.Redact(error.Message), ProcessEpoch));
                }
            }
            finally
            {
                lock (downloadGate)
                {
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
            if (!activeDownloads.TryGetValue(jobId, out var context)) return false;
            context.Cancellation.Cancel();
            return true;
        }
    }

    private void EmitDownloadProgress(
        ActiveDownload context, string stage,
        long? totalBytes = null, long? verifiedBytes = null, int? totalChunks = null, int? verifiedChunks = null)
    {
        context.Sequence += 1;
        writer.Send(new
        {
            v = ProtocolLimits.Version,
            type = "event",
            @event = "downloadProgress",
            requestId = context.RequestId,
            sequence = context.Sequence,
            processEpoch = ProcessEpoch,
            jobId = context.JobId,
            stage,
            totalBytes,
            verifiedBytes,
            totalChunks,
            verifiedChunks,
        });
    }

    /// ≤4Hz 合并的 chunk 进度；分母为未压缩总量（压缩字节不混入分母）。
    private void EmitDownloadChunkProgress(
        ActiveDownload context, long verifiedBytes, int verifiedChunks, int totalChunks)
    {
        var tick = Environment.TickCount64;
        if (context.LastProgressTick != 0
            && tick - context.LastProgressTick < ProgressCoalesceInterval.TotalMilliseconds)
        {
            return;
        }
        context.LastProgressTick = tick;
        EmitDownloadProgress(context, "chunks",
            verifiedBytes: verifiedBytes, totalChunks: totalChunks, verifiedChunks: verifiedChunks);
    }

    private static string ClassifyDownloadError(Exception error)
    {
        var message = error.Message;
        if (message.Contains("RateLimited", StringComparison.OrdinalIgnoreCase)) return "rateLimited";
        if (message.Contains("AccessDenied", StringComparison.OrdinalIgnoreCase)
            || message.Contains("decryption key denied", StringComparison.OrdinalIgnoreCase)) return "accessDenied";
        // GetDetails 层级的失败（项目不存在/私有）属内容不可用，而非网络。
        if (message.Contains("GetDetails failed", StringComparison.OrdinalIgnoreCase)) return "unsupportedContent";
        if (error is IOException) return "network";
        return "unsupportedContent";
    }
}

// ---- 会话原语与 chunk 下载/校验（partial 续） ----
internal sealed partial class SteamSession
{
    /// 跨 worker 的共享计数（字段可 Interlocked；异步方法不能带 ref）。
    private sealed class DownloadCounters
    {
        public long VerifiedBytes;
        public int DoneChunks;
    }

    private async Task<PublishedFileDetails> GetDetailsInternalAsync(ulong publishedFileId, CancellationToken ct)
    {
        var request = new CPublishedFile_GetDetails_Request { appid = ProtocolLimits.AppId };
        request.publishedfileids.Add(publishedFileId);
        var response = await publishedFiles.GetDetails(request)
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        return response.Body.publishedfiledetails.FirstOrDefault(item => item.publishedfileid == publishedFileId)
            ?? throw new IOException("GetDetails returned no entry.");
    }

    private async Task<uint> GetWorkshopDepotIdInternalAsync(CancellationToken ct)
    {
        var tokens = await apps.PICSGetAccessTokens([ProtocolLimits.AppId], [])
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        var request = new SteamApps.PICSRequest(ProtocolLimits.AppId);
        if (tokens.AppTokens.TryGetValue(ProtocolLimits.AppId, out var token)) request.AccessToken = token;
        var response = await apps.PICSGetProductInfo([request], [])
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        var info = response.Results?.Select(r => r.Apps)
            .FirstOrDefault(a => a.ContainsKey(ProtocolLimits.AppId))
            ?? throw new IOException("PICS product info unavailable.");
        var depot = info[ProtocolLimits.AppId].KeyValues["depots"]["workshopdepot"].AsUnsignedInteger();
        return depot != 0 ? depot : throw new IOException("workshopdepot missing.");
    }

    private async Task<byte[]> GetDepotDecryptionKeyInternalAsync(uint depotId, CancellationToken ct)
    {
        var result = await apps.GetDepotDecryptionKey(depotId, ProtocolLimits.AppId)
            .ToTask()
            .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        if (result.Result != EResult.OK)
        {
            throw new IOException($"depot decryption key denied: {result.Result}");
        }
        return result.DepotKey;
    }

    private async Task<ulong> GetManifestRequestCodeInternalAsync(uint depotId, ulong manifestId, CancellationToken ct)
    {
        var code = await content.GetManifestRequestCode(depotId, ProtocolLimits.AppId, manifestId, "public")
            .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.DetailsTimeoutSeconds), ct)
            .ConfigureAwait(false);
        return code != 0 ? code : throw new IOException("manifest request code unavailable.");
    }

    private async Task<Server> GetContentServerInternalAsync(CancellationToken ct)
    {
        var servers = await content.GetServersForSteamPipe()
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
        uint depotId,
        byte[] depotKey,
        ConcurrentQueue<(DepotManifest.FileData File, DepotManifest.ChunkData Chunk, string Target)> work,
        int totalChunks,
        CancellationToken ct)
    {
        var counters = new DownloadCounters();
        var workers = Enumerable.Range(0, Math.Min(DownloadWorkersPerJob, Math.Max(1, totalChunks)))
            .Select(_ => Task.Run(() => ChunkWorkerAsync(
                context, depotId, depotKey, work, totalChunks, counters, ct)))
            .ToArray();
        await Task.WhenAll(workers).ConfigureAwait(false);
        return Interlocked.Read(ref counters.VerifiedBytes);
    }

    private async Task ChunkWorkerAsync(
        ActiveDownload context,
        uint depotId,
        byte[] depotKey,
        ConcurrentQueue<(DepotManifest.FileData File, DepotManifest.ChunkData Chunk, string Target)> work,
        int totalChunks,
        DownloadCounters counters,
        CancellationToken ct)
    {
        using var workerClient = new SteamKit2.CDN.Client(client);
        while (work.TryDequeue(out var item))
        {
            ct.ThrowIfCancellationRequested();
            var buffer = new byte[item.Chunk.UncompressedLength];
            var server = await GetContentServerInternalAsync(ct).ConfigureAwait(false);
            var written = await workerClient
                .DownloadDepotChunkAsync(depotId, item.Chunk, server, buffer, depotKey)
                .WaitAsync(TimeSpan.FromSeconds(ProtocolLimits.ChunkTimeoutSeconds), ct)
                .ConfigureAwait(false);
            if (written != (int)item.Chunk.UncompressedLength)
            {
                throw new IOException($"short chunk read: {written}/{item.Chunk.UncompressedLength}");
            }
            using (var handle = File.OpenHandle(item.Target, FileMode.Open, FileAccess.Write,
                FileShare.ReadWrite, FileOptions.Asynchronous | FileOptions.RandomAccess))
            {
                await RandomAccess.WriteAsync(handle, buffer.AsMemory(0, written), (long)item.Chunk.Offset, ct)
                    .ConfigureAwait(false);
            }
            var verifiedNow = Interlocked.Add(ref counters.VerifiedBytes, written);
            var doneNow = Interlocked.Increment(ref counters.DoneChunks);
            EmitDownloadChunkProgress(context, verifiedNow, doneNow, totalChunks);
        }
    }

    private static void ValidateStagedFiles(
        IReadOnlyList<DepotManifest.FileData> files, string staging)
    {
        foreach (var file in files.Where(f => !f.Flags.HasFlag(EDepotFileFlag.Directory)))
        {
            var target = ResolveContainedPath(staging, file.FileName);
            using var stream = new FileStream(target, FileMode.Open, FileAccess.Read, FileShare.Read);
            foreach (var chunk in file.Chunks)
            {
                if (!IsChunkValid(stream, chunk))
                {
                    throw new IOException($"chunk validation failed: {file.FileName} @ {chunk.Offset}");
                }
            }
        }
    }

    private static bool IsChunkValid(FileStream stream, DepotManifest.ChunkData chunk)
    {
        if (chunk.UncompressedLength == 0) return true;
        if ((ulong)stream.Length < chunk.Offset + chunk.UncompressedLength) return false;
        var buffer = new byte[chunk.UncompressedLength];
        stream.Position = (long)chunk.Offset;
        var read = 0;
        while (read < buffer.Length)
        {
            var count = stream.Read(buffer, read, buffer.Length - read);
            if (count == 0) return false;
            read += count;
        }
        return DepotChunk.AdlerHash(buffer) == chunk.Checksum;
    }

    /// 路径围栏：manifest 内相对路径必须解析到 stagingRoot 之内。
    internal static string ResolveContainedPath(string root, string relative)
    {
        var normalized = relative.Replace('\\', Path.DirectorySeparatorChar)
            .Replace('/', Path.DirectorySeparatorChar);
        if (Path.IsPathRooted(normalized))
        {
            throw new IOException($"manifest contains absolute path: {relative}");
        }
        var fullRoot = Path.GetFullPath(root);
        var full = Path.GetFullPath(Path.Combine(fullRoot, normalized));
        var prefix = fullRoot.EndsWith(Path.DirectorySeparatorChar)
            ? fullRoot
            : fullRoot + Path.DirectorySeparatorChar;
        if (!full.StartsWith(prefix, StringComparison.Ordinal))
        {
            throw new IOException($"manifest path escapes staging root: {relative}");
        }
        return full;
    }
}
