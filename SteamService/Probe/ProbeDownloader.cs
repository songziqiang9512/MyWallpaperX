using System.Collections.Concurrent;
using System.Security.Cryptography;
using SteamKit2;
using SteamKit2.CDN;

namespace SteamService.Probe;

// SK0.1 下载探针：匿名或登录会话下走 授权→manifest→有界 chunk→校验 的最小闭环。
// 只产出 staged 内容与完整性报告；不做入库、不做恢复语义（SK4.x 范围）。
internal static class ProbeDownloader
{
    public sealed record DownloadReport(
        ulong PublishedFileId,
        string Mode,
        ulong ManifestId,
        uint DepotId,
        int FileCount,
        long ManifestTotalBytes,
        long VerifiedUncompressedBytes,
        string StagingDir,
        string Sha256ProjectJson,
        bool ProjectJsonPresent,
        long ElapsedMs);

    private sealed class ChunkProgress
    {
        public long Done;
        public long UncompressedBytes;

        public void Record(uint uncompressedLength)
        {
            Interlocked.Increment(ref Done);
            Interlocked.Add(ref UncompressedBytes, uncompressedLength);
        }
    }

    public static async Task<DownloadReport> DownloadAsync(
        ProbeSession session, ulong publishedFileId, string outputRoot, CancellationToken ct)
    {
        var started = System.Diagnostics.Stopwatch.StartNew();
        var detail = await session.GetDetailsAsync(publishedFileId, ct).ConfigureAwait(false)
            ?? throw new IOException("unified GetDetails returned no entry.");
        if (detail.result != (uint)EResult.OK)
        {
            throw new IOException($"GetDetails failed: {(EResult)detail.result} (anonymous={session.IsAnonymous})");
        }
        if (detail.consumer_appid != Budgets.AppId)
        {
            throw new IOException($"item belongs to app {detail.consumer_appid}, not Wallpaper Engine.");
        }
        if (detail.hcontent_file == 0)
        {
            throw new IOException("item has no content manifest (hcontent_file=0).");
        }

        var depotId = await session.GetWorkshopDepotIdAsync(ct).ConfigureAwait(false);
        var depotKey = await session.GetDepotDecryptionKeyAsync(depotId, ct).ConfigureAwait(false);
        var requestCode = await session.GetManifestRequestCodeAsync(depotId, detail.hcontent_file, ct).ConfigureAwait(false);
        var server = await session.GetContentServerAsync(ct).ConfigureAwait(false);

        DepotManifest manifest;
        using (var cdnClient = new Client(session.Client))
        {
            manifest = await cdnClient
                .DownloadManifestAsync(depotId, detail.hcontent_file, requestCode, server, depotKey)
                .WaitAsync(TimeSpan.FromSeconds(Budgets.ManifestTimeoutSeconds), ct)
                .ConfigureAwait(false);
        }
        var files = manifest.Files
            ?? throw new IOException("manifest has no file list.");
        if (files.Count == 0) throw new IOException("manifest is empty.");
        if (files.Count > Budgets.OutputFileCountCap)
        {
            throw new IOException($"manifest file count {files.Count} exceeds probe cap {Budgets.OutputFileCountCap}.");
        }

        var root = Path.GetFullPath(outputRoot);
        var staging = Path.Combine(root, ".staging", publishedFileId.ToString());
        Directory.CreateDirectory(staging);

        long manifestTotal = 0;
        long manifestUncompressedTotal = 0;
        var work = new ConcurrentQueue<(DepotManifest.FileData File, DepotManifest.ChunkData Chunk, string Path)>();
        foreach (var file in files)
        {
            if (file.Flags.HasFlag(EDepotFileFlag.Symlink))
            {
                throw new IOException("manifest contains symlink; refusing per SK0 path contract.");
            }
            var target = ResolveContainedPath(staging, file.FileName);
            if (file.Flags.HasFlag(EDepotFileFlag.Directory))
            {
                Directory.CreateDirectory(target);
                continue;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            using (var resize = new FileStream(target, FileMode.OpenOrCreate, FileAccess.Write, FileShare.ReadWrite))
            {
                resize.SetLength((long)file.TotalSize);
            }
            manifestTotal += (long)file.TotalSize;
            foreach (var chunk in file.Chunks)
            {
                manifestUncompressedTotal += chunk.UncompressedLength;
                work.Enqueue((file, chunk, target));
            }
        }
        if (manifestTotal > Budgets.OutputBytesCap)
        {
            throw new IOException($"manifest total {manifestTotal} bytes exceeds probe cap {Budgets.OutputBytesCap}.");
        }

        var progress = new ChunkProgress();
        var totalChunks = work.Count;
        var workers = Enumerable.Range(0, Math.Min(Budgets.ChunkWorkersPerJob, Math.Max(1, totalChunks)))
            .Select(_ => Task.Run(() => WorkerLoopAsync(session, depotId, depotKey, work, progress, ct), ct))
            .ToArray();

        using var progressStop = new CancellationTokenSource();
        var progressTask = Task.Run(async () =>
        {
            while (!progressStop.IsCancellationRequested)
            {
                try
                {
                    await Task.Delay(250, progressStop.Token).ConfigureAwait(false);
                }
                catch (OperationCanceledException) { return; }
                ProbeReport.Emit(new
                {
                    probe = "download",
                    stage = "chunks",
                    publishedFileId = publishedFileId.ToString(),
                    doneChunks = Interlocked.Read(ref progress.Done),
                    totalChunks,
                });
            }
        }, CancellationToken.None);

        try
        {
            await Task.WhenAll(workers).ConfigureAwait(false);
        }
        finally
        {
            progressStop.Cancel();
            try { await progressTask.ConfigureAwait(false); } catch { }
        }

        // 最终校验：逐 chunk adler。
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

        var projectJsonPath = Path.Combine(staging, "project.json");
        var projectJsonPresent = File.Exists(projectJsonPath);
        var sha = projectJsonPresent
            ? Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(projectJsonPath)))
            : "";

