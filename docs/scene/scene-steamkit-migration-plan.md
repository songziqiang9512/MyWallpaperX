# SteamCMD → SteamKit2 迁移计划

> 状态：规划中（M4.2/M4.3/M6 的前置批次）
>
> 复核：2026-09-15
>
> 许可：SteamKit2 = LGPL-2.0（独立进程调用，不传染）；MirageWallpaper = GPL-3.0（仅参考架构，不复制代码）

## 1. 现状架构（要替换的）

| 功能 | 当前实现 | 问题 |
|---|---|---|
| Steam 登录 | SteamCMD PTY 交互（密码明文写入 PTY） | 密码暴露、无会话持久化、每次下载重登 |
| 已订阅浏览 | WKWebView cookie + steamcommunity.com HTML 抓取 | 页面结构变化即 break |
| 下载 | SteamCMD `workshop_download_item` 串行 | 无进度、无限速、无并行 |
| 订阅操作 | ❌ 不支持 | 用户无法从 App 内管理订阅 |
| 收藏管理 | ❌ 不支持 | — |
| 错误检测 | stdout 文本匹配 | 脆弱、依赖 SteamCMD 输出格式 |

## 2. 目标架构（SteamKit2）

```
MyWallpaperX.app (Swift)
    │ Process() 孵化
    │ stdin: JSON 命令 ──→ SteamService (.NET 8 + SteamKit2 3.4.0)
    │ stdout: JSON 事件 ←──   ├── SteamSession.cs: 登录/会话/Guard
    │                         ├── SubscriptionService.cs: 订阅列表/操作
    │                         └── WorkshopDownloader.cs: CDN 下载
    ├── SteamDaemonClient (Swift): 管道帧协议 + 退避重启
    └── UI: 状态栏/设置面板/浏览页/下载页
```

SteamService 二进制 self-contained ~78MB（.NET runtime 内嵌），作为 helper 进程替代 SteamCMD。

## 3. 功能映射表：现有 UI → SteamKit2 迁移

### 3.1 登录

| 现有 UI 元素 | 当前数据流 | SteamKit2 迁移后数据流 |
|---|---|---|
| 详情面板登录按钮 | `authenticateUser()` → SteamCMD PTY `login user pass` | `SteamService stdin: {"cmd":"login", ...}` → SteamKit2 `LogOn` → 回调返回成功/需 Guard/失败 |
| Steam Guard 面板 | PTY stdout 文本匹配 → 用户输入令牌 → PTY 写入 | SteamKit2 回调 `NeedTwoFactor` → UI 弹窗 → `{"cmd":"submitGuard", "code":"..."}` → SteamKit2 提交 |
| Keychain 凭据存储 | UserDefaults 明文 username + Keychain password | RefreshToken 存 Keychain（SteamKit2 原生提供），下次启动 `restoreSession` 不需重输密码 |
| 登录状态检测 | `hasSavedCredentials` (检查 UserDefaults 非空) | `IsLoggedOn` SteamKit2 属性 + `sessionAlive` 心跳 ping |

### 3.2 浏览（含已订阅列表）

| 现有 UI 元素 | 当前数据流 | SteamKit2 迁移后数据流 |
|---|---|---|
| 浏览页来源筛选（"Steam 已订阅"） | WKWebView cookie → steamcommunity.com HTML 抓取 | **保持不变**——HTML 抓取路径继续工作，SteamKit2 不替代浏览器 |
| "我的收藏" 来源 | 同上 | **保持不变**——同上 |
| 下载列表 | 本地 `downloads: [SteamWorkshopDownloadRecord]` | **保持不变**——这是本地记录，非 Steam 订阅 |
| **新增：已订阅标签** | ❌ 不存在 | `listSubscriptions` → JSON 结构化列表 → 新 Subscriptions 标签 UI |

**结论**：浏览功能不需要迁移——WKWebView cookie 会话与 SteamKit2 是并行的两条路径。SteamKit2 负责下载和订阅管理，浏览器负责内容浏览。

### 3.3 下载

