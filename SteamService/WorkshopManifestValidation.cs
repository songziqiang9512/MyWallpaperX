using System.Text;
using SteamKit2;

namespace SteamService;

// Pure admission: reject the whole manifest before creating directories or allocating files.
internal static class WorkshopManifestValidation
{
    internal sealed class Rejected(string message) : IOException(message);
    internal sealed record Summary(long Bytes, int Chunks);
    private sealed record Entry(string Spelling, bool Directory, bool Explicit);
    internal const int MaxChunks = 262_144;

    internal static Summary Validate(IReadOnlyList<DepotManifest.FileData> files,
        long byteBudget, int fileBudget, long chunkBudget, CancellationToken ct)
    {
        if (files.Count == 0 || files.Count > fileBudget) throw new Rejected("manifest file count exceeds budget");
        var paths = new Dictionary<string, Entry>(StringComparer.OrdinalIgnoreCase);
        int pathCharacters = 0;
        const int pathCharacterBudget = 8 * 1024 * 1024;
        long bytes = 0;
        int chunks = 0;
        bool project = false;
        foreach (var file in files)
        {
            ct.ThrowIfCancellationRequested();
            if (file.Flags.HasFlag(EDepotFileFlag.Symlink)) throw new Rejected("manifest symlink is unsupported");
            bool directory = file.Flags.HasFlag(EDepotFileFlag.Directory);
            if (string.IsNullOrEmpty(file.FileName) || file.FileName.Length > 4096)
                throw new Rejected("manifest path length exceeds budget");
            string path = file.FileName.Replace('\\', '/');
            if (directory) path = path.TrimEnd('/');
            if (string.IsNullOrEmpty(path) || path.Contains('\0') || path.Contains(':'))
                throw new Rejected("invalid manifest path");
            var parts = path.Split('/');
            if (parts.Length > 64 || parts.Any(p => p is "" or "." or "..")) throw new Rejected("invalid manifest path component");
            for (int i = 0; i < parts.Length; i++)
            {
                ct.ThrowIfCancellationRequested();
                string prefix = string.Join('/', parts.Take(i + 1));
                string key = prefix.Normalize(NormalizationForm.FormC);
                bool explicitEntry = i == parts.Length - 1;
                bool isDirectory = !explicitEntry || directory;
                if (paths.TryGetValue(key, out var previous))
                {
                    if (!previous.Directory || !isDirectory || previous.Spelling != prefix ||
                        (previous.Explicit && explicitEntry)) throw new Rejected("manifest path collision");
                    if (explicitEntry) paths[key] = previous with { Explicit = true };
                }
                else
                {
                    if (key.Length > pathCharacterBudget - pathCharacters)
                        throw new Rejected("manifest path index exceeds budget");
                    pathCharacters += key.Length;
                    paths.Add(key, new(prefix, isDirectory, explicitEntry));
                }
            }
            if (directory)
            {
                if (file.TotalSize != 0 || file.Chunks.Count != 0) throw new Rejected("directory contains data");
                continue;
            }
            if (file.TotalSize > (ulong)(byteBudget - bytes)) throw new Rejected("manifest byte budget exceeded");
            bytes += checked((long)file.TotalSize);
            if (file.Chunks.Count > MaxChunks - chunks) throw new Rejected("manifest chunk count exceeds budget");
            chunks += file.Chunks.Count;
            ulong end = 0;
            foreach (var chunk in file.Chunks.OrderBy(c => c.Offset))
            {
                ct.ThrowIfCancellationRequested();
                if (chunk.UncompressedLength == 0 || chunk.UncompressedLength > chunkBudget ||
                    chunk.CompressedLength == 0 || chunk.CompressedLength > chunkBudget ||
                    chunk.ChunkID is not { Length: 20 }) throw new Rejected("invalid chunk shape or budget");
                if (chunk.Offset != end || chunk.Offset > file.TotalSize ||
                    chunk.UncompressedLength > file.TotalSize - chunk.Offset)
                    throw new Rejected("chunk overlap, gap or out-of-range extent");
                end += chunk.UncompressedLength; // bounded by file.TotalSize above; cannot overflow
            }
            if (end != file.TotalSize) throw new Rejected("chunks do not cover file");
            if (path == "project.json" && file.TotalSize > 0) project = true;
        }
        if (!project) throw new Rejected("manifest requires a nonempty root project.json");
        return new(bytes, chunks);
    }
}