        return new DownloadReport(
            publishedFileId,
            session.IsAnonymous ? "anonymous" : $"user:{ProbeAuth.SanitizeAccount(session.AccountName)}",
            detail.hcontent_file,
            depotId,
            files.Count,
            manifestTotal,
            Interlocked.Read(ref progress.UncompressedBytes),
            staging,
            sha,
            projectJsonPresent,
            started.ElapsedMilliseconds);
    }

    private static async Task WorkerLoopAsync(
        ProbeSession session, uint depotId, byte[] depotKey,
        ConcurrentQueue<(DepotManifest.FileData File, DepotManifest.ChunkData Chunk, string Path)> work,
        ChunkProgress progress, CancellationToken ct)
    {
        using var cdnClient = new Client(session.Client);
        while (work.TryDequeue(out var item))
        {
            ct.ThrowIfCancellationRequested();
            var buffer = new byte[item.Chunk.UncompressedLength];
            var server = await session.GetContentServerAsync(ct).ConfigureAwait(false);
            var written = await cdnClient
                .DownloadDepotChunkAsync(depotId, item.Chunk, server, buffer, depotKey)
                .WaitAsync(TimeSpan.FromSeconds(Budgets.ChunkTimeoutSeconds), ct)
                .ConfigureAwait(false);
            if (written != (int)item.Chunk.UncompressedLength)
            {
                throw new IOException($"short chunk read: {written}/{item.Chunk.UncompressedLength}");
            }
            using var handle = File.OpenHandle(item.Path, FileMode.Open, FileAccess.Write, FileShare.ReadWrite,
                FileOptions.Asynchronous | FileOptions.RandomAccess);
            await RandomAccess.WriteAsync(handle, buffer.AsMemory(0, written), (long)item.Chunk.Offset, ct)
                .ConfigureAwait(false);
            progress.Record(item.Chunk.UncompressedLength);
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

    public static string ResolveContainedPath(string root, string relative)
    {
        var normalized = relative.Replace('\\', Path.DirectorySeparatorChar)
            .Replace('/', Path.DirectorySeparatorChar);
        if (Path.IsPathRooted(normalized))
        {
            throw new IOException($"manifest contains absolute path: {relative}");
        }
        var full = Path.GetFullPath(Path.Combine(root, normalized));
        var prefix = Path.GetFullPath(root) + Path.DirectorySeparatorChar;
        if (!full.StartsWith(prefix, StringComparison.Ordinal))
        {
            throw new IOException($"manifest path escapes staging: {relative}");
        }
        return full;
    }
}
