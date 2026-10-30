# Parallels Windows 官方 Scene 对照方法

用于本机 Parallels Windows 11 中的 Wallpaper Engine 对照、guest 文件准备、命令失败、窗口输入及截图排障。行为研究与一致性声明服从[官方研究工作流](../../../../docs/scene/development/official-client-behavior-research-workflow.md)；本页只保存操作方法，不保存固定 VM UUID、receiver PID、当前工具版本或样本结论。

## 先确认本轮允许做什么

用户已要求实际官方对照时，按该范围执行常规准备、官方 CLI 与已授权 native CUA，不反复询问已获授权的步骤。只有整理资料/只读侦查时，不启动、恢复、执行 guest 命令或操作 GUI。VM 状态变更、官方窗口与输入由一个操作者串行持有，先确认没有并行任务使用；独立的宿主只读调查可并行。

重启/reset、丢弃挂起状态、切快照、重装 Tools、改注册表/共享/输入/显示设置不属于命令失败后的默认重试。确需这些动作时，先说明已证故障和对其他任务的影响，按当前授权处理。旧脚本中存在某种 UI 或截图旁路不代表本轮获准使用。

## 分层定位，停在首个失败处

先区分上一条调用是**仍在等待**还是**已退出但无输出**，保留原始返回与本轮进程身份；未结束或归属不明时不重叠派发。短探针设置宿主侧有界超时；超时/取消只说明宿主停止等待，不证明 guest 已取消或回滚。只回收精确归属本轮的调用，先核 guest 进程、stage 和窗口的实际结果，再决定是否重试，不批杀 prlctl、PowerShell 或官方主客户端。

| 层 | 最小问题 | 失败时处理 |
|---|---|---|
| VM 与控制台 | 正确 UUID？running 还是 paused/suspended/stopped？控制台是否可见？ | 先查状态；按已授权范围恢复或启动，随后重查。不能在挂起 VM 上重试 guest 业务命令 |
| Tools / guest 执行 | 一条无副作用的短命令能返回吗？ | 查 Tools 与原始错误。无 guest 输出不证明 guest 什么都没做；先核目标现场，别盲重拷 |
| 用户与会话 | 当前用户、PowerShell、receiver 是否属于预期会话/路径？ | 重新发现实际 receiver；不使用旧 PID，不因控制进程退出就杀掉主客户端 |
| 文件与装载 | guest 本地 stage 与 manifest 一致？实际 project.file/VFS 正确？ | 只修运输/路径/编码；loose 文件与 PKG 同 hash 不证明挂载语义相同 |
| 官方命令与窗口 | 唯一预览窗口确实属于 receiver、可见且未遮挡吗？ | 用官方 CLI 和已有 native CUA 检查；返回0或窗口 metadata 不授画面资格 |
| 对照证据 | 同输入、状态、时间、音源及 viewport 的正控成立吗？ | 正控/截图资格不成立就记录未验证，不调整产品算法“修黑图” |

下面的命令片段只在本轮允许实际对照时使用；变量值从现场取得，不照抄历史记录。

## 1. 先用本机 CLI 发现事实

```sh
command -v prlctl
prlctl --version
prlctl exec --help
prlctl list --all --json
prlctl status "$ORACLE_VM"
prlctl list --info "$ORACLE_VM"
```

`prlctl list` 不带 `--all` 只列运行中的 VM，空表不能推成 VM 不存在。帮助语法是 `prlctl exec --help`，不是 `prlctl help exec`。`ORACLE_VM` 使用刚发现的 UUID，避免同名 VM 选错。需要时读本机 `man prlctl`，不要猜 `copy`、鼠标坐标或其它未列出的子命令。官方说明与本机帮助都要求 guest 执行安装 Parallels Tools。[P1][P2]

已经 running 时不要再 start 来“显示窗口”；running 不等于 guest 已解锁、桌面可交互或控制台已置前。stopped 与 paused/suspended 分别按本机帮助选择 start / resume，属于实际运行步骤；失败不升级成 reset / stop --kill / --drop-state。

短通道探针：

```sh
prlctl exec "$ORACLE_VM" --current-user whoami.exe
prlctl exec "$ORACLE_VM" --current-user powershell.exe -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()'
```

`--current-user` 选择 guest 当前登录用户的凭据；它不保证 GUI 在可见桌面上，也不是授权替代。需要识别 receiver 时，用短只读 PowerShell 查询进程的 `Id / ProcessName / SessionId / Path`，确认实际32/64位入口、版本、哈希与用户会话。CLI 转发进程与长期播放进程分开识别。若 guest 未登录/被锁定，先处理登录现场，不绕过锁屏或切换到另一账号来掩盖问题。

## 2. 直接 CLI 优先，脚本执行是有条件路径

宿主 shell → prlctl → Windows 程序 → PowerShell/cmd 是不同解析层。控制官方客户端时优先直接用参数数组执行官方 exe；准备数据时沿现有授权使用短的内置命令。复杂计算/生成留在宿主，guest 消费纯数据。需要 shell 时只保留一层，不把带括号、重定向和 JSON 的大串再包进 `cmd /c`，不把 manifest 值拼成 PowerShell 源码。

