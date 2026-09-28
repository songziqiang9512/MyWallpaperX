<p align="center">
  <img src="MyWallpaperX/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Default-1024x1024@1x.png" width="112" height="112" alt="MyWallpaperX 图标">
</p>

<h1 align="center">MyWallpaperX</h1>

<p align="center"><strong>让 macOS 桌面动起来。</strong><br>视频、网页与实时场景壁纸，一个原生工作台。</p>

<p align="center">
  <a href="https://github.com/songziqiang9512/MyWallpaperX/releases"><img src="https://img.shields.io/github/v/release/songziqiang9512/MyWallpaperX?style=flat-square&color=5865f2" alt="最新正式版本"></a>
  <img src="https://img.shields.io/badge/macOS-26.0%2B-222222?style=flat-square" alt="macOS 26.0 及以上">
  <img src="https://img.shields.io/badge/Apple_Silicon-arm64-222222?style=flat-square" alt="Apple Silicon arm64">
</p>

<p align="center">
  <a href="https://github.com/songziqiang9512/MyWallpaperX/releases">下载应用</a> ·
  <a href="https://www.mwpx.me">官方网站</a> ·
  <a href="docs/releases/2.10.0.md">2.10.0 更新说明</a> ·
  <a href="https://github.com/songziqiang9512/MyWallpaperX/issues">反馈问题</a>
</p>

---

MyWallpaperX 是一款以 Swift 和 AppKit 构建的 macOS 壁纸应用。你可以整理本地素材、发现在线资源，也可以登录 Steam 浏览和下载 Wallpaper Engine 创意工坊作品，再把喜欢的内容设为桌面壁纸。

