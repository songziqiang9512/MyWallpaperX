using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using SteamKit2;
using SteamKit2.Authentication;

namespace SteamService.Probe;

// 认证探针：密码/QR/令牌恢复三条路都必须落到同一 SteamID 才算通过（SK0.1 验收）。
// 刷新令牌只写入隔离 state 目录（0600），stdout 一律脱敏。
internal static class ProbeAuth
{
    public sealed record SavedSession(string AccountName, string SteamId, string RefreshToken, string? GuardData);

    public static string StateDir { get; set; } =
        Path.Combine(Path.GetTempPath(), "mwx-sk01-probe");

    public static string SessionPath => Path.Combine(StateDir, "session.json");

    public static SavedSession? LoadSavedSession()
    {
        if (!File.Exists(SessionPath)) return null;
        var json = File.ReadAllText(SessionPath);
        return JsonSerializer.Deserialize<SavedSession>(json);
    }

    private static void SaveSession(SavedSession session)
    {
        Directory.CreateDirectory(StateDir);
        var json = JsonSerializer.Serialize(session, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(SessionPath, json);
        if (OperatingSystem.IsMacOS())
        {
            File.SetUnixFileMode(SessionPath, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        }
    }

    public static async Task RunPasswordAsync(string username, CancellationToken ct)
    {
        Console.Error.Write($"Steam 密码（{username}）: ");
        var password = ReadLineMasked();
        if (string.IsNullOrEmpty(password)) throw new IOException("empty password");

        await using var session = new ProbeSession();
        await session.ConnectAsync(ct).ConfigureAwait(false);
        ProbeReport.Emit(new { probe = "auth-password", stage = "connected" });

        var authenticator = new ProbeConsoleAuthenticator();
        var authSession = await session.Client.Authentication.BeginAuthSessionViaCredentialsAsync(
            new AuthSessionDetails
            {
                Username = username,
                Password = password,
                IsPersistentSession = true,
                Authenticator = authenticator,
                DeviceFriendlyName = "MyWallpaperX-SK01-Probe",
            })
            .WaitAsync(TimeSpan.FromMinutes(5), ct)
            .ConfigureAwait(false);
        var pollResult = await authSession.PollingWaitForResultAsync(ct).ConfigureAwait(false);

        await session.LogOnWithTokenAsync(pollResult.AccountName, pollResult.RefreshToken, ct).ConfigureAwait(false);
        SaveSession(new SavedSession(pollResult.AccountName, session.SteamId, pollResult.RefreshToken, pollResult.NewGuardData));
        ProbeReport.Emit(new
        {
            probe = "auth-password",
            stage = "logged-on",
            accountName = SanitizeAccount(pollResult.AccountName),
            steamId = session.SteamId,
            refreshTokenSavedTo = "state/session.json (0600)",
            hasNewGuardData = pollResult.NewGuardData != null,
        });
    }

    public static async Task RunQrAsync(CancellationToken ct)
    {
        await using var session = new ProbeSession();
        await session.ConnectAsync(ct).ConfigureAwait(false);
        ProbeReport.Emit(new { probe = "auth-qr", stage = "connected" });

        var authSession = await session.Client.Authentication.BeginAuthSessionViaQRAsync(
            new AuthSessionDetails
            {
                IsPersistentSession = true,
                DeviceFriendlyName = "MyWallpaperX-SK01-Probe",
            })
            .WaitAsync(TimeSpan.FromMinutes(1), ct)
            .ConfigureAwait(false);
        authSession.ChallengeURLChanged = () =>
            Console.Error.WriteLine($"二维码已刷新，请重新扫码: {authSession.ChallengeURL}");
        Console.Error.WriteLine($"请用 Steam 手机应用扫码确认: {authSession.ChallengeURL}");

        var pollResult = await authSession.PollingWaitForResultAsync(ct).ConfigureAwait(false);
        await session.LogOnWithTokenAsync(pollResult.AccountName, pollResult.RefreshToken, ct).ConfigureAwait(false);
        SaveSession(new SavedSession(pollResult.AccountName, session.SteamId, pollResult.RefreshToken, pollResult.NewGuardData));
        ProbeReport.Emit(new
        {
            probe = "auth-qr",
            stage = "logged-on",
            accountName = SanitizeAccount(pollResult.AccountName),
            steamId = session.SteamId,
            refreshTokenSavedTo = "state/session.json (0600)",
        });
    }

    public static async Task RunRestoreAsync(CancellationToken ct)
    {
        var saved = LoadSavedSession()
            ?? throw new IOException($"no saved session at {SessionPath}; run auth-password or auth-qr first.");
        await using var session = new ProbeSession();
        await session.ConnectAsync(ct).ConfigureAwait(false);
        await session.LogOnWithTokenAsync(saved.AccountName, saved.RefreshToken, ct).ConfigureAwait(false);
        var sameAccount = session.SteamId == saved.SteamId;
        ProbeReport.Emit(new
        {
            probe = "auth-restore",
            stage = "logged-on",
            accountName = SanitizeAccount(saved.AccountName),
            savedSteamId = saved.SteamId,
            liveSteamId = session.SteamId,
            sameSteamId = sameAccount,
        });
        if (!sameAccount)
        {
            throw new IOException("restored session resolved to a different SteamID.");
        }
    }

    public static string SanitizeAccount(string? accountName) =>
        string.IsNullOrEmpty(accountName) ? "" : accountName.Length <= 2 ? "**" : accountName[..2] + "***";

    private static string ReadLineMasked()
    {
        var buffer = new StringBuilder();
        while (true)
        {
            var key = Console.ReadKey(intercept: true);
            if (key.Key == ConsoleKey.Enter) break;
            if (key.Key == ConsoleKey.Backspace)
            {
                if (buffer.Length > 0) buffer.Length -= 1;
                continue;
            }
            if (!char.IsControl(key.KeyChar)) buffer.Append(key.KeyChar);
        }
        Console.Error.WriteLine();
        return buffer.ToString();
    }
}
