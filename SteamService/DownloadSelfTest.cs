using System.Security.Cryptography;
using System.Text.Json;
using SteamKit2;

namespace SteamService;

internal static class DownloadSelfTest
{
    internal static int Run()
    {
        int count = 0;
        void Check(bool value) { if (!value) throw new Exception($"download check {count + 1} failed"); count++; }
        var state = new DownloadProgressState();
        var frames = new List<DownloadProgressState.Snapshot>();
        state.Publish("preparing", 10000, 10000, frames.Add);
        Parallel.For(0, 10000, _ => state.CompleteChunk(1, frames.Add));
        state.Publish("validating", null, null, frames.Add);
        Check(frames.Select(f => f.Sequence).SequenceEqual(Enumerable.Range(1, frames.Count)));
        Check(frames.All(f => f.TotalBytes == 10000 && f.TotalChunks == 10000));
        Check(frames.Zip(frames.Skip(1)).All(pair => pair.First.VerifiedBytes <= pair.Second.VerifiedBytes
            && pair.First.VerifiedChunks <= pair.Second.VerifiedChunks));
        Check(frames[^1].VerifiedBytes == 10000 && frames[^1].VerifiedChunks == 10000);
        try { state.CompleteChunk(1, frames.Add); Check(false); } catch (InvalidDataException) { Check(true); }
        Check(SteamSession.ClassifyDownloadError(new IOException("AccessDenied budget chunk validation failed")) == "network");
        Check(SteamSession.ClassifyDownloadError(SteamRequestFailure.FromResult(EResult.AccessDenied)) == "accessDenied");
        Check(SteamSession.ClassifyDownloadError(SteamRequestFailure.FromResult(EResult.RateLimitExceeded)) == "rateLimited");
        Check(SteamSession.ClassifyDownloadError(new InvalidDataException("anything")) == "integrity");
        Check(SteamSession.ClassifyDownloadError(WorkshopStagingLease.ClassifyIO(new IOException("opaque", 28))) == "diskFull");
        Check(SteamSession.ClassifyDownloadError(WorkshopStagingLease.ClassifyIO(new IOException("opaque", 112))) == "diskFull");
        Check(SteamSession.ClassifyDownloadError(WorkshopStagingLease.ClassifyIO(new IOException("opaque", 13))) == "accessDenied");
        Check(SteamSession.ClassifyDownloadError(WorkshopStagingLease.ClassifyIO(new IOException("disk full", 5))) == "integrity");
        using var cts = new CancellationTokenSource();
        using var stream = new CancelAfterRead(cts);
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        try
        {
            SteamSession.IsChunkValid(stream, new DepotManifest.ChunkData(new byte[20], 0, 0, 131072, 131072), cts.Token, hash);
            Check(false);
        }
        catch (OperationCanceledException) { Check(stream.ReadCalls == 1); }
        for (int i = 0; i < 100; i++) Check(SteamSession.TestDownloadTerminalRace());
        Console.WriteLine($"download progress/errors/cancellation: {count}/{count} PASS (offline)");
        return 0;
    }

    private sealed class CancelAfterRead(CancellationTokenSource source) : MemoryStream(new byte[131072])
    {
        internal int ReadCalls;
        public override int Read(byte[] buffer, int offset, int count)
        {
            int read = base.Read(buffer, offset, count);
            ReadCalls++;
            source.Cancel();
            return read;
        }
    }
}

internal sealed partial class SteamSession
{
    // Exercise the actual success/targeted-cancel decision without connecting to Steam.
    internal static bool TestDownloadTerminalRace()
    {
        var session = new SteamSession(new ProtocolWriter(), new TerminalTracker());
        var source = session.PublishAccountForTest(1, "76561198000000000");
        using var cancellation = new CancellationTokenSource();
        var context = new ActiveDownload { JobId = "job", RequestId = "request", StagingRoot = "/unused",
            PublishedFileId = 1, Cancellation = cancellation, Account = session.CaptureAccountForTest(1), Source = source };
        session.activeDownloads.Add(context.JobId, context);
        var output = new StringWriter();
        var original = Console.Out;
        bool accepted = false;
        try
        {
            Console.SetOut(output);
            Parallel.Invoke(() => accepted = session.CancelDownload(context.JobId), () =>
            {
                try { session.FinishDownloadSuccess(context, new { stagedComplete = true }); }
                catch (OperationCanceledException) { session.FinishSteamRequestFailure(context, "cancelled", "cancelled"); }
            });
        }
        finally { Console.SetOut(original); source.Disconnect(); }
        var lines = output.ToString().Split('\n', StringSplitOptions.RemoveEmptyEntries);
        if (lines.Length != 1) return false;
        using var document = JsonDocument.Parse(lines[0]);
        return document.RootElement.GetProperty("ok").GetBoolean() == !accepted
            && !session.CancelDownload(context.JobId);
    }
}
