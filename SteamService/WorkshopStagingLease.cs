using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace SteamService;

// macOS descriptor-relative staging. The base must already exist. A new job gets
// an exclusive root; resume may adopt only one exact direct managed lease and
// then only manifest-declared nodes. Dispose releases handles only.
internal sealed class WorkshopStagingLease : IDisposable
{
    private const int DirectoryFlags = 0x00100000 | 0x01000000 | 0x00000100;
    private const int FileFlags = 0x01000000 | 0x00000100 | 0x00000004;
    private readonly SafeFileHandle root;
    private readonly Identity rootIdentity;
    private readonly string basePath;
    private readonly string name;
    private readonly Dictionary<string, Identity> directories = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Identity> files = new(StringComparer.Ordinal);
    internal string Path { get; }
    internal int Device => rootIdentity.Device;
    internal ulong Inode => rootIdentity.Inode;

    internal class Failure(string code, string message) : IOException(message)
    {
        internal string Code { get; } = code;
    }
    internal sealed class Rejected(string message) : Failure("integrity", message);
    private readonly record struct Identity(int Device, ulong Inode, long BirthSeconds, long BirthNanoseconds);

    // Darwin arm64 struct stat, verified against the SDK's sys/stat.h.
    [StructLayout(LayoutKind.Explicit, Size = 144)]
    private struct Stat
    {
        [FieldOffset(0)] public int Device;
        [FieldOffset(4)] public ushort Mode;
        [FieldOffset(6)] public ushort Links;
        [FieldOffset(8)] public ulong Inode;
        [FieldOffset(80)] public long BirthSeconds;
        [FieldOffset(88)] public long BirthNanoseconds;
    }
    [DllImport("libSystem.B.dylib", SetLastError = true)] private static extern int open(string path, int flags);
    [DllImport("libSystem.B.dylib", SetLastError = true)] private static extern int openat(SafeFileHandle dir, string path, int flags);
    // Darwin arm64 passes variadic arguments on the stack, unlike fixed arguments.
    // Fill x3...x7 so mode is the first stack argument. This ABI is arm64-only;
    // the runtime platform guard above is mandatory and filesystem tests assert 0600.
    [DllImport("libSystem.B.dylib", EntryPoint = "openat", SetLastError = true)]
    private static extern int openat_create(SafeFileHandle dir, string path, int flags,
        nint x3, nint x4, nint x5, nint x6, nint x7, uint mode);
    [DllImport("libSystem.B.dylib", SetLastError = true)] private static extern int mkdirat(SafeFileHandle dir, string path, uint mode);
    [DllImport("libSystem.B.dylib", SetLastError = true)] private static extern int fstat(SafeFileHandle fd, out Stat value);
    [DllImport("libSystem.B.dylib", SetLastError = true)] private static extern int unlinkat(
        SafeFileHandle dir, string path, int flags);

    private static SafeFileHandle Handle(int fd)
    {
        if (fd >= 0) return new SafeFileHandle((IntPtr)fd, ownsHandle: true);
        throw NativeFailure();
    }
    private static Failure NativeFailure()
    {
        int error = Marshal.GetLastPInvokeError();
        string code = error switch { 28 => "diskFull", 1 or 13 => "accessDenied", _ => "integrity" };
        return new Failure(code, $"staging operation failed (errno {error})");
    }
    // Only call at a local filesystem boundary, never for CDN/network IOException.
    internal static Failure ClassifyIO(IOException error) => error as Failure ?? new Failure(
        (error.HResult & 0xffff) switch { 28 or 112 => "diskFull", 1 or 13 => "accessDenied", _ => "integrity" },
        "staging I/O failed");