| 现有 UI 元素 | 当前数据流 | SteamKit2 迁移后数据流 |
|---|---|---|
| 详情面板"设为壁纸" | `setAsWallpaper` → SteamCMD `workshop_download_item` | `SteamKitDaemonClient` → `{"cmd":"downloadWorkshopItem"}` → CDN 并行下载 → 完成后启动 |
| 下载进度 | `upsertTransientRecord(status:.downloading)` (无进度百分比) | SteamKit2 CDN 回调 → 1Hz `frameStats` 事件携带下载进度 |
| 下载完成 | SteamCMD 退出码判断 + 文件系统检查 | SteamKit2 `DownloadComplete` 事件 + 文件验证 |

### 3.4 订阅操作（全新能力）

| UI | 数据流 |
|---|---|
| 详情面板"订阅"按钮 | `{"cmd":"subscribe", "workshopId": N}` → SteamKit2 `CPublishedFile_Subscribe` |
| 详情面板"取消订阅"按钮 | `{"cmd":"unsubscribe", "workshopId": N}` → SteamKit2 `CPublishedFile_Unsubscribe` |
| 订阅状态查询 | `{"cmd":"checkSubscriptionStates", "ids":[...]}` → 批量查询 |

## 4. IPC 协议 v1（SteamService ↔ 主程序）

### 命令（stdin → SteamService）

| 命令 | 载荷 |
|---|---|
| `login` | `{username, password}` |
| `restoreSession` | `{refreshToken}` |
| `submitGuard` | `{code}` |
| `listSubscriptions` | — |
| `subscribe` | `{workshopId}` |
| `unsubscribe` | `{workshopId}` |
| `checkSubscriptionStates` | `{workshopIds: [N,...]}` |
| `downloadWorkshopItem` | `{workshopId, outputRoot}` |
| `ping` | — |
| `shutdown` | — |

### 事件（SteamService → 主程序）

| 事件 | 载荷 |
|---|---|
| `ready` | 进程启动确认 |
| `connected` | Steam 网络连接成功 |
| `loggedOn` | `{refreshToken}` — 登录成功 |
| `needGuard` | 需要 Steam Guard 令牌 |
| `loginFailed` | `{result}` — 登录失败 |
| `subscriptionList` | `{items: [{publishedFileId, title, fileSize, previewUrl, timeCreated, timeUpdated}]}` |
| `subscriptionStates` | `{states: [{publishedFileId, isSubscribed}]}` |
| `downloadProgress` | `{workshopId, downloadedBytes, totalBytes, percent}` |
| `downloadComplete` | `{workshopId, outputRoot}` |
| `downloadFailed` | `{workshopId, reason}` |
| `pong` | 心跳响应 |
| `exited` | 进程即将退出 |

## 5. RefreshToken 持久化

SteamKit2 登录成功后返回 `RefreshToken`（JWT 格式，有效期 ~200 天）。持久化方案：

| 层 | 存储 | 内容 |
|---|---|---|
| Keychain | `SteamKitRefreshToken` | RefreshToken 字符串 |
| UserDefaults | `SteamKit.RefreshTokenSavedAt` | 上次保存时间 |

启动流程：
1. 主程序启动 → 检查 Keychain 有 RefreshToken？
2. 是 → 孵化 SteamService → 发送 `restoreSession {refreshToken}` → 无需密码
3. 否 → 需要用户手动登录（`login` 命令）→ 成功后保存 RefreshToken 到 Keychain

## 6. UI 变更清单

