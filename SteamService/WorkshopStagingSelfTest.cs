using System.Runtime.InteropServices;

namespace SteamService;

internal static class WorkshopStagingSelfTest
{
    [DllImport("libSystem.B.dylib", SetLastError = true)] private static extern int link(string source, string target);
    [DllImport("libSystem.B.dylib", SetLastError = true)] private static extern int mkfifo(string path, uint mode);
    internal static int Run()
    {
        if (!OperatingSystem.IsMacOS()) throw new PlatformNotSupportedException("macOS filesystem tests");
        string fixture = Path.Combine("/private/tmp", "mwx-staging-test-" + Guid.NewGuid());
        Directory.CreateDirectory(fixture);
        int count = 0;
        void Check(string name, bool passed)
        {
            if (!passed) throw new Exception("staging test failed: " + name);
            count++;
        }
        void Reject(string name, Action action)
        {
            try { action(); }
            catch (IOException) { count++; return; }
            throw new Exception("unsafe staging operation accepted: " + name);
        }
        try
        {
            string outside = Path.Combine(fixture, "outside");
            Directory.CreateDirectory(outside);
            string sentinel = Path.Combine(outside, "sentinel");
            File.WriteAllText(sentinel, "unchanged");
            string alias = Path.Combine(fixture, "alias");
            Directory.CreateSymbolicLink(alias, outside);
            Reject("base symlink", () => { using var denied = new WorkshopStagingLease(alias); });
            Directory.CreateDirectory(Path.Combine(outside, "child"));
            Reject("ancestor symlink", () => { using var denied = new WorkshopStagingLease(Path.Combine(alias, "child")); });
            using var first = new WorkshopStagingLease(fixture);
            using var second = new WorkshopStagingLease(fixture);
            Check("separate exclusive roots", first.Path != second.Path);
            Task.WaitAll(Task.Run(() =>
            {
                first.CreateFile("parallel", 1);
                using var handle = first.OpenFile("parallel", true);
                RandomAccess.Write(handle, new byte[] { 1 }, 0);
            }), Task.Run(() =>
            {
                second.CreateFile("parallel", 1);
                using var handle = second.OpenFile("parallel", true);
                RandomAccess.Write(handle, new byte[] { 2 }, 0);
            }));
            Check("first job isolated", File.ReadAllBytes(Path.Combine(first.Path, "parallel"))[0] == 1);
            Check("second job isolated", File.ReadAllBytes(Path.Combine(second.Path, "parallel"))[0] == 2);
            Check("root mode 0700", File.GetUnixFileMode(first.Path) == (UnixFileMode)0x1c0);
            first.CreateFile("dir/data", 4);
            string directory = Path.Combine(first.Path, "dir");
            string data = Path.Combine(directory, "data");
            Check("directory mode 0700", File.GetUnixFileMode(directory) == (UnixFileMode)0x1c0);
            Check("file mode 0600", File.GetUnixFileMode(data) == (UnixFileMode)0x180);
            using (var handle = first.OpenFile("dir/data", true))
                RandomAccess.WriteAsync(handle, new byte[] { 1, 2, 3, 4 }, 0).AsTask().GetAwaiter().GetResult();
            Check("descriptor write", File.ReadAllBytes(data).SequenceEqual(new byte[] { 1, 2, 3, 4 }));
            Reject("existing file is not truncated", () => first.CreateFile("dir/data", 0));
            Check("original bytes retained", File.ReadAllBytes(data).SequenceEqual(new byte[] { 1, 2, 3, 4 }));
            Reject("traversal", () => first.CreateFile("../escape", 0));
            Reject("unprepared file", () => { using var handle = first.OpenFile("unknown", true); });

            File.Move(data, data + ".original");
            File.CreateSymbolicLink(data, sentinel);
            Reject("file symlink", () => { using var handle = first.OpenFile("dir/data", true); });
            File.Delete(data);
            Check("create hardlink fixture", link(sentinel, data) == 0);
            Reject("hardlink", () => { using var handle = first.OpenFile("dir/data", true); });
            File.Delete(data);
            Check("create fifo fixture", mkfifo(data, 0x180) == 0);
            Reject("FIFO cannot block or act as file", () => { using var handle = first.OpenFile("dir/data", true); });
            File.Delete(data);
            File.WriteAllText(data, "replacement");
            Reject("replacement inode", () => { using var handle = first.OpenFile("dir/data", true); });
            File.Delete(data);
            File.Move(data + ".original", data);

            // Replacing a pathname after open never redirects the already-held descriptor.
            using (var pinned = first.OpenFile("dir/data", true))
            {
                File.Move(data, data + ".original");
                File.WriteAllText(data, "replacement");
                RandomAccess.Write(pinned, new byte[] { 9 }, 0);
                Check("replacement unchanged after pinned write", File.ReadAllText(data) == "replacement");
                Check("pinned inode receives write", File.ReadAllBytes(data + ".original")[0] == 9);
            }
            File.Delete(data);
            File.Move(data + ".original", data);
            Directory.Move(directory, directory + ".original");
            Directory.CreateSymbolicLink(directory, outside);
            Reject("child directory symlink", () => { using var handle = first.OpenFile("dir/data", true); });
            File.Delete(directory);
            Directory.CreateDirectory(directory);
            File.WriteAllText(Path.Combine(directory, "data"), "replacement");
            Reject("child directory replacement", () => { using var handle = first.OpenFile("dir/data", true); });
            File.Delete(Path.Combine(directory, "data"));
            Directory.Delete(directory);
            Directory.Move(directory + ".original", directory);

            first.VerifyPublicationPath();
            count++;
            Directory.Move(first.Path, first.Path + ".original");
            Directory.CreateDirectory(first.Path);
            Reject("root replacement prevents receipt", first.VerifyPublicationPath);
            Directory.Delete(first.Path);
            Directory.Move(first.Path + ".original", first.Path);
            Check("outside sentinel unchanged", File.ReadAllText(sentinel) == "unchanged");
        }
        finally { Directory.Delete(fixture, recursive: true); } // exact fresh fixture, never a user staging tree
        Console.WriteLine($"staging filesystem: {count}/{count} PASS (isolated macOS arm64 fixture)");
        return 0;
    }
}