    private static Identity Inspect(SafeFileHandle fd, bool directory)
    {
        if (fstat(fd, out var value) != 0) throw new Rejected("staging identity unavailable");
        if ((value.Mode & 0xf000) != (directory ? 0x4000 : 0x8000) || (!directory && value.Links != 1))
            throw new Rejected("staging node is not an exclusive regular file/directory");
        return new(value.Device, value.Inode, value.BirthSeconds, value.BirthNanoseconds);
    }
    internal WorkshopStagingLease(string basePath) : this(basePath, existingPath: null) { }
    internal static WorkshopStagingLease Resume(
        string basePath,
        string existingPath,
        int expectedDevice,
        ulong expectedInode) => new(basePath, existingPath, expectedDevice, expectedInode);

    private WorkshopStagingLease(
        string basePath,
        string? existingPath,
        int? expectedDevice = null,
        ulong? expectedInode = null)
    {
        if (!OperatingSystem.IsMacOS() || RuntimeInformation.ProcessArchitecture != Architecture.Arm64)
            throw new PlatformNotSupportedException("staging requires macOS arm64");
        if (!System.IO.Path.IsPathFullyQualified(basePath)) throw new Rejected("staging base must be absolute");
        this.basePath = basePath;
        using var parent = OpenAbsoluteDirectory(basePath);
        string selectedName;
        if (existingPath == null)
        {
            selectedName = "job-" + Guid.NewGuid().ToString("N");
            if (mkdirat(parent, selectedName, 0x1c0) != 0) throw NativeFailure();
        }
        else
        {
            string basePrefix = basePath.TrimEnd('/');
            if (basePrefix.Length == 0 || !existingPath.StartsWith(basePrefix + '/', StringComparison.Ordinal))
                throw new Rejected("resume staging path escapes configured base");
            selectedName = existingPath[(basePrefix.Length + 1)..];
            if (!ValidLeaseName(selectedName) || selectedName.Contains('/'))
                throw new Rejected("resume staging path is not a direct managed lease");
        }
        name = selectedName;
        root = Handle(openat(parent, name, DirectoryFlags));
        try
        {
            rootIdentity = Inspect(root, true);
            if (existingPath != null
                && (expectedDevice == null || expectedInode == null
                    || rootIdentity.Device != expectedDevice
                    || rootIdentity.Inode != expectedInode))
            {
                throw new Rejected("resume staging identity changed");
            }
            Path = System.IO.Path.Combine(basePath, name);
            VerifyPublicationPath();
        }
        catch { root.Dispose(); throw; }
    }
    private static bool ValidLeaseName(string name) =>
        name.Length == 36 && name.StartsWith("job-", StringComparison.Ordinal)
            && name.AsSpan(4).ToString().All(character => character is >= '0' and <= '9' or >= 'a' and <= 'f');
    private static SafeFileHandle OpenAbsoluteDirectory(string path)
    {
        if (!System.IO.Path.IsPathFullyQualified(path)) throw new Rejected("absolute directory required");
        var current = Handle(open("/", DirectoryFlags));
        try
        {
            foreach (var part in path.TrimEnd('/').Split('/').Skip(1))
            {
                if (part is "" or "." or ".." || part.Contains('\0')) throw new Rejected("invalid base path component");
                var next = Handle(openat(current, part, DirectoryFlags));
                current.Dispose();
                current = next;
            }
            return current;
        }
        catch { current.Dispose(); throw; }
    }