- 用已经可访问的共享目录运输本轮纯数据到 guest 本地独占 stage。共享路径先做一次可达性检查，不假设 `\\Mac\Home`、盘符或映射在每台 VM 都相同，也不扩大共享范围。共享/网络路径行为有疑义时，先用 guest 本地输入区分。[P3]
- 首次复制后按研究输入 manifest 核完整文件集、长度与 SHA；已有同一有效副本走 verify-existing。运输报错先检查实际目标是否完整，不能不明重拷或覆盖。不要在每次查询/截图前重做全文校验。
- Windows PowerShell 5.1 含非 ASCII 的脚本使用 UTF-8 BOM；JSON 使用显式 UTF-8 读取，例如 `Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8`。隐藏文件检查用 `-Force`，文件操作用 `-LiteralPath`。PowerShell 7 的编码缺省不同，先认清实际版本。[M1]
- `-EncodedCommand` 的载荷是 UTF-16LE 后 Base64；它处理嵌套引号，不缩短命令，也不绕过运输/Windows 各层限制。仅在短载荷且该路径已验证时使用，不能由一次 `Invalid argument` 推断一个通用长度上限。[M2]

**`.ps1 + -File` 不是本机默认保证可用的长命令解法。** 已有 UNC 脚本以 `SecurityError / UnauthorizedAccess` 被执行策略拒绝的收据，而同批直接官方 CLI 返回成功。只有确实需要脚本时，先在同用户、同 PowerShell 上查询 `Get-ExecutionPolicy` 及 `Get-ExecutionPolicy -List`；此查询也只在本轮获准操作 VM 时执行。[M3]

- `Restricted` 允许单独命令而拒绝脚本；不能由短 `-Command` 成功推成 `.ps1` 可执行。`RemoteSigned` 下 UNC/来源区域也可能影响脚本。复制到C盘、补BOM只处理位置/编码，不能解除 Restricted。
- 只有同一上下文已确认允许该脚本时，才把复杂逻辑放 `.ps1`、参数放 JSON，再用短 `-File`；`-File` 后全部是脚本路径及参数。[M2] 不把被拒脚本读成字符串交 `Invoke-Expression` / EncodedCommand 原样执行。
- 不默认加 `-ExecutionPolicy Bypass`、`Unblock-File` 或改全局策略来让示例跑通。若当前授权明确包含进程级策略调整，仍要确认其实际生效，组策略优先于进程参数，不能保证 Bypass 有效。[M3]

分开记录拒绝来源：工具审批拒绝须停在该操作边界，不能换包装重发；Windows 的 `SecurityError / UnauthorizedAccess` 查执行策略；`PrlJob...Invalid argument` 查运输，三者不混。通过策略允许的脚本如需返回外部程序退出码，显式 `exit $LASTEXITCODE`，不让后续打印覆盖失败。分开保存 prlctl 原始返回、stage 校验、官方 CLI 结果与窗口/截图结果；没有 guest 收据不归因到 shader 或时间线。

## 3. 官方客户端用公开 CLI 控制独占窗口

先保证正确版本的官方主客户端已经运行，再用对应的 `wallpaper32.exe` / `wallpaper64.exe` 发送控制命令。以下是**guest PowerShell 脚本内容**，不是在 macOS 执行的命令；三个变量分别为已发现的官方可执行文件、已准备的输入入口和本轮唯一窗口名。[W1]

```powershell
& $OracleExe -control openWallpaper -file $ProjectPath -playInWindow $WindowName -width 960 -height 540
exit $LASTEXITCODE
```

- 示例960×540不是验收预设；实际使用本轮两端约定的 viewport，不能只改单端来迁就屏幕。`-file` 按实际项目入口和 VFS 选择，显式记录 preset/属性。不要假定预览窗口继承桌面当前全部设置。需要置前时，使用该客户端已验证的公开 `activate` 参数或已有 native CUA。
- `getWallpaper -location <窗口名>` 可辅助确认输入路径；不能证明资源 ready、动画阶段或像素正确。
- `applyProperties` 的 JSON 遵守公开 `RAW~(` / `)~END` 封装。包含 JSON 的调用还要核对宿主/PowerShell 的实际参数传递，不能只看生成字符串“像正确”。
- 清理用 `closeWallpaper -location <本轮窗口名>`。无 location 的关闭、全局 pause/stop/mute 或 openProfile 会影响其他输出，不作为单窗口操作的默认动作。

公开 CLI 不作为任意 seek、截图或 Timeline API 使用；未文档化参数不能靠猜。自有脚本探针仍走现有研究方法，并独立验证时间相位与正控。

## 4. 点击无反应与黑截图

先用已有 native CUA 观察：正确 VM 控制台是否在前台、guest 是否已解锁、是否有模态/UAC覆盖、焦点是否在终端或另一个窗口、鼠标是否被 VM 捕获。点击一次再看新状态；不要对一张旧图连续发送坐标。全屏/Coherence/窗口模式、Retina缩放和 guest 分辨率发生变化后，重新取得窗口与 client rect，再注册 ROI，不能沿用旧坐标。

