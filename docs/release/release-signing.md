# Release signing and notarization

<!-- document-role: stable-contract -->

GitHub Actions builds are signed and notarized before being attached to GitHub Releases. Configure these repository secrets before relying on release downloads:

- `BUILD_CERTIFICATE_BASE64`: Base64-encoded `.p12` export of the Developer ID Application certificate.
- `P12_PASSWORD`: Password for the exported `.p12`.
- `KEYCHAIN_PASSWORD`: Temporary CI keychain password. Any strong generated value is fine.
- `DEVELOPER_ID_APPLICATION`: Full signing identity, for example `Developer ID Application: Your Name (TEAMID)`.
- `APPLE_ID`: Apple Developer account email.
- `APPLE_APP_SPECIFIC_PASSWORD`: App-specific password for notarization.
- `APPLE_TEAM_ID`: Apple Developer Team ID.
- `SPARKLE_PRIVATE_KEY`: Private EdDSA key exported by Sparkle's `generate_keys`
  tool. Keep this secret out of the repository.

Create `BUILD_CERTIFICATE_BASE64` locally after exporting the Developer ID Application certificate from Keychain Access:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

The workflow intentionally fails early when any signing secret is missing. Unsigned macOS downloads often show as damaged because Gatekeeper cannot verify the app.

## 正式发布流程

Pushing or merging to `main` does **not** publish a release. Publishing requires
an explicit `workflow_dispatch` of [Release MyWallpaperX](../../.github/workflows/build.yml)
against `main`.

从下一次发布起，产品版本创建为正式 **GitHub Release**，并标记为 **Latest**。
继续使用 `build-<version>` Tag 固定构建的完整提交 SHA，以兼容已有版本、下载链接和
版本比较；Tag 是 Release 的源码引用，不是独立的发布入口。历史预发布不自动改写。
`update-feed` 仍是承载 Sparkle XML 的机器预发布，不作为 Latest。

### Agent 一句话发布

用户明确说「发布」「发布新版本」或「帮我打包、上传、发布新版本，并更新日志」，即授权完成
准备、必要提交、主分支整合、推送、构建、签名公证、公开 Release 和更新源核验。
Agent 持续执行到交付或具体外部阻塞，不把模板填写、Git 操作或 Actions 按钮交给用户，
也不在已授权步骤重复索要确认。仅准备、审核材料或讨论发布方案时，不提交、推送或发布。

Agent 按以下顺序执行：

1. 核对工作树归属，fetch `origin/main` 与标签，读取最新正式 Release 和公开 appcast；区分已发布内容、
   当前候选与并行改动。只提交明确归属的待发布文件，先整合 main 的独有内容，再将候选合入 main。
   冲突按已确认的发布范围裁决，保留较新实现及正式发布历史，不用旧版整文件覆盖当前合同。
   共享工作区不适合切换时使用隔离检出；不强推、不混入未授权的其他分支工作。
2. 用户指定版本就使用该版本；未指定时，若项目已有高于已发布版本的版本号则使用它，
   否则在最新版本上递增补丁号。已经准备好的同一版本与构建号直接复用，仍须同时高于公开 appcast。
   对照**上一正式版本**至当前候选的代码、验证与产品行为提炼变化，提交主题只作线索。
3. 由 **Agent 编写** `docs/releases/<version>.md`，使用 [日志模板](../releases/TEMPLATE.md)。
   标题为 `# MyWallpaperX <version>`，一段面向用户的概述后分为
   **新增、修改、优化、修复、已知问题**；没有变化的类别写 `- 无。`，至少有一项实际变化。
   保留五类标题，在类别内用默认关闭的 `<details>` / `<summary>` 展开正文；不附历史版本回顾或提交清单。
   写清使用场景、行为变化、必要操作和已知限制，不把研究、失败实验或局部测试写成普遍兼容或性能收益。
   同步 README 发布入口、许可和版本相关过期描述；已有准确内容不重复重写。无需用户逐项填写或确认。
