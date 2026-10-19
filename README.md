<p align="center">
  <img src="MyWallpaperX/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Default-1024x1024@1x.png" width="112" height="112" alt="MyWallpaperX 应用图标">
</p>

<h1 align="center">MyWallpaperX</h1>

<p align="center"><strong>为 macOS 打造的原生动态壁纸工作台</strong><br>从本地影像到交互网页，再到实时场景，让喜欢的内容成为桌面的一部分。</p>

<p align="center">
  <a href="https://github.com/songziqiang9512/MyWallpaperX/releases/latest"><img src="https://img.shields.io/github/v/release/songziqiang9512/MyWallpaperX?style=flat-square&color=5b6ee1" alt="最新正式版本"></a>
  <img src="https://img.shields.io/badge/macOS-26.0%2B-24292f?style=flat-square&logo=apple&logoColor=white" alt="macOS 26.0 或更新版本">
  <img src="https://img.shields.io/badge/Apple_Silicon-arm64-24292f?style=flat-square" alt="Apple Silicon arm64">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0-167d5b?style=flat-square" alt="GNU GPL 3.0 许可证"></a>
</p>

<p align="center">
  <a href="https://github.com/songziqiang9512/MyWallpaperX/releases/latest">下载正式版</a> ·
  <a href="docs/releases/2.11.0.md">2.11.0 更新说明</a> ·
  <a href="https://www.mwpx.me">官方网站</a> ·
  <a href="https://github.com/songziqiang9512/MyWallpaperX/issues">问题反馈</a> ·
  <a href="docs/README.md">开发文档</a>
</p>

---

MyWallpaperX 是一款使用 **Swift / AppKit** 构建的开源 macOS 壁纸应用，集本地素材管理、在线发现、Steam 创意工坊获取与动态桌面播放于一体。视频由 AVFoundation 播放，网页由 WebKit 承载，Scene 场景通过 Metal 实时渲染。