    private static string[] Parts(string relative)
    {
        var parts = relative.Replace('\\', '/').TrimEnd('/').Split('/');
        if (parts.Length > 64 || parts.Any(p => p is "" or "." or ".." || p.Contains('\0') || p.Contains(':')))
            throw new Rejected("invalid staging relative path");
        return parts;
    }
    private SafeFileHandle Directory(string[] parts, int count, bool create, bool adoptExisting = false)
    {
        var current = Handle(openat(root, ".", DirectoryFlags));
        try
        {
            for (int i = 0; i < count; i++)
            {
                string key = string.Join('/', parts.Take(i + 1));
                if (!directories.TryGetValue(key, out var expected))
                {
                    if (create)
                    {
                        if (mkdirat(current, parts[i], 0x1c0) != 0
                            && !(adoptExisting && Marshal.GetLastPInvokeError() == 17)) throw NativeFailure();
                    }
                    else if (!adoptExisting)
                    {
                        throw new Rejected("unprepared staging directory");
                    }
                    using var created = Handle(openat(current, parts[i], DirectoryFlags));
                    expected = Inspect(created, true);
                    directories.Add(key, expected);
                }
                var next = Handle(openat(current, parts[i], DirectoryFlags));
                try
                {
                    if (Inspect(next, true) != expected) throw new Rejected("staging directory identity changed");
                }
                catch { next.Dispose(); throw; }
                current.Dispose();
                current = next;
            }
            return current;
        }
        catch { current.Dispose(); throw; }
    }
    internal void CreateDirectory(string relative)
    {
        var parts = Parts(relative);
        using var directory = Directory(parts, parts.Length, true);
    }
    internal void ResumeDirectory(string relative)
    {
        var parts = Parts(relative);
        using var directory = Directory(parts, parts.Length, create: true, adoptExisting: true);
    }
    internal void CreateFile(string relative, long length)
    {
        var parts = Parts(relative);
        using var parent = Directory(parts, parts.Length - 1, true);
        using var file = Handle(openat_create(parent, parts[^1], FileFlags | 2 | 0x200 | 0x800, 0, 0, 0, 0, 0, 0x180));
        var identity = Inspect(file, false);
        files.Add(string.Join('/', parts), identity);
        try { RandomAccess.SetLength(file, length); }
        catch (IOException error) { throw ClassifyIO(error); }
    }
    internal bool ResumeFile(string relative, long length)
    {
        if (TryResumeFile(relative, length)) return true;
        CreateFile(relative, length);
        return false;
    }
    internal bool TryResumeFile(string relative, long length)
    {
        var parts = Parts(relative);
        using var parent = Directory(parts, parts.Length - 1, create: true, adoptExisting: true);
        int descriptor = openat(parent, parts[^1], FileFlags);
        if (descriptor < 0)
        {
            if (Marshal.GetLastPInvokeError() == 2) return false;
            throw NativeFailure();
        }
        using var file = Handle(descriptor);
        var identity = Inspect(file, false);
        if (RandomAccess.GetLength(file) != length)
            throw new Rejected("resume staging file length changed");
        files.Add(string.Join('/', parts), identity);
        return true;
    }
    internal SafeFileHandle OpenFile(string relative, bool write)
    {
        var parts = Parts(relative);
        if (!files.TryGetValue(string.Join('/', parts), out var expected)) throw new Rejected("unprepared staging file");
        using var parent = Directory(parts, parts.Length - 1, false);
        var file = Handle(openat(parent, parts[^1], FileFlags | (write ? 2 : 0)));
        try
        {
            if (Inspect(file, false) != expected) throw new Rejected("staging file identity changed");
            return file;
        }
        catch { file.Dispose(); throw; }
    }
    internal void VerifyPublicationPath()
    {
        using var namedRoot = OpenAbsoluteDirectory(Path);
        if (Inspect(namedRoot, true) != rootIdentity) throw new Rejected("staging publication path changed");
    }
    /// A newly allocated lease has no children before the App acknowledges its
    /// durable identity. Reopen and compare immediately before pathname removal;
    /// a replacement observed at either check fails closed.
    internal void RemoveUnacknowledgedIfEmpty(Action? beforeFinalIdentityCheck = null)
    {
        using var parent = OpenAbsoluteDirectory(basePath);
        using var namedRoot = Handle(openat(parent, name, DirectoryFlags));
        if (Inspect(namedRoot, true) != rootIdentity)
            throw new Rejected("unacknowledged staging root identity changed");
        beforeFinalIdentityCheck?.Invoke();
        using var finalNamedRoot = Handle(openat(parent, name, DirectoryFlags));
        if (Inspect(finalNamedRoot, true) != rootIdentity)
            throw new Rejected("unacknowledged staging root identity changed before removal");
        const int AtRemoveDir = 0x80;
        if (unlinkat(parent, name, AtRemoveDir) != 0) throw NativeFailure();
    }
    public void Dispose() => root.Dispose();
}
