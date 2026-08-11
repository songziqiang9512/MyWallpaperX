# MyWallpaperX

<p align="center">
  <img src="MyWallpaperX/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Default-1024x1024@1x.png" width="120" height="120" alt="MyWallpaperX">
</p>

<p align="center">
  <samp>
    <b>macOS 原生动态壁纸工作台</b><br>
    <b>本地素材管理 · 在线资源浏览 · Steam Workshop 播放 · Metal Scene 渲染</b>
  </samp>
</p>

<p align="center">
  <a href="https://github.com/songziqiang9512/MyWallpaperX/releases">
    <img src="https://img.shields.io/github/v/release/songziqiang9512/MyWallpaperX?color=6366f1&style=flat-square" alt="Release">
  </a>
  <a href="https://github.com/songziqiang9512/MyWallpaperX/stargazers">
    <img src="https://img.shields.io/github/stars/songziqiang9512/MyWallpaperX?color=f59e0b&style=flat-square" alt="Stars">
  </a>
  <a href="https://github.com/songziqiang9512/MyWallpaperX/forks">
    <img src="https://img.shields.io/github/forks/songziqiang9512/MyWallpaperX?color=10b981&style=flat-square" alt="Forks">
  </a>
  <a href="https://github.com/songziqiang9512/MyWallpaperX/releases">
    <img src="https://img.shields.io/github/downloads/songziqiang9512/MyWallpaperX/total?color=8b5cf6&style=flat-square" alt="Downloads">
  </a>
  <img src="https://img.shields.io/badge/macOS-26.0%2B-06b6d4?style=flat-square" alt="macOS 26.0+">
</p>

<p align="center">
  <a href="https://www.mwpx.me">
    <img src="https://img.shields.io/badge/🌐_官方网站-mwpx.me-4da8da?style=for-the-badge" alt="官方网站">
  </a>
</p>

---

## 界面预览

<table width="100%">
  <tr>
    <td width="33%"><img src="Screenshot/截屏2026-05-12%2006.00.16.png" width="100%" alt="本地视频壁纸库"><p align="center"><b>本地壁纸库</b><br><sub>导入、搜索、收藏与标签管理</sub></p></td>
    <td width="33%"><img src="Screenshot/截屏2026-05-12%2006.02.03.png" width="100%" alt="壁纸浏览与管理"><p align="center"><b>浏览与管理</b><br><sub>macOS 原生列表、网格与 Quick Look 预览</sub></p></td>
    <td width="33%"><img src="Screenshot/截屏2026-05-12%2006.03.09.png" width="100%" alt="在线壁纸资源"><p align="center"><b>在线壁纸资源</b><br><sub>浏览 Pixabay 在线库并下载纳入本地</sub></p></td>
  </tr>
  <tr>
    <td width="33%"><img src="Screenshot/截屏2026-05-12%2006.03.56.png" width="100%" alt="Steam Workshop"><p align="center"><b>Steam Workshop</b><br><sub>原生网格浏览、下载和管理创意工坊</sub></p></td>
    <td width="33%"><img src="Screenshot/截屏2026-05-12%2006.05.39.png" width="100%" alt="下载与详情"><p align="center"><b>下载与详情面板</b><br><sub>集中查看下载状态、文件位置和素材信息</sub></p></td>
    <td width="33%"><img src="Screenshot/截屏2026-05-12%2006.00.16.png" width="100%" alt="桌面播放"><p align="center"><b>桌面播放</b><br><sub>视频守护进程与 Web / Scene 专用宿主协同播放</sub></p></td>
  </tr>
</table>

---

## 核心能力

MyWallpaperX 深度利用 macOS 原生能力，围绕**素材管理 → 资源获取 → 桌面播放**三条主线设计。

| 模块 | 状态 | 说明 |
|------|:----:|------|
| **本地视频壁纸库** | ✅ | 导入视频文件，支持收藏、最近使用、标签管理、Quick Look 预览、排序和详情检查器，面向长期积累 |
| **图片壁纸管理** | ✅ | 管理本地图片素材，瀑布流 / 网格双布局，标签整理，与视频库共享侧边栏与工具栏 |
| **Pixabay 在线库** | ✅ | 浏览 Pixabay 在线资源，异步下载并纳入本地库管理，支持下载状态追踪 |
| **Steam Workshop 浏览** | ✅ | 完全原生的 AppKit NSCollectionView 网格浏览 Wallpaper Engine 创意工坊，内置 SteamCMD Runtime |
| **视频壁纸播放** | ✅ | 独立 helper 进程承载视频播放，支持切换、音量、播放速率、音量控制，DaemonProtocol 跨进程通信 |
| **Web 壁纸支持** | ✅ | `project.json → descriptor → runtime model → playback context` 四层解析管线；当前代码所有权、历史运行证据和未闭合发布项见 [Web 现役状态](docs/web/current-state.md) |
| **Scene 壁纸渲染** | 🚧 | 已具备 Scene/PKG/TEX 解析、Metal 桌面宿主、基础层级，以及受限 graph/provider/effect、Timeline、动态输入、文字和粒子子集；SceneScript 与高级对象仍只有局部识别或严格受限 profile |
| **系统音频频谱** | 🚧 | 已验证真实音源相关性、Wallpaper Engine 64+64 双声道布局和兼容幅度响应；设备切换、系统静音和睡眠恢复仍待发布验收 |
| **菜单栏控制** | ✅ | 状态栏入口，GPU 占用实时显示，快速访问播放控制与模块切换 |

