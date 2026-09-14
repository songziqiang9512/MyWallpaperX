namespace SteamService.Probe;

// SK0.1 冻结的初始预算；后续卡不得在无证据时放宽。
internal static class Budgets
{
    public const uint AppId = 431960;
    public const string PublicBranch = "public";

    public const int QueryPageSize = 30;
    public const int DetailBatchSize = 20;
    public const int MaxConcurrentHttpRequests = 2;

    public const int QueryTimeoutSeconds = 15;
    public const int DetailsTimeoutSeconds = 20;
    public const int ManifestTimeoutSeconds = 30;
    public const int ChunkTimeoutSeconds = 60;
    public const int ConnectTimeoutSeconds = 12;
    public const int LogOnTimeoutSeconds = 30;

    public const int ChunkWorkersPerJob = 4;

    public const long OutputBytesCap = 2L * 1024 * 1024 * 1024;
    public const int OutputFileCountCap = 100_000;
}
