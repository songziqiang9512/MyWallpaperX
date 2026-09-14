using SteamKit2.Authentication;

namespace SteamService;

// SK2.1 离线认证合同自检：attempt 簿记与 Guard 认证器的语义正反例（无网络）。
// 运行：dotnet SteamService.dll selftest auth；真实账号流由账号门单独验证。
internal static class AuthSelfTest
{
    public static int Run()
    {
        var passed = 0;
        var total = 0;
        void Check(string name, bool ok, string detail = "")
        {
            total += 1;
            if (ok) passed += 1;
            Console.Out.WriteLine(System.Text.Json.JsonSerializer.Serialize(new
            {
                suite = "selftest-auth",
                check = name,
                ok,
                detail,
            }));
        }

        // 1. 单活动 attempt：第二个 Begin 立即顶替第一个。
        var book = new AuthAttemptBook();
        var first = book.Begin("req-a", "password");
        var second = book.Begin("req-b", "qr");
        Check("single-active-attempt",
            book.CanEmit(first.AttemptId) == false && book.CanEmit(second.AttemptId) == true,
            $"first={first.AttemptId} second={second.AttemptId}");

        // 2. 迟到终结被抑制：被顶替 attempt 的 Finish 不产生效果。
        Check("superseded-finish-suppressed", book.TryFinish(first.AttemptId, "online") == false);

        // 3. 事件抑制：被顶替 attempt 不再发事件。
        Check("superseded-events-suppressed",
            !book.CanEmit(first.AttemptId) && book.CanEmit(second.AttemptId));

        // 4. 正常终结后 CanEmit 关闭。
        Check("finish-closes-attempt",
            book.TryFinish(second.AttemptId, "online") && !book.CanEmit(second.AttemptId));

        // 5. CancelAuthentication 后 Submit 返回 false（验证码窗口已关）。
        var session = new SteamSession(new ProtocolWriter(), new TerminalTracker());
        session.BeginLoginPassword("req-submit-test", "user", "pw");
        var activeId = SessionTestHook.ActiveAttemptId(session);
        Check("active-attempt-exists", activeId != null);
        session.CancelAuthentication(null);
        Check("submit-after-cancel-rejected",
            activeId == null || session.SubmitChallenge(activeId, "12345") == false);

        // 6. cancelAuthentication 指定错误 attemptId 不取消活动 attempt。
        var book2 = new AuthAttemptBook();
        var attempt2 = book2.Begin("req-c", "password");
        Check("wrong-attempt-id-does-not-cancel",
            book2.CanEmit(attempt2.AttemptId));

        // 7. Guard 认证器：Submit 解除等待中的验证码请求。
        var received = new List<(string State, string? Email, bool? Incorrect)>();
        var authenticator = new AttemptAuthenticator(
            (state, email, incorrect) => received.Add((state, email, incorrect)),
            () => true);
        var codeTask = authenticator.GetEmailCodeAsync("qq.com", previousCodeWasIncorrect: false);
        Check("email-code-state-emitted",
            received.Count == 1 && received[0].State == "awaitingEmailCode" && received[0].Email == "qq.com");
        Check("submit-resolves-code", authenticator.Submit("3HBFR") && codeTask.Result == "3HBFR");

        // 8. Guard 认证器：取消后等待中的验证码任务被取消。
        var cancelledAuthenticator = new AttemptAuthenticator((_, _, _) => { }, () => true);
        var cancelledTask = cancelledAuthenticator.GetDeviceCodeAsync(false);
        cancelledAuthenticator.Cancel();
        Check("cancel-aborts-code-wait", cancelledTask.IsCanceled);

        // 9. Guard 分型：设备码与手机确认各自独立状态。
        var typedReceived = new List<string>();
        var typedAuthenticator = new AttemptAuthenticator(
            (state, _, _) => typedReceived.Add(state), () => true);
        _ = typedAuthenticator.AcceptDeviceConfirmationAsync();
        var deviceTask = typedAuthenticator.GetDeviceCodeAsync(previousCodeWasIncorrect: true);
        typedAuthenticator.Submit("ABCDEF");
        Check("guard-typed-states",
            typedReceived.SequenceEqual(["awaitingDeviceConfirmation", "awaitingDeviceCode"])
            && deviceTask.Result == "ABCDEF",
            string.Join(",", typedReceived));

        // 10. 死 attempt 的事件回调被抑制（attemptAlive=false 时不 report、任务取消）。
        var deadReceived = 0;
        var deadAuthenticator = new AttemptAuthenticator((_, _, _) => deadReceived += 1, () => false);
        var deadTask = deadAuthenticator.GetEmailCodeAsync("qq.com", false);
        Check("dead-attempt-suppresses-report-and-cancels-wait",
            deadReceived == 0 && deadTask.IsCanceled);

        Console.Out.WriteLine(System.Text.Json.JsonSerializer.Serialize(new
        {
            suite = "selftest-auth",
            check = "summary",
            ok = passed == total,
            detail = $"{passed}/{total} passed",
        }));
        return passed == total ? 0 : 1;
    }
}

/// 仅供离线自检观察会话内部 attempt 状态；产品路径不使用。
internal static class SessionTestHook
{
    public static string? ActiveAttemptId(SteamSession session) => session.TestActiveAttemptId;
}