> **Scene 壁纸说明**：Scene 采用分级、fail-closed 的兼容路线。固定或完整样本门通过只证明对应输入和构建未回归，不代表通用格式支持或 Wallpaper Engine 视觉等价。当前等级与缺口见 [Scene 官方语义与实现覆盖台账](docs/scene/semantics/coverage-ledger.md)，最新构建、样本和签名证据见 [运行证据索引](docs/scene/semantics/runtime-evidence-index.md)。

> 文档导航见 [项目文档入口](docs/README.md)；长期技术路线见[技术栈与架构路线边界](docs/architecture/technology-stack-boundaries.md)。带日期的 roadmap、plan 和 review 默认只保留对应批次的历史结论，只有文档入口明确列出的现役迁移目标或现役执行计划例外。

---

## 系统架构

主界面、功能模块与播放链路按职责分区，并通过 Shell、服务入口和播放合同组合。当前仍是同一 App target 内的源码模块，Shell/App 会直接引用部分模块类型，**不承诺删除任意模块目录后仍可编译**；真正可选装的边界必须由独立 target/package、协议注册和构建门证明。

```text
MyWallpaperX.app
├─ App / Shell                 ← Swift + AppKit 主窗口、侧边栏、状态栏、菜单栏、模块导航
├─ Modules
│  ├─ VideoLibrary             ← 本地视频壁纸库（导入、收藏、标签、播放设置）
│  ├─ StaticImageLibrary       ← 本地图片壁纸库（瀑布流 / 网格、Quick Look）
│  ├─ OnlineLibrary            ← Pixabay 在线资源浏览与下载管理
│  └─ SteamWorkshop
│     ├─ Core                  ← Workshop API 模型、网络调度、下载管理、详情刷新
│     ├─ Web                   ← Web 壁纸属性系统、运行时缓存、校验与兼容诊断
│     ├─ Scene                 ← Scene 壁纸详情、诊断信息与播放路由
│     ├─ UI                    ← 原生 NSCollectionView 网格浏览、下载列表、详情面板
│     └─ Toolbar               ← Workshop 专用工具栏与操作
├─ Core
│  ├─ Playback                 ← WallpaperEngine、DaemonProtocol、系统音频频谱
│  ├─ SteamWorkshopWeb         ← Web 壁纸引擎（本地 scheme 处理器、兼容脚本注入、运行时桥接）
│  ├─ SteamWorkshopScene       ← Metal Scene 渲染器（场景解析、纹理加载、渲染管线）
│  └─ System                   ← 全局快捷键、系统状态监控
├─ Shared                      ← 通用 UI 组件、缩略图缓存、Inspector、网格布局
├─ Models                      ← VideoWallpaper 数据模型、播放设置
└─ Resources                   ← SteamCMD Runtime、内置视频素材

WallpaperDaemonSources         ← 独立 helper，承载视频播放与频谱呈现；Web daemon 仅保留诊断 harness
```

最终 UI 路线为 Swift + AppKit；当前少量 SwiftUI 只属于受控迁移残留。长期语言职责、性能合同、跨进程边界，以及 SceneScript VM / shader compiler 候选的准入规则见[技术栈与架构路线边界](docs/architecture/technology-stack-boundaries.md)。其中的候选路线不表示对应依赖或服务已经进入当前产品。

---

## 安装

> 前往 **[🌐 mwpx.me](https://www.mwpx.me)** 了解更多，或直接从 [GitHub Releases](https://github.com/songziqiang9512/MyWallpaperX/releases) 下载最新 `MyWallpaperX-*.dmg`。

打开 DMG，将 `MyWallpaperX.app` 拖入 `Applications` 即可。发布包由 GitHub Actions 自动构建，经 Developer ID 签名与 Apple Notarization 公证。

### 系统要求

- macOS 26.0+
- 支持 Apple Silicon 与 Intel Mac
- Steam Workshop 功能需可访问 Steam 服务

---

## 开发

```bash
# Xcode 打开项目
open MyWallpaperX.xcodeproj

# 脚本构建并运行
script/build_and_run.sh            # 构建并启动
script/build_and_run.sh debug      # 进入 LLDB 调试
script/build_and_run.sh logs       # 构建、运行并查看应用日志
script/build_and_run.sh verify     # 构建、运行并做最小启动验证

# 或直接使用 xcodebuild
xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -derivedDataPath .codex/DerivedData build
```

---

## 支持与捐助

如果这个项目对你有帮助，欢迎 [Star on GitHub](https://github.com/songziqiang9512/MyWallpaperX)。

反馈交流 QQ 群：569399751

<p align="center">
  <img src="Screenshot/IMG_3047.JPG" width="260" alt="收款码">
  <img src="Screenshot/IMG_3048.JPG" width="260" alt="收款码">
</p>

---

## 免责声明

MyWallpaperX 是一个面向 macOS 的个人壁纸管理与播放工具。

- 用户导入内容、账号使用和第三方平台条款由用户自行负责；本项目不隶属于 Steam、Valve、Wallpaper Engine、Pixabay 或其他第三方内容平台。

---

## Star 历史

<p align="center">
  <a href="https://www.mwpx.me">
    <img src="https://img.shields.io/badge/🌐_官方网站-mwpx.me-4da8da?style=for-the-badge" alt="官方网站">
  </a>
</p>

<p align="center">
  <img src="https://api.star-history.com/svg?repos=songziqiang9512/MyWallpaperX&type=Date" alt="Star History Chart">
</p>
