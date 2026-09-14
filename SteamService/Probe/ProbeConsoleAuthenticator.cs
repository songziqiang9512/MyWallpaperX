using SteamKit2.Authentication;

namespace SteamService.Probe;

// 控制台交互认证器：Guard 提示走 stderr，验证码从 stdin 读取；仅探针使用。
internal sealed class ProbeConsoleAuthenticator : IAuthenticator
{
    public Task<string> GetDeviceCodeAsync(bool previousCodeWasIncorrect)
    {
        if (previousCodeWasIncorrect)
        {
            Console.Error.WriteLine("上一枚验证码被拒绝，请重新输入。");
        }
        else
        {
            Console.Error.WriteLine("需要 Steam 令牌验证码（手机或邮箱）。");
        }
        Console.Error.Write("验证码: ");
        return Task.FromResult((Console.ReadLine() ?? "").Trim());
    }

    public Task<string> GetEmailCodeAsync(string email, bool previousCodeWasIncorrect)
    {
        if (previousCodeWasIncorrect)
        {
            Console.Error.WriteLine("上一枚邮箱验证码被拒绝，请重新输入。");
        }
        else
        {
            Console.Error.WriteLine($"验证码已发送到邮箱 {email}。");
        }
        Console.Error.Write("验证码: ");
        return Task.FromResult((Console.ReadLine() ?? "").Trim());
    }

    public Task<bool> AcceptDeviceConfirmationAsync()
    {
        Console.Error.WriteLine("请在 Steam 手机应用上确认本次登录……");
        return Task.FromResult(true);
    }
}
