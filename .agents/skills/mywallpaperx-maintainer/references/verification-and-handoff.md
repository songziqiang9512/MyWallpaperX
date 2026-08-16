# 验证、macOS 调试与 Git 交接方法

本参考吸收通用 macOS Skill 对本项目有用的 shell-first build/debug、AppKit/window、测试分诊、日志、签名、打包和公证方法。只在任务实际涉及这些表面时加载；加载后仍不使用 `build-macos-apps`。

## 目录

1. [先定义证据问题](#先定义证据问题)
2. [发现当前工具入口](#发现当前工具入口)
3. [失败分诊](#失败分诊)
4. [AppKit 与窗口](#appkit-与窗口)
5. [日志与 typed diagnostics](#日志与-typed-diagnostics)
6. [签名、nested code 与发布](#签名nested-code-与发布)
7. [Runtime 隔离与声明等级](#runtime-隔离与声明等级)
8. [Tracked 与 untracked 交接](#tracked-与-untracked-交接)

## 先定义证据问题

每个命令只为回答一个可证伪问题：新代码是否被目标/harness 加载；target membership/链接是否成立；运行的是哪个 App/helper；request/session/surface 是否仍是当前意图；结果到了 accepted、prepared、published、composited 还是 visible；局部失败是否保留 previous current；签名/entitlement/Gatekeeper 是否是实际阻塞。

先跑能区分当前候选解释的最小门。只有风险或新结果要求时扩大到 build、runtime、matrix、签名或发布；无信息地重复 full suite 不增加证据。

## 发现当前工具入口

从当前仓库发现 Xcode project/workspace、scheme、`script/` 入口、测试和 machine manifest。优先使用 `AGENTS.md`、专题 current-state/README 和脚本 `--help` 指定的统一入口；不要把本参考中的命令示例当永久 interface，也不要创建第二 run script 或 ad hoc 环境配置。

典型选择方法：

- 纯结构/单元：运行直接命中的 Python/Swift harness，确认实际 selection。
- Swift 产品变更：在共享 build/runtime 空闲时串行执行当前 checkpoint build。
- build + run/debug/logs：先读当前 `script/build_and_run.sh` 行为，确认 kill 范围、scheme、DerivedData、App 路径和 mode；只读任务不能运行。
- Scene/Web runtime：使用各自 current gate/benchmark 和隔离 output，不能用普通 App 存活替代 host/GPU/visible evidence。
- release：读取 `docs/release/release-signing.md` 和当前 CI/export workflow。

任何工具会终止同名 App、重用共享 DerivedData、写真实目录或启动长期进程时，先核对授权和并行状态。

## 失败分诊

| 类别 | 先核对 | 不要误报为 |
|---|---|---|
| source/health/layout | 规则、路径、source set、file length、manifest | runtime regression |
| compiler | 第一个真实 syntax/type/Metal diagnostic | 后续 cascade |
| linker/target membership | symbol、duplicate、architecture、Xcode/standalone list | 功能逻辑失败 |
| toolchain/settings | SDK、deployment、module、dependency、Python/Xcode identity | 产品代码回归 |
| signing/entitlement | 实际 bundle、nested code、Team ID、runtime、sandbox | 普通 compile failure |
| launch/process | executable path/hash、bundle、helper、process tree | surface ready |
| environment/fixture | sample、permission、display、WebKit/GPU、runtime root | 产品 assertion |
| assertion/regression | 确认测试真实执行与 target contract | flake 或环境问题 |
| async/flake | request/generation/session 和 deterministic stale case | 可忽略偶发失败 |
| visual/fidelity | producer-to-compositor identity、ROI/事件 | route/build success |
| crash/GPU fault | symbolized stack、command buffer、现场 identity | 普通视觉差异 |

修复后先复现原失败，再跑相邻反例和相称 checkpoint。测试若锁定已知错误现状，应按目标合同修测试和实现；目标本身被证伪则先走合同/Skill 纠偏。

## AppKit 与窗口

项目 UI 是 AppKit-first。优先现有 `NSWindowController`、coordinator、responder chain、toolbar/sidebar/inspector、panel/menu、pasteboard 和 drag/drop owner；既有 SwiftUI 只是受控残留，不为新功能创建新 SwiftUI 产品面或扩大 `NSHostingView` bridge。

窗口变化检查 role、identity、display、restoration、teardown、accessibility、drag region、visible-frame placement、Spaces/collection behavior、focus/input 和 borderless wallpaper level。主窗口、panel、Video helper window、Web surface、Scene output 各由当前唯一 owner 管理；不要把通用 SwiftUI scene/window modifier 套进当前 AppKit 生命周期。

UI 只投影产品状态并发命令，不能成为第二 runtime 真值。多显示器行为使用目标 display 的当前 geometry，不假设固定分辨率或单屏。

## 日志与 typed diagnostics

优先模块已有 typed diagnostic/store；需要统一日志时使用真实 bundle subsystem 和稳定 owner category。事件包含 privacy-safe 的 request/display/session/surface/generation/route identity，区分 accepted/prepared/published/visible、stale rejection、fallback、crash/recovery 和 teardown。

不记录 token、bookmark data、用户文件内容、完整私人路径、原始 Workshop payload/shader；不以 `print` 或每 mutation 大 payload 代替产品 telemetry。运行一次目标路径并按 process/subsystem/category 过滤，确认事件数量有界且来自正确 build/identity。日志出现只证明事件代码执行，不证明画面。

## 签名、nested code 与发布

先区分 local debug 与 distribution。notarization 不是普通 Debug 前置，ad hoc 签名也不能证明 Developer ID 或发布身份。

对实际 artifact 检查主 app/executable、wallpaper helper/daemon、framework、compiler/VM worker 或其他 nested code，以及 entitlements、hardened runtime、Team ID、CDHash、architectures、DMG/export、notary result 和 Gatekeeper。使用当前系统工具读取 artifact，不从 Xcode settings 推断最终包已正确签名。

正式运行证据绑定 staged app 的绝对路径、bundle ID、Team ID、CDHash、executable hash 和 helper identity。没有 exported/notarized artifact 时明确结论只到 build/static/signed-staged 的实际等级。签名问题按 identity、entitlement、runtime、sandbox、nested-code、bundle structure 和 notarization phase 分类。

## Runtime 隔离与声明等级

真实 Scene/Workshop root 与用户视频只读。sample copy、runtime home、property injection、cache、manifest、screenshots、reports 和 evidence 使用每次全新隔离位置；记录 App/helper 的绝对路径、hash、PID 和 display/request/surface identity。检查旧 `/Applications` App 没有抢占 helper、URL handler 或 writer。

同一时刻只运行一个会竞争 App、helper、GPU、benchmark、matrix 或共享 DerivedData 的任务。结束后确认进程退出或明确保留。高体量输出另加载 artifact governance。

声明按实际最高阶段：static/recognized、compiled/linked、process alive、accepted/host ready、prepared、published/composited、visible bounded case、matrix profile、signed staged、official bounded comparison、release。较低阶段不能冒充较高阶段；所有 PASS 绑定 diff/commit、build identity、输入、环境和 gate version。

## Tracked 与 untracked 交接

先展开 owned manifest：

```bash
git status --short --branch --untracked-files=all -- <owned-paths>
git ls-files -- <owned-paths>
```

分开审查：

- tracked unstaged：`git diff --check -- <owned-paths>` 与 scoped `git diff`；
- staged：`git diff --cached --check -- <owned-paths>`、`git diff --cached --name-status` 和 scoped cached diff；
- untracked：逐文件完整读取并运行适用 validator/formatter。需要 patch/whitespace 视图时可用 `git diff --no-index --check /dev/null <file>`，但“文件有差异”本身会产生非零状态，必须与真实 whitespace diagnostic 区分。

空 `git diff` 不能证明 untracked 内容 clean。全工作区 status 用于发现并行 lane；全工作区 `diff --check` 的其他 owner 错误只能作警告，不能归责当前 owned batch。

提交前逐路径暂存，禁止 `git add -A`。核对 cached manifest 只含本批完整职责，提交后再检查 `git show --stat --oneline HEAD`、`git status` 和目标路径状态。除非用户要求，不推送。最终报告只列适用项：实际结果、验证、未运行门、runtime/signing/artifact identity、剩余边界和 Git 状态。