| UI 元素 | 现有 | 迁移后 |
|---|---|---|
| 详情面板登录按钮 | `authenticateUser()` → SteamCMD PTY | → SteamKit2 `loginPassword` → `needGuard`/`loggedOn` 事件 |
| Steam Guard 输入面板 | PTY stdout 文本匹配 → 用户输入 | SteamKit2 回调 → `needGuard` 事件 → 同一面板 |
| 浏览页"Steam 已订阅" | WKWebView cookie HTML 抓取 | **保持不变**（与 SteamKit2 并行） |
| **新增：已订阅标签** | ❌ | 基于 `subscriptionList` 事件的新标签页，展示已订阅项目列表 + 一键下载 |
| 详情面板"订阅"按钮 | ❌ 不存在 | 新增 subscribe/unsubscribe 按钮（`checkSubscriptionStates` 查状态） |
| 设置面板静音 | `PlaybackMuteState` 公共权威 | **不变** |
| 设置面板 FPS 档 | `PlaybackPerformanceProfile` | **不变** |
| 状态栏静音/播放/切换 | 命令层 multiplexer | **不变**（scene handler 内部从 SteamCMD 切 SteamKit） |
| 下载进度 | `statusMessage` 文本 | 1Hz `downloadProgress` 事件 → 进度条 UI |

## 7. C# SteamService 文件结构

```
SteamService/
├── SteamService.csproj          .NET 8, SteamKit2 3.4.0
├── Program.cs                   stdin 命令循环 + dispatch
├── SteamSession.cs              SteamKit2 客户端（登录/回调/Guard/RefreshToken）
├── SubscriptionService.cs       订阅列表/状态/订阅操作
├── WorkshopDownloader.cs        CDN 下载（分块、进度回调）
├── Protocol.cs                  JSON 命令/事件类型定义
└── .gitignore                   bin/ obj/
```

## 8. Swift 侧文件变更

| 文件 | 变更 |
|---|---|
| `Core/PlaybackControl/SteamKitDaemonClient.swift` | 新增：孵化 SteamService + 管道通信 + 命令映射 |
| `Core/SteamWorkshopScene/Runtime/SceneDaemonClient.swift` | 现有 scene daemon client，不变 |
| `Modules/SteamWorkshop/Core/SteamWorkshopService+Authentication.swift` | 改为调用 SteamKitDaemonClient |
| `Modules/SteamWorkshop/Core/SteamWorkshopService+Downloads.swift` | 改为调用 SteamKitDaemonClient |
| `App/MyWallpaperXApplication.swift` | 注册 SteamKitDaemonClient 到 multiplexer |
| `Shared/Settings/AppKitSettingsView.swift` | **不变**（已通过命令层间接调用） |
| `App/StatusBarController.swift` | **不变**（已通过命令层间接调用） |

## 9. 迁移批次

| 批次 | 内容 | 验收门 |
|---|---|---|
| S1 | 安装 .NET SDK → 创建 C# 项目 → 编译 self-contained 二进制 → 手动 ping 测试 | 二进制存在，ping → pong |
| S2 | 实现 SteamSession（登录/Guard/RefreshToken/断线重连）→ 编译通过 → 手动 login 测试 | 登录成功 + RefreshToken 输出 |
| S3 | 实现订阅列表 + CDN 下载 → 编译通过 → 手动 listSubscriptions + downloadWorkshopItem 测试 | 订阅列表返回 + 下载完成 |
| S4 | Swift 侧 SteamKitDaemonClient + Xcode 工程集成 | 主程序可孵化 + 命令管道全链通 |
| S5 | 接入现有控制面：Authentication/Downloads 切 SteamKit | 状态栏/设置/下载全链无感切换 |

## 10. 许可

| 组件 | 许可 | 影响 |
|---|---|---|
| SteamKit2 | LGPL-2.0 | 独立进程调用，不传染主 App |
| Mirage SteamService | GPL-3.0 | 仅参考架构，不复制代码 |
| 本项目 SteamService 实现 | 本项目许可 | 原创 C# 代码 |

## 11. 环境

| 工具 | 状态 | 安装方式 |
|---|---|---|
| .NET 8 SDK | ✅ 已安装 (`~/.dotnet/dotnet` 8.0.401) | 手动 tarball 解压 |
| SteamKit2 3.4.0 | ✅ NuGet 包已还原 | `dotnet add package SteamKit2` |
| self-contained 二进制 | ✅ 78MB 已验证可运行 | `dotnet publish -c Release -r osx-arm64 --self-contained` |
