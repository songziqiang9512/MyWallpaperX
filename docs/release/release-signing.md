# Release signing and notarization

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

用户只需说「帮我打包、上传、发布新版本，并更新日志」。这条明确的发布请求包含
准备日志、版本提交、推送、触发构建和公开 Release；Agent 应完成整个流程，不把模板填写、
Git 操作或 Actions 按钮操作交给用户。仅修改发布工具或讨论发布方案不表示要求立即发布。

Agent 按以下顺序执行：

1. 核对当前分支、工作树归属、`origin/main` 和已有 Release/Tag。提交本次明确归属的产品改动，
   不混入并行工作。将经验证的发布内容集成到 `main`；共享工作区不适合切换时使用隔离检出。
   不强推、不覆盖并行改动、不默认把其他分支尚未完成的工作合入发布。
2. 用户指定版本就使用该版本；未指定时，若项目已有高于已发布版本的版本号则使用它，
   否则在最新版本上递增补丁号。对照上一已发布版本的代码差异、验证结果及实际产品行为整理变化；
   提交记录只能作为线索，不能直接当成发布正文。
3. 由 **Agent 编写** `docs/releases/<version>.md`，使用 [日志模板](../releases/TEMPLATE.md)。
   标题为 `# MyWallpaperX <version>`，一段面向用户的概述后分为
   **新增、修改、优化、修复、已知问题**；没有变化的类别写 `- 无。`，至少有一项实际变化。
   描述使用场景、行为变化及必要操作，不把未验证的效果写成已完成。无需用户填写或逐项确认。
4. 在已经集成好的 `main` 检出中运行：

   ```bash
   python3.12 script/publish_release.py <version>
   ```

   这个入口检查日志和工作树、获取远端最新标签、准备版本、只提交项目版本及对应日志、推送
   `main`，然后自动触发构建。它通过 GitHub API 返回的 run ID 追踪本次任务，等待运行结束，
   最后核对正式/Latest 状态、源码提交、日志正文、附件和 Sparkle 更新源。
   `source_sha` 输入会阻止 main 在推送与触发间变化时误发布另一份源码。
5. 期间 Agent 持续跟进并处理可修复失败；断线后根据已经输出的 run URL 恢复跟踪，
   不盲目再次触发。成功后给出 Release 链接、版本和验证结果。
   凭据缺失、GitHub/Apple 权限不足等无法自行解决的外部阻塞，要报告具体失败阶段。

`prepare_release_version.sh` 只是内部文件准备步骤，不自动提交或推送；完整发布入口是
`publish_release.py`。GitHub Release 和应用内 Sparkle 使用同一份日志。
日志缺失、空章节、模板占位或版本不一致直接失败，不存在提交记录回退路径；自动门检查
完整性，内容是否准确由 Agent 对照代码与证据复核。日常 push/PR 只运行
[CI](../../.github/workflows/ci.yml)，不会自动发布。`workflow_dispatch` 是 Agent 调用的技术入口，
不要求用户前往 GitHub 手工操作。

### 版本一致性

项目中的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION` 是版本号和构建号的唯一来源，
App/Daemon、Debug/Release 必须一致。准备版本时先读取公开的 `update-feed/appcast.xml`，
构建号取 `max(项目构建号, 已发布构建号) + 1` 并写入版本提交；CI 不再用 Git 提交数计算另一个构建号。
这也能跨过历史版本中源码构建号 277、实际公开构建号 278 的差异。

发布入口验证本地版本提交与远端 main SHA/项目版本一致；CI 在构建前要求版本号和构建号
都高于已发布版本，构建后核对 App 的 Info.plist，生成更新源后核对 appcast。
发布完成还会检查公开 appcast 的两个版本字段与本地一致、正式 Release 与 update-feed 的 XML 完全相同。
任一处不一致即停止，不能仅凭文件名或工作流成功认定发布完成。

正式包的内容边界、视频编码及资源裁剪规则见 [App 内容与体积](bundle-content.md)。

### 工作流顺序与产物

发布任务串行执行，不取消正在签名或上传的任务。一次运行只处理检出的固定提交：

1. 检查输入版本、正式日志、重复/倒退版本及已有 Release 草稿。
2. 运行仓库测试、代码健康检查，构建 arm64 Release。
3. 检查 bundle 内容；由内到外签署 SteamService、Scene 工具、WallpaperDaemon、Sparkle
   和主 App，再验证完整签名。SteamService 保留 JIT 权限，Sparkle Downloader 保留 sandbox 权限。
4. 公证并 staple App，使用保留符号链接的 `ditto` 装入 DMG；签署、公证、staple 并校验 DMG。
5. 生成带 EdDSA 下载签名和同一份日志的 Sparkle appcast；打包 dSYM、计算最终 DMG 的 SHA-256。
6. 保存 Actions artifacts；将 DMG、SHA-256、dSYM 和 appcast 上传到 Release 草稿，上传完成后
   发布为正式 Latest。公开版本不使用 `--clobber` 覆盖安装包。
7. 正式 Release 可下载后，才替换 `update-feed/appcast.xml`。已安装版本每天检查一次，也可以手动
   选择 **检查更新…**。

全量测试和签名、公证失败都会阻止公开 Release。GitHub CI 没有私有 Workshop corpus，
离线测试、构建和发布成功不等于所有真实壁纸、真实账号或最低系统版本的运行验收。

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

`script/sign-steam-helper.sh <helper-dir> <identity>` signs native dependencies
before the apphost. Real signing identities use hardened runtime and apphost
`com.apple.security.cs.allow-jit`; native libraries must have the same Team ID.
The outer App is signed after nested code, without `--deep --force` re-signing
that would overwrite helper entitlements. Ad-hoc `-` is a local, unhardened test
path because it has no Team ID for library validation. It does not prove the
Developer ID/notarization gate.

The arm64 bundle validator requires the helper, its runtime and license material.
A release still needs actual signed-bundle launch, full account/list/download
flow on the minimum supported Mac, notarization and Gatekeeper verification.
Build or offline self-tests do not close those gates.