4. 在已经集成好的 `main` 检出中运行：

   ```bash
   python3.12 script/publish_release.py <version>
   ```

   集成后先跑最近发布回归、文档与工程门；签名、公证和包体核验由固定 SHA 的发布工作流完成。
   入口核对日志、工作树、远端标签与版本，仅在版本或日志变化时提交。推送 `main` 后等待同 SHA 的普通 CI 成功；
   CI 未成功不触发 Release。确认 main 未移动后触发构建，用 API run ID 追踪，
   完成后核对正式/Latest、源码提交、日志、附件及 Sparkle 更新源。
   `source_sha` 输入会阻止 main 在推送与触发间变化时误发布另一份源码。
5. 期间 Agent 持续跟进并处理可修复失败；断线后根据已经输出的 run URL 恢复跟踪，
   不盲目再次触发。成功后给出 Release 链接、版本和验证结果。
   凭据缺失、GitHub/Apple 权限不足等外部阻塞须报告具体阶段；不能把 Actions 已启动当成发布完成。
   收尾清理本轮隔离构建和临时检出，报告实际源码 SHA、版本/构建号、公开附件与更新源的核验结果。

`prepare_release_version.sh` 只是内部文件准备步骤，不自动提交或推送；完整发布入口是
`publish_release.py`。GitHub Release 和应用内 Sparkle 使用同一份日志。
日志缺失、空章节、模板占位或版本不一致直接失败，不存在提交记录回退路径；自动门检查
完整性，内容是否准确由 Agent 对照代码与证据复核。日常 push/PR 只运行
[CI](../../.github/workflows/ci.yml)，不会自动发布。`workflow_dispatch` 是 Agent 调用的技术入口，
不要求用户前往 GitHub 手工操作。

### 版本一致性