> 本页介绍当前源码能力；已发布版本和安装包以 [GitHub Releases](https://github.com/songziqiang9512/MyWallpaperX/releases) 为准。项目自有代码采用 **GNU GPL 3.0** 开源许可，完整声明见[开源许可](#开源许可)。

## 一处管理，三种动态体验

| 壁纸类型 | 内容与体验 |
| --- | --- |
| **Video · 视频壁纸** | 导入本地影像，调整填充方式、音量和播放速率，支持循环、顺序与随机播放。 |
| **Web · 网页壁纸** | 运行工坊网页项目，调节作者开放的属性，呈现时钟、交互动画、音频可视化与受支持的歌曲信息。 |
| **Scene · 实时场景** | 通过 Metal 合成图层、粒子、文字和受支持的模型、材质与动画，响应作者脚本、鼠标、音频及属性设置。 |

三类动态壁纸共用播放、暂停、静音和音量控制；上一张／下一张可以在已安装的 Video、Web、Scene 作品之间切换，自动跳过缺少依赖或无法播放的项目。静态图片也可直接设为系统桌面。

### 从发现到桌面

- **整理素材**：本地视频与图片库提供搜索、收藏、标签、最近使用、网格／列表和详情预览；支持从 Pixabay 发现并下载视频。
- **浏览工坊**：在应用内登录 Steam，浏览榜单、类型、搜索结果、作者作品、「我的订阅」和「我的收藏」。支持扫码、账号密码及 Steam Guard 验证。
- **安排下载**：统一查看队列、进度和失败原因，暂停／继续任务、优先下载或批量重试。下载完成后进入本地工坊库；删除已下载作品会同步删除对应文件。
- **按作品调整**：通过原生属性面板修改作者提供的颜色、数值、选项、文字及受支持的文件属性；支持范围内的设置可直接更新到播放中的作品。

### 贴合日常使用

- **启动恢复**：可恢复上次使用的动态壁纸及暂停状态，也可关闭自动恢复。
- **节能策略**：按焦点、全屏、电池供电与电脑不活跃状态暂停壁纸；菜单栏和工具栏提供常用控制。
- **歌曲与音频响应**：Web、Scene 共用系统歌曲信息来源；兼容作品可显示歌曲、封面和播放进度，或响应系统音频频谱。歌曲信息默认关闭，按需启用并授予相应权限。
- **HDR 显示**：兼容 Scene 作品可在支持的屏幕上呈现 HDR 高光，也可在播放中切换回普通亮度。
- **播放隔离**：Video、Web、Scene 通过独立播放进程承载桌面内容，并协调壁纸切换、取消与失败回退。

## 安装与开始使用

| 项目 | 要求 |
| --- | --- |
| 操作系统 | **macOS 26.0 或更新版本** |
| 芯片 | **Apple Silicon（M 系列，arm64）** |
| 安装包 | GitHub Releases 提供的 DMG；当前不提供 Intel 版本 |
| Steam | 使用工坊获取功能时，需要可访问相应作品的账号与网络连接 |

1. 从 [GitHub Releases](https://github.com/songziqiang9512/MyWallpaperX/releases/latest) 下载正式版 DMG。
2. 打开 DMG，将 `MyWallpaperX.app` 拖入「应用程序」，然后启动应用。
3. 导入本地视频或图片，或登录 Steam 浏览并下载工坊作品。
4. 选择作品开始播放，再按需要调整作品属性、显示与节能设置。

正式发行流程包含 Developer ID 签名与 Apple 公证。应用内可通过 **检查更新…** 获取更新；具体变化及限制见对应 Release。

<details>
<summary><strong>使用提示与兼容性说明</strong></summary>

- **按作品 ID 查找**：在创意工坊总榜的 Steam 搜索框输入 `ID=1234567890`，将数字换为实际作品 ID；在作者页时请先返回总榜。
- **全局快捷键**：先在设置中启用并分配按键。上一张／下一张切换已安装的动态壁纸，播放／暂停和静音作用于当前动态引擎。
- **Scene 兼容性**：引擎仍在持续完善。部分复杂特效、脚本、粒子、模型动画和交互可能缺失或与 Wallpaper Engine 存在差异，复杂场景也有性能优化空间。支持某类效果不代表同类作品全部兼容。
- **Web 外部依赖**：部分作品依赖远程服务、字体或其他工坊内容，网络不可用或依赖缺失时可能无法正常显示。
- **歌曲信息**：显示内容取决于播放器提供的系统媒体数据、作品实现及权限；尚未覆盖所有播放器和歌词。应用不会因登录 Steam 而绕过作品授权。
- **更多帮助**：打开应用的「帮助」菜单查看操作与排错说明；仓库保留[中文](MyWallpaperXHelp/zh-Hans.lproj/index.html)和[英文](MyWallpaperXHelp/en.lproj/index.html)帮助内容。

</details>

## 开发与贡献

欢迎提交问题、改进建议与 Pull Request。提交问题时，请附上应用版本、macOS 版本、芯片型号、复现步骤与错误提示；工坊问题请同时提供作品链接或 ID。请勿公开密码、验证码或登录令牌。

本地构建需要支持 macOS 26 SDK 的 Xcode、Python 3.12，以及 [SteamService/global.json](SteamService/global.json) 锁定的 .NET SDK。发行包已包含 SteamService 所需运行时，普通用户无需安装开发工具。

```bash
git clone https://github.com/songziqiang9512/MyWallpaperX.git
cd MyWallpaperX
python3.12 -m pip install -r script/requirements-tests.txt
dotnet restore SteamService/SteamService.csproj --locked-mode
open MyWallpaperX.xcodeproj
```

在 Xcode 中选择 `MyWallpaperX` scheme，并按本机开发账号配置签名。共享 scheme 的 Run 使用 Release；需要调试诊断时使用 Debug 配置。验证命令及影响面选择见[开发工作流](docs/development/repository-workflow.md)。

| 开发主题 | 入口 |
| --- | --- |
| 开工规则与仓库职责 | [AGENTS.md](AGENTS.md) · [仓库地图](docs/architecture/repository-map.md) |
| 项目文档与技术边界 | [文档入口](docs/README.md) · [技术栈合同](docs/architecture/technology-stack-boundaries.md) |
| Scene 架构、能力与证据 | [Scene 入口](docs/scene/README.md) · [能力台账](docs/scene/capabilities/coverage-ledger.md) · [运行证据](docs/scene/capabilities/runtime-evidence-current.md) |
| Web 实现与限制 | [Web 当前状态](docs/web/current-state.md) |
| 签名、公证与正式发布 | [发布流程](docs/release/release-signing.md) |

## 开源许可

除另有声明的第三方代码、组件与资源外，**MyWallpaperX 项目自有代码采用 GNU General Public License v3.0（GPL-3.0-only）**。你可以在该许可证的条件下使用、修改和再分发本项目；分发时须遵守适用的源码提供、许可及版权声明保留等要求。

完整许可正文见 [LICENSE](LICENSE)，项目与第三方声明见 [NOTICE.md](NOTICE.md)。本软件按许可证约定提供，不附带适销性或特定用途适用性等担保。第三方依赖保留各自许可；壁纸、字体、图片、音视频等资源的权利与授权须分别遵守原声明。

MyWallpaperX 是独立项目，与 Valve、Steam、Wallpaper Engine 及 Pixabay 没有隶属或官方合作关系。Steam 与 Wallpaper Engine 等名称、商标及第三方作品的权利归各自权利人所有。

## 交流与支持

通过 [Issues](https://github.com/songziqiang9512/MyWallpaperX/issues) 反馈问题，或加入 QQ 群 **569399751** 交流。如果项目对你有帮助，欢迎点亮 [Star](https://github.com/songziqiang9512/MyWallpaperX)。

<details>
<summary>自愿支持项目开发</summary>

<p align="center">
  <img src="Screenshot/IMG_3047.JPG" width="220" alt="项目支持收款码一">
  <img src="Screenshot/IMG_3048.JPG" width="220" alt="项目支持收款码二">
</p>

感谢支持。赞助完全自愿，不改变开源许可证授予的权利。

</details>