普通桌面交互不要先开启游戏鼠标优化。官方旧 KB 对“键盘不工作”和“鼠标不能自动捕获”给出不同设置方向，不能混成统一修法；确认具体症状和现有设置再决定是否调整。[P4][P5] 本机 man 还列有 Modality 点击透传选项；只有实际处在该模式且设置吻合时才考虑，不全局改配置碰运气。

`prlctl capture` 是官方 PNG 捕获命令，但黑图不是渲染失败的充分证据。本项目已有 capture 全黑而 native CUA 图像有效、终端遮挡预览的记录；取得实际像素正控后才裁 ROI。title/class/PID/visible/client rect只证明窗口身份。Tools 通道通、窗口在、截图有效、语义正控通过是四件事，不互相代替。

若工具访问/操作被拒绝，或现有 CUA 无法给出合格图像，记录阻塞与失败层；不新增 PostMessage/SendInput、脚本截图、RDP/另一输入后端来绕过现有 UI 工具边界。换会话/后端也可能改变图形、音频与焦点条件，不能无记录继续作同一对照。

## 5. 常见失败的下一步

| 现象 | 下一步；不要做什么 |
|---|---|
| `IO_STOPPED`、VM paused/suspended | 查电源状态与所有者；恢复后先跑短探针，不重复派发壁纸实验 |
| `PrlJob_GetRetCode: Invalid argument`，长 cmd/EncodedCommand 无输出 | 保留错误并核 stage；改短探针/直接 CLI，仅策略允许时用短 `-File`，不猜固定长度上限 |
| `.ps1` 返回 `SecurityError / UnauthorizedAccess` | 查同用户/同PowerShell的有效策略及各scope；不当BOM或长命令故障，不编码绕行/默认Bypass |
| 复制后打不开，中文/隐藏文件异常 | 查实际共享路径、BOM、JSON编码、`-LiteralPath`/`-Force`与 project.file，不改渲染器 |
| 命令返回0但没看到新窗口 | 查当前 receiver/SessionId、入口、唯一窗口名和实际桌面，不认为返回0就是成景 |
| 窗口可见但点不到 | 查捕获、遮挡、焦点、模式与缩放，用新UI状态定位；不重启来代替诊断 |
| 捕获全黑或 ROI 落到终端 | 重新资格采集与正控；不判定壁纸黑屏或调整颜色算法 |

同一失败不原样循环；换最小探针定位一层，仍不能区分就停止语义实验并保存现场。只关闭本轮窗口、清理已停止使用的独占 stage；原主客户端与 VM 的去留按原授权，交还资源时报告实际状态，不默认停机。

## 来源与复核

官方资料核对日期：2026-10-30；命令形式另以本机 `prlctl <action> --help` 和 `man prlctl` 只读复核。本轮没有执行 guest 命令或操作 VM，不宣称上述全部分支在当前 Windows 会话实测成功。

- [P1：Parallels 开发指南 CLI](https://docs.parallels.com/landing/parallels-desktop-developers-guide/command-line-interface-utility)：适用版本/版本类型及工具职责。
- [P2：Parallels Command-Line Reference](https://download.parallels.com/desktop/v20/docs/en_US/Parallels%20Desktop%20Command-Line%20Reference.pdf)：Tools、exec/current-user、状态与电源语义。该下载路径含 v20，但 PDF 封面仍为 v18；不是当前版本完整开关清单，以本机帮助补正。
- [P3：Parallels 第三方软件排障](https://kb.parallels.com/en/112983)：共享/网络路径与 guest 本地输入的区分。
- [P4：鼠标自动捕获](https://kb.parallels.com/en/116990)、[P5：键盘排障](https://kb.parallels.com/en/113932)：旧 KB 只辅助区分症状，不泛化驱动/配置修复。
- [M3：PowerShell 执行策略](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-5.1)：Restricted、UNC与策略优先级。
- [M1：PowerShell 编码](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding?view=powershell-5.1)、[M2：powershell.exe 参数](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1)。
- [W1：Wallpaper Engine 官方 CLI](https://help.wallpaperengine.io/en/functionality/cli.html)：公开命令、窗口 location 与属性格式；后续使用仍核固定客户端行为。
- 本机既有观察只支持方法选择：[短 PowerShell 运输与唯一窗口清理](../../../../docs/scene/history/light-particle-qualification-2026-10-23.md)、[receiver 更新及遮挡正控](../../../../docs/scene/history/composition-local-perspective-2026-10-16.md)、[黑 capture 不作结果](../../../../docs/scene/history/vec3-mixed-dimension-arithmetic-2026-10-16.md)。不把旧 PID、路径、STOP 或成功状态当当前事实。

本机脚本拒绝与直接CLI成功的原始收据（未入库、可能按证据政策迁移）分别为 `.artifacts/vector-return-qualification-20261030/official-stage-result.json` 与 `official-direct-cli-result.json`。它们证明一次真实拒绝/不同调用路径结果，不证明当前会话策略值；不得把它们改写为所有 `.ps1` 永远不可执行。