项目中的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION` 是版本号和构建号的唯一来源，
App/Daemon、Debug/Release 必须一致。准备版本时先读取公开的 `update-feed/appcast.xml`，
同版且构建号高于线上时沿用，重复准备不递增；新版本取 `max(项目构建号, 已发布构建号) + 1`。
已准备构建号不高于线上即停止。无变化时复用提交；CI 不另算构建号。

发布入口验证本地版本提交与远端 main SHA/项目版本一致；CI 在构建前要求版本号和构建号
都高于已发布版本，构建后核对 App 的 Info.plist，生成更新源后核对 appcast。
发布完成还会检查公开 appcast 的两个版本字段与本地一致、正式 Release 与 update-feed 的 XML 完全相同。
任一处不一致即停止，不能仅凭文件名或工作流成功认定发布完成。

正式包的内容边界、视频编码及资源裁剪规则见 [App 内容与体积](bundle-content.md)。

### 工作流顺序与产物

发布任务串行执行，不取消正在签名或上传的任务。一次运行只处理检出的固定提交：

1. 检查输入版本、正式日志、重复/倒退版本及已有 Release 草稿。
2. 准备锁定的 Python/NuGet 依赖，运行 `--scope release` 的安装包与核心链路检查；首次失败立即打印详情并取消未开始的模块。检查代码健康，再构建 arm64 Release。
3. 检查 bundle，逐层签署 SteamService、Scene 工具、WallpaperDaemon、Sparkle、主 App；
   校验全包同 Team 的 Developer ID、runtime、时间戳，App Apple Events、Steam JIT，以及 逐项匹配 Sparkle 2.9.2 原包权限；禁止注入 sandbox/JIT/调试权限（[上游合同](https://sparkle-project.org/documentation/sandboxing/)）。
4. 公证并 staple App，使用保留符号链接的 `ditto` 装入 DMG；签署、公证、staple 并校验 DMG。
5. 生成含 EdDSA 签名与日志的 appcast；合包 App/WallpaperDaemon dSYM，计算 DMG SHA-256。
6. 保存 Actions artifacts；将 DMG、SHA-256、dSYM 和 appcast 上传到 Release 草稿，上传完成后
   发布为正式 Latest。公开版本不使用 `--clobber` 覆盖安装包。
7. 正式 Release 可下载后，才替换 `update-feed/appcast.xml`。已安装版本每天检查一次，也可以手动
   选择 **检查更新…**。

测试和签名、公证失败都会阻止公开 Release。离线 Steam 测试只从已恢复的锁定包缓存构建，不在测试中联网补依赖。GitHub CI 没有私有 Workshop corpus，缺少本机 fixture 时逐用例明确报告跳过，同模块的合成用例照常运行；本机证据缓存不作为仓库文件存在性门，但源码、测试和文档引用仍须有效。

普通 CI push 从同分支最近成功且为祖先的 CI push SHA 累计验证，失败后不丢前次改动；无记录沿原回退。PR 用 PR base；手动 `base_ref` 默认前一提交。`test_scope` 默认为 `changed`，可选 `release` / `all`；显式范围替代定向测试，不重复运行。
CI 同样在首次失败后取消未开始的测试。删除测试触发全仓回归时，全量门替代已覆盖的定向测试，避免同一批模块重复运行。

工程配置变更把 `script/run_scene_tests.py` 的 `RELEASE_MODULES` 合并到定向测试并去重，覆盖版本、日志、脚本、包体、Steam、播放策略、Web 暂停及 Scene 生命周期。详细 Scene/corpus 按影响面验证。

需要完整回归时，为 Agent 发布命令追加 `--test-scope all`，或将发布工作流的 `test_scope` 显式设为 `all`；不发布时可单独执行 `python3.12 -B script/run_scene_tests.py --scope all --jobs 4 --fail-fast`。缩小默认测试范围不会跳过 Release 构建、包体检查、签名验证、公证或发布结果核验；核心检查通过不等于所有 Scene 能力或真实样本通过。

GitHub CI 的离线测试、构建和发布成功不等于所有真实壁纸、真实账号或最低系统版本的运行验收。

### 失败后的处理

- 构建、公证或 appcast 生成失败且未创建 Release 时，修复原因后重新运行。
- 上传或公开发布失败可能留下草稿。流程会停止而非覆盖它；核对草稿绑定的提交和附件，
  Agent 可在确认提交、日志及附件完整后完成该草稿；若需删除或重建，先核对其确属本次失败发布，
  仅处理本次草稿及其未发布标签。不得删除或覆盖已经公开的版本。
- 正式版本成功、更新源上传失败时，Release 和下载包仍有效，旧更新源保持可用（上传替换期间
  可能短暂不可用）。从该次 Actions artifact 或该版本 Release 取出已生成的 `appcast.xml`，
  核对它仍对应当前最新版本后，只重试上传到 `update-feed`；不要重建或覆盖正式安装包。
  不要把旧运行的 appcast 覆盖到更新版本之上。

## SteamService build and signing boundary

Xcode's App target publishes and embeds `Contents/Resources/SteamService/` in both
Debug and Release. Install SDK **8.0.401** (`SteamService/global.json`); CI selects
that version explicitly. The helper ships a pinned **.NET 8.0.31 osx-arm64** runtime,
so users do not need an SDK or runtime installation. NuGet restore is locked;
`SteamService/NOTICE.md` and `licenses/` accompany the generated directory.
Review runtime security updates independently of the fixed build SDK.

`script/publish-steam-helper.sh` publishes into a fresh temporary directory and
mirrors only a recognized generated helper output, removing stale dependencies.
Xcode's `TARGETNAME` must not change the managed entry assembly: the script fixes
`TargetName=SteamService` explicitly and rejects a missing `SteamService.dll`.
Per-build intermediates live in DerivedData, outside the source tree.

`script/sign-steam-helper.sh <helper-dir> <identity> [required|none]` signs native dependencies
before the apphost. Real signing identities use hardened runtime and apphost
`com.apple.security.cs.allow-jit`; native libraries must have the same Team ID.
The optional timestamp policy defaults to `required`; ad-hoc code always omits
timestamps. Xcode Debug embeds use `none`, avoiding an online timestamp service
for local builds. The opt-in Scene diagnostic xcconfig also explicitly selects
`MWX_STEAM_HELPER_TIMESTAMP_POLICY=none`; ordinary Release and direct signing
retain the required timestamp. Identity, runtime, JIT and strict verification
are unchanged; these local paths do not prove distribution readiness.
The outer App is signed after nested code, without `--deep --force` re-signing
that would overwrite helper entitlements. Ad-hoc `-` is a local, unhardened test
path because it has no Team ID for library validation. It does not prove the
Developer ID/notarization gate.

The arm64 bundle validator requires the helper, its runtime and license material.
A release still needs actual signed-bundle launch, full account/list/download
flow on the minimum supported Mac, notarization and Gatekeeper verification.
Build or offline self-tests do not close those gates.
