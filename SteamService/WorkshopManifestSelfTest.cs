using SteamKit2;

namespace SteamService;

internal static class WorkshopManifestSelfTest
{
    internal static int Run()
    {
        int count = 0;
        static DepotManifest.ChunkData Chunk(ulong offset, uint size) => new(new byte[20], 0, offset, size, size);
        static DepotManifest.FileData File(string name, ulong size, params DepotManifest.ChunkData[] chunks)
        {
            var file = new DepotManifest.FileData(name, new byte[20], 0, size, new byte[20], "", false, chunks.Length);
            file.Chunks.AddRange(chunks);
            return file;
        }
        static DepotManifest.FileData Project() => File("project.json", 2, Chunk(0, 2));
        void Check(string name, bool reject, params DepotManifest.FileData[] files)
        {
            bool rejected = false;
            try { WorkshopManifestValidation.Validate(files, 1024, 100, 64, CancellationToken.None); }
            catch (WorkshopManifestValidation.Rejected) { rejected = true; }
            if (reject != rejected) throw new Exception($"manifest check failed: {name}");
            count++;
        }
        Check("valid", false, Project(), File("dir/file", 4, Chunk(2, 2), Chunk(0, 2)));
        Check("empty file", false, Project(), File("empty", 0));
        Check("missing project", true, File("file", 2, Chunk(0, 2)));
        Check("empty project", true, File("project.json", 0));
        Check("unsigned overflow", true, Project(), File("huge", ulong.MaxValue));
        Check("aggregate budget", true, Project(), File("huge", 1024));
        Check("missing chunks", true, Project(), File("file", 4));
        Check("gap", true, Project(), File("file", 4, Chunk(1, 3)));
        Check("overlap", true, Project(), File("file", 4, Chunk(0, 3), Chunk(2, 2)));
        Check("extent overflow", true, Project(), File("file", 4, Chunk(ulong.MaxValue, 2)));
        Check("past eof", true, Project(), File("file", 4, Chunk(0, 5)));
        Check("zero chunk", true, Project(), File("file", 0, Chunk(0, 0)));
        Check("chunk budget", true, Project(), File("file", 65, Chunk(0, 65)));
        Check("duplicate", true, Project(), Project());
        Check("case collision", true, Project(), File("FILE", 0), File("file", 0));
        Check("unicode collision", true, Project(), File("é", 0), File("e\u0301", 0));
        Check("parent casing", true, Project(), File("Dir/a", 0), File("dir/b", 0));
        Check("file then directory", true, Project(), File("dir", 0), File("dir/a", 0));
        Check("directory then file", true, Project(), File("dir/a", 0), File("dir", 0));
        Check("traversal", true, Project(), File("../escape", 0));
        Check("absolute", true, Project(), File("/escape", 0));
        Check("windows absolute", true, Project(), File("C:\\escape", 0));
        Check("empty component", true, Project(), File("dir//a", 0));
        Check("chunk count budget", true, Project(), File("many", 1,
            Enumerable.Repeat(Chunk(0, 1), WorkshopManifestValidation.MaxChunks + 1).ToArray()));
        Check("symlink", true, Project(), new DepotManifest.FileData("link", new byte[20],
            EDepotFileFlag.Symlink, 0, new byte[20], "target", false, 0));
        Check("explicit parent", false, Project(), File("dir/a", 0), new DepotManifest.FileData("dir",
            new byte[20], EDepotFileFlag.Directory, 0, new byte[20], "", false, 0));
        Check("path depth", true, Project(), File(string.Join('/', Enumerable.Repeat("a", 65)), 0));
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        try
        {
            WorkshopManifestValidation.Validate([Project()], 1024, 100, 64, cancelled.Token);
            throw new Exception("cancellation ignored");
        }
        catch (OperationCanceledException) { count++; }
        // Run the actual final validation against only our own isolated two-byte fixture.
        var folder = Directory.CreateDirectory(Path.Combine("/private/tmp", "mwx-manifest-test-" + Guid.NewGuid()));
        var lease = new WorkshopStagingLease(folder.FullName);
        lease.CreateFile("project.json", 2);
        var target = Path.Combine(lease.Path, "project.json");
        try
        {
            byte[] bytes = [(byte)'{', (byte)'}'];
            var valid = File("project.json", 2, new DepotManifest.ChunkData(new byte[20],
                SteamKit2.CDN.DepotChunk.AdlerHash(bytes), 0, 2, 2));
            System.IO.File.WriteAllBytes(target, bytes);
            var digest = SteamSession.ValidateStagedFiles([valid], lease, CancellationToken.None);
            if (digest != "e84ca141a76fc927400b3428d5d509be7a7b5319f6d160aa30eb549a73d71832") throw new Exception("cross-language receipt digest mismatch");
            count++;
            try
            {
                SteamSession.ValidateStagedFiles([valid], lease, cancelled.Token);
                throw new Exception("final validation ignored cancellation");
            }
            catch (OperationCanceledException) { count++; }
            System.IO.File.WriteAllBytes(target, [0, 0]);
            try
            {
                SteamSession.ValidateStagedFiles([valid], lease, CancellationToken.None);
                throw new Exception("checksum corruption accepted");
            }
            catch (InvalidDataException) { count++; }
            System.IO.File.WriteAllBytes(target, [0]);
            try
            {
                SteamSession.ValidateStagedFiles([valid], lease, CancellationToken.None);
                throw new Exception("wrong length accepted");
            }
            catch (InvalidDataException) { count++; }
        }
        finally { lease.Dispose(); System.IO.File.Delete(target); Directory.Delete(lease.Path); folder.Delete(); }
        Console.WriteLine($"manifest and staged validation: {count}/{count} PASS (offline, isolated fixture)");
        return 0;
    }
}