本页介绍当前源码的功能。正式发布版本及其安装包以 [GitHub Releases](https://github.com/songziqiang9512/MyWallpaperX/releases) 为准。

## 三种动态壁纸

| 类型 | 适合什么内容 | 可以做什么 |
| --- | --- | --- |
| **Video · 视频** | 风景短片、循环动画、实拍影像 | 导入本地视频，调整填充方式与播放速率，使用循环、顺序或随机播放 |
| **Web · 网页** | 时钟、网页动画、交互式桌面 | 通过 WebKit 运行工坊网页项目，调节作者开放的属性，使用受支持的鼠标、音频和媒体交互 |
| **Scene · 实时场景** | 多图层动画、粒子、特效与动态文字 | 通过 Metal 实时渲染场景，调节作品属性，响应受支持的脚本、鼠标和音频输入 |

三种类型共用音量、静音、暂停与继续播放控制。设置中的焦点、全屏、电池供电和电脑不活跃暂停策略也统一作用于三种引擎。

**Scene 已进入基本可用阶段，兼容性仍在持续完善。** 支持范围内的作品可以用于日常播放；部分复杂材质、特效、脚本、粒子及交互仍可能缺失或与 Wallpaper Engine 有差异，复杂场景的性能也有优化空间。Web 作品若依赖远程服务或其他资源，也可能受网络和依赖完整性影响。这里不承诺所有工坊作品都能完整运行。

## 从发现到桌面

### 本地素材库

- 管理本地视频与图片，使用搜索、收藏、标签和最近使用整理素材。
- 通过网格、列表和详情面板查看内容，使用 Quick Look 快速预览支持的文件。
- 浏览 Pixabay 在线视频资源，下载后纳入本地库。

### Steam 创意工坊

当前获取链路使用 **SteamKit2**，已替换旧的 SteamCMD 方案。

- 应用内支持扫码、账号密码及 Steam Guard 验证，可保存登录状态、退出或切换账号。
- 浏览工坊榜单、按类型筛选、搜索作品，查看「我的订阅」和「我的收藏」。
- 查看作品详情与作者工坊，管理订阅，下载 Video、Web 和 Scene 内容。
- 下载面板显示排队、进度和错误；失败后可以重试，清除任务历史不会打断活动下载。
- 下载完成后按作品 ID 整理到本地目录；在工坊「已下载」列表删除作品，会同步删除对应文件。

> **按 ID 查作品：** 在创意工坊总榜的 Steam 搜索框输入 `ID=1234567890`，将示例编号换成作品 ID。位于作者页时，先返回总榜。

Steam 内容能否下载取决于服务状态、网络连接和账号访问权限。账号登录不会绕过作品授权，也不保证任意作品都可访问。

### 日常控制

菜单栏与工具栏提供常用播放入口；设置中可以配置节能策略、视频播放方式及全局快捷键。全局快捷键需要先启用并分配按键，播放／暂停和静音用于当前动态引擎，上一张／下一张用于视频切换。

更完整的工具栏说明、快捷键表、登录及下载报错排查，请打开应用的 **帮助** 菜单。帮助内容同时提供[中文源码](MyWallpaperXHelp/zh-Hans.lproj/index.html)与[英文源码](MyWallpaperXHelp/en.lproj/index.html)。

## 安装与开始使用

**当前构建要求 macOS 26.0 或更新版本，以及 Apple Silicon 芯片的 Mac。发行构建为 arm64，不提供 Intel 安装包。**

1. 从 [GitHub Releases](https://github.com/songziqiang9512/MyWallpaperX/releases) 下载正式版本的 DMG。
2. 打开 DMG，将 `MyWallpaperX.app` 拖入「应用程序」。
3. 启动应用，导入本地视频，或登录 Steam 获取工坊作品。
4. 选择壁纸并播放，再按需要调整音量、属性和节能策略。

发布流程包含 Developer ID 签名和 Apple 公证；本地开发构建与正式发行包的验证范围不同。具体版本的已知问题请查看对应 Release 的更新日志。

## 开发与贡献

项目使用 Xcode 构建。准备支持当前 SDK 的 Xcode、Python 3.12，以及 [`SteamService/global.json`](SteamService/global.json) 锁定的 .NET SDK；SteamService 的依赖版本由 NuGet lockfile 固定。

```bash
# 准备测试和 SteamService 依赖
python3.12 -m pip install -r script/requirements-tests.txt
(cd SteamService && dotnet restore --locked-mode)

# 用 Xcode 打开，按本机账号配置签名
open MyWallpaperX.xcodeproj

# 构建并启动；该脚本会先关闭正在运行的 MyWallpaperX
bash script/build_and_run.sh verify

# 根据当前改动选择验证门；先查看计划，再按需要执行
python3.12 -B script/verify_scene_change.py --base HEAD --phase inner
```

主界面与素材管理由 AppKit 承载；Video 使用 AVFoundation 和独立播放进程，Web 使用 WebKit，Scene 使用 Metal 与独立 Scene 播放进程。SteamService 通过 SteamKit2 负责 Steam 会话及内容获取。

| 想了解什么 | 从这里开始 |
| --- | --- |
| 项目文档与职责导航 | [文档入口](docs/README.md) |
| 开发、验证及工作区约束 | [AGENTS.md](AGENTS.md) |
| Scene 的结构与开发方式 | [Scene 入口](docs/scene/README.md) · [开发工作流](docs/scene/development/development-workflow.md) |
| Scene 已实现的能力和局限 | [能力台账](docs/scene/semantics/coverage-ledger.md) · [运行证据](docs/scene/semantics/runtime-evidence-current.md) |
| Web 的实现及验证边界 | [Web 当前状态](docs/web/current-state.md) |
| 自动打包、签名与 GitHub Release | [Agent 发布流程](docs/release/release-signing.md) |

提交问题时，请附上应用版本、macOS 版本、Mac 芯片型号、复现步骤及错误提示；工坊问题请提供作品链接或 ID。不要公开密码、验证码、登录令牌或其他账号凭据。

## 交流与支持

欢迎通过 [Issues](https://github.com/songziqiang9512/MyWallpaperX/issues) 反馈问题，也欢迎提交改进。交流 QQ 群：**569399751**。如果项目对你有帮助，可以点一个 [Star](https://github.com/songziqiang9512/MyWallpaperX)。

<p align="center">
  <img src="Screenshot/IMG_3047.JPG" width="220" alt="项目支持收款码一">
  <img src="Screenshot/IMG_3048.JPG" width="220" alt="项目支持收款码二">
</p>

MyWallpaperX 是独立项目，与 Valve、Steam、Wallpaper Engine 和 Pixabay 没有隶属关系。第三方作品的版权归原作者所有，请遵守作品许可及相关平台条款。
