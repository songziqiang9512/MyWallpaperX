using System.Net.Sockets;
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
        Check(TestPhysicalDrain().GetAwaiter().GetResult());
        long gib = 1024L * 1024 * 1024;
        Check(SteamSession.CanReserveDiskBytes(gib, 6 * gib,
            SteamSession.RemainingReservation(8 * gib, 7 * gib)));
        Check(SteamSession.ClassifyDownloadError(WorkshopStagingLease.ClassifyIO(new IOException("opaque", 28))) == "diskFull");
        Check(SteamSession.ClassifyDownloadError(WorkshopStagingLease.ClassifyIO(new IOException("opaque", 112))) == "diskFull");
        Check(SteamSession.ClassifyDownloadError(WorkshopStagingLease.ClassifyIO(new IOException("opaque", 13))) == "accessDenied");
        Check(SteamSession.ClassifyDownloadError(WorkshopStagingLease.ClassifyIO(new IOException("disk full", 5))) == "integrity");
        Check(SteamSession.MaxChunkDownloadAttempts == 3);
        Check(SteamSession.TestStagingAcknowledgementBarrier().GetAwaiter().GetResult());
        Check(SteamSession.ChunkRetryBackoffDelay(1) == TimeSpan.FromMilliseconds(500)
            && SteamSession.ChunkRetryBackoffDelay(2) == TimeSpan.FromMilliseconds(2000)
            && SteamSession.ChunkRetryBackoffDelay(9) == TimeSpan.FromMilliseconds(2000));
        Check(SteamSession.IsRetryableChunkFetch(new TimeoutException(), CancellationToken.None));
        Check(SteamSession.IsRetryableChunkFetch(new HttpRequestException("cdn"), CancellationToken.None));
        Check(SteamSession.IsRetryableChunkFetch(new SocketException(), CancellationToken.None));
        // A transport-level timeout surfaces as TaskCanceledException without the job token.
        Check(SteamSession.IsRetryableChunkFetch(new OperationCanceledException(), CancellationToken.None));
        Check(SteamSession.IsRetryableChunkFetch(SteamRequestFailure.FromResult(EResult.Busy), CancellationToken.None));
        Check(SteamSession.IsRetryableChunkFetch(SteamRequestFailure.FromResult(EResult.RateLimitExceeded), CancellationToken.None));
        Check(!SteamSession.IsRetryableChunkFetch(SteamRequestFailure.FromResult(EResult.AccessDenied), CancellationToken.None));
        Check(!SteamSession.IsRetryableChunkFetch(new InvalidDataException("short read"), CancellationToken.None));
        Check(!SteamSession.IsRetryableChunkFetch(WorkshopStagingLease.ClassifyIO(new IOException("disk full", 28)), CancellationToken.None));
        Check(!SteamSession.IsRetryableChunkFetch(new TimeoutException(), new CancellationToken(canceled: true)));
        Check(SteamSession.MaxActiveDownloadJobs == 2
            && SteamSession.MaxConcurrentDownloadChunks == 4
            && SteamSession.TestActiveDownloadCapacity()
            && TestSharedChunkBudget().GetAwaiter().GetResult()
            && SteamSession.CanReserveDiskBytes(
                8L * 1024 * 1024 * 1024,
                16L * 1024 * 1024 * 1024 + 256L * 1024 * 1024,
                8L * 1024 * 1024 * 1024)
            && !SteamSession.CanReserveDiskBytes(
                8L * 1024 * 1024 * 1024,
                16L * 1024 * 1024 * 1024 + 256L * 1024 * 1024 - 1,
                8L * 1024 * 1024 * 1024)
            && !SteamSession.CanReserveDiskBytes(-1, long.MaxValue, 0)
            && SteamSession.AvailableDiskBytesForTest(Path.GetTempPath()) > 256L * 1024 * 1024);
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

    private static async Task<bool> TestPhysicalDrain()
    {
        foreach (bool timeOut in new[] { false, true })
        {
            using var cancellation = new CancellationTokenSource();
            var physical = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
            var cancelled = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            var waiter = SteamSession.AwaitPhysicalOperation(physical.Task,
                () => cancelled.TrySetResult(true), timeOut ? TimeSpan.Zero : TimeSpan.FromSeconds(5), cancellation.Token);
            if (!timeOut) cancellation.Cancel();
            await cancelled.Task.WaitAsync(TimeSpan.FromSeconds(5));
            if (waiter.IsCompleted) return false;
            physical.SetResult(1); // simulate a non-cancellable decode finishing later
            try { await waiter; return false; }
            catch (TimeoutException) when (timeOut) {}
            catch (OperationCanceledException) when (!timeOut) {}
        }
        return true;
    }

    private static async Task<bool> TestSharedChunkBudget()
    {
        var session = new SteamSession(new ProtocolWriter(), new TerminalTracker());
        int active = 0, peak = 0;
        var tasks = Enumerable.Range(0, 12).Select(_ => session.WithDownloadChunkSlotForTest(async () =>
        {
            int current = Interlocked.Increment(ref active);
            int observed;
            do
            {
                observed = peak;
                if (observed >= current) break;
            } while (Interlocked.CompareExchange(ref peak, current, observed) != observed);
            await Task.Delay(20).ConfigureAwait(false);
            Interlocked.Decrement(ref active);
            return true;
        }, CancellationToken.None));
        if (!(await Task.WhenAll(tasks).ConfigureAwait(false)).All(value => value)
            || peak != SteamSession.MaxConcurrentDownloadChunks) return false;

        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        try
        {
            await session.WithDownloadChunkSlotForTest(() => Task.FromResult(true), cancelled.Token);
            return false;
        }
        catch (OperationCanceledException) { }
        return await session.WithDownloadChunkSlotForTest(() => Task.FromResult(true), CancellationToken.None);
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
    internal static async Task<bool> TestStagingAcknowledgementBarrier()
    {
        var session = new SteamSession(new ProtocolWriter(), new TerminalTracker());
        var source = session.PublishAccountForTest(1, "76561198000000000");
        var cancellation = new CancellationTokenSource();
        var context = new ActiveDownload
        {
            JobId = "job-ack", RequestId = "request-ack", StagingRoot = "/unused",
            PublishedFileId = 1,
            Cancellation = cancellation, Account = session.CaptureAccountForTest(1), Source = source,
        };
        session.activeDownloads.Add(context.JobId, context);
        try
        {
            var waiting = AwaitStagingAcknowledgementAsync(context, cancellation.Token);
            await Task.Yield();
            if (waiting.IsCompleted
                || session.AcknowledgeDownloadStaging(
                    context.JobId, "/private/tmp/job-ack", "123", "1", "2", 1))
            {
                return false;
            }
            await Task.Run(() => session.PublishStagingIdentity(
                context, "/private/tmp/job-ack", "123", "1", "2")).ConfigureAwait(false);
            if (session.AcknowledgeDownloadStaging(
                    context.JobId, context.StagingPath!, context.StagingManifestId!,
                    context.StagingDevice!, "wrong", 1)
                || session.AcknowledgeDownloadStaging(
                    context.JobId, context.StagingPath!, context.StagingManifestId!,
                    context.StagingDevice!, context.StagingInode!, 2)
                || waiting.IsCompleted)
            {
                return false;
            }
            if (!session.AcknowledgeDownloadStaging(
                    context.JobId, context.StagingPath!, context.StagingManifestId!,
                    context.StagingDevice!, context.StagingInode!, 1)) return false;
            await waiting.ConfigureAwait(false);
            if (session.AcknowledgeDownloadStaging(
                    context.JobId, context.StagingPath!, context.StagingManifestId!,
                    context.StagingDevice!, context.StagingInode!, 1)) return false;

            var cancelled = new ActiveDownload
            {
                JobId = "job-cancel", RequestId = "request-cancel", StagingRoot = "/unused",
                StagingPath = "/private/tmp/job-cancel", StagingManifestId = "456",
                StagingDevice = "3", StagingInode = "4", PublishedFileId = 1,
                Cancellation = new CancellationTokenSource(),
                Account = session.CaptureAccountForTest(1), Source = source,
            };
            session.activeDownloads.Add(cancelled.JobId, cancelled);
            var cancelledWait = AwaitStagingAcknowledgementAsync(cancelled, cancelled.Cancellation.Token);
            cancelled.Cancellation.Cancel();
            try { await cancelledWait.ConfigureAwait(false); return false; }
            catch (OperationCanceledException) { }
            finally
            {
                session.activeDownloads.Remove(cancelled.JobId);
                cancelled.Cancellation.Dispose();
            }
            var timedOut = new ActiveDownload
            {
                JobId = "job-timeout", RequestId = "request-timeout", StagingRoot = "/unused",
                PublishedFileId = 1, Cancellation = new CancellationTokenSource(),
                Account = session.CaptureAccountForTest(1), Source = source,
            };
            try
            {
                await AwaitStagingAcknowledgementAsync(
                    timedOut, CancellationToken.None, TimeSpan.Zero).ConfigureAwait(false);
                return false;
            }
            catch (SteamRequestFailure failure) when (failure.Code == "integrity") { }
            finally { timedOut.Cancellation.Dispose(); }
            return true;
        }
        finally
        {
            session.activeDownloads.Remove(context.JobId);
            cancellation.Dispose();
            source.Disconnect();
        }
    }

    internal static bool TestActiveDownloadCapacity()
    {
        var session = new SteamSession(new ProtocolWriter(), new TerminalTracker());
        var source = session.PublishAccountForTest(1, "76561198000000000");
        try
        {
            for (int index = 0; index < MaxActiveDownloadJobs; index++)
            {
                var cancellation = new CancellationTokenSource();
                session.activeDownloads.Add($"job-{index}", new ActiveDownload
                {
                    JobId = $"job-{index}", RequestId = $"request-{index}", StagingRoot = "/unused",
                    PublishedFileId = 1, Cancellation = cancellation,
                    Account = session.CaptureAccountForTest(1), Source = source,
                });
            }
            if (session.DownloadJobCapacityAvailableLocked()) return false;
            var removed = session.activeDownloads["job-0"];
            session.activeDownloads.Remove("job-0");
            removed.Cancellation.Dispose();
            return session.DownloadJobCapacityAvailableLocked();
        }
        finally
        {
            foreach (var context in session.activeDownloads.Values) context.Cancellation.Dispose();
            source.Disconnect();
        }
    }

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
