# MyWallpaperX Web 现役状态

> 状态：Web 当前状态唯一入口
>
> 源码复核：2026-08-11
>
> 证据边界：本页已核对当前源码所有权与文档合同，但本次文档收口没有构建 App、启动 Web runtime 或重跑样本矩阵。2026-07 的签名 App、固定/完整矩阵和外部样本结果均为历史运行基线，不代表当前 HEAD 已重新验证。

本页回答 Web 当前生产路径由谁拥有、哪些结论只有源码证据、哪些发布项仍未闭合。长期语言、进程与性能边界统一由[技术栈与架构路线边界](../architecture/technology-stack-boundaries.md)规定；测试证据口径由[Web 壁纸运行能力评测标准](web-wallpaper-benchmark-standard.md)规定。

## 1. 当前生产所有权

| 系统 | 当前所有者 | 当前边界 |
|---|---|---|
| 项目解释 | `SteamWorkshopService` 的 Web Core | 原始 `project.json` 是声明源；构建 descriptor、runtime model、playback context 与诊断，不覆盖作者文件 |
| 播放协调 | `WallpaperEngine` | 保存当前 Web request/content/property 状态，处理暂停、恢复、属性、音频需求、显示器与 runtime 切换 |
| 生产宿主 | `DedicatedWebWallpaperHostPlaceholderAdapter` | 当前默认 `.dedicatedHostPlaceholder` 策略；负责每显示器 WKWebView surface、生命周期、输入、属性、音频和本地资源桥接 |
| daemon Web 路径 | `WallpaperDaemon` Web extensions | 只作为 `.daemonDiagnosticsHarness` 排障路径；不是默认生产 Web 宿主，也不是后续扩展两套宿主的理由 |
| 本地资源 | `WebWallpaperLocalSchemeHandler` 等 | 受控读取项目根、MIME/响应转换和兼容资源映射；不能扩大为任意文件访问 |
| 评测工具 | `script/web_wallpaper_benchmark.py` 及矩阵 | 采集 App 身份、日志、DOM/窗口/动画证据；没有 fixture 时不能伪造 PASS |

当前生产 Web 播放链为：

```text
project.json / Workshop directory
  -> ResolvedWebProjectDescriptor
  -> ResolvedWebRuntimeModel
  -> ResolvedWebPlaybackContext
  -> WallpaperEngine
  -> DedicatedWebWallpaperHostPlaceholderAdapter
  -> per-display WKWebView surface
```

`Placeholder` 是尚未完成命名收口的历史名称，不表示该类型没有产品执行权。重命名必须作为独立机械批次完成源码、测试、日志 schema 和文档同步；不得同时改变宿主行为。

## 2. 稳定实现合同

- 原始 `project.json`、目录和资源布局保持只读；本地 descriptor/cache 是派生执行数据，不反向改写样本。
- Web 与视频、Scene 的产品状态分离，但共享高层播放切换、显示器、系统中断和音频采集合同。
- 每个播放 request 使用显式 identity；旧 navigation、旧 surface、旧 property replay 和旧异步回调不得修改新 request。
- Web 项目通过受控本地 scheme 和明确的资源根加载，不以任意 `file://` 权限换取兼容。
- Wallpaper Engine property、audio、media、pause、input 等桥接按声明和需求启用；存在 handler 或路由不等于用户可见行为已经通过。
- macOS 桌面输入不宣称与 Windows Wallpaper Engine 等价。单宿主的 click-through、hit test 和短时接管必须以“不吞桌面输入、不产生长期 focus/Space 副作用”为上限。
- 不新增第二套生产 Web 宿主。只有现有宿主无法满足且有可复现证据时，才允许提出替代方案；替代必须同批撤销旧 owner。

## 3. 当前证据状态

| 结论 | 当前证据 | 可表述范围 |
|---|---|---|
| 四层 project/runtime 模型存在 | 当前 Swift 类型和调用链 | 可称“源码已实现”，不能据此称所有项目可运行 |
| 默认生产宿主与 daemon harness 已分流 | `WallpaperEngine.currentWebHostStrategy` 与 launch switch | 可称“当前代码所有权明确”，不证明发布环境切换无回归 |
| 本地资源、属性、输入、音频与生命周期实现存在 | 当前 Core/Host 源码 | 只能证明对应路径存在，用户可见兼容仍以运行门为准 |
| 2026-07 固定、完整和外部样本结果 | [统一历史索引](../history/README.md)中的 dated roadmap 与 baseline | 只作为历史比较基线，不代表当前 HEAD PASS |
| 当前 HEAD 发布级 Web 闭环 | 本批未运行 | **未验证**，不得写成已完成 |

新的“当前 PASS”、样本数量、得分、coverage、Team ID、CDHash 或报告路径只能在同一源码/构建身份完成正式门后写回本页；被替代的历史数字收入统一 history，不复制到 README 或长期技术规范。

## 4. 未闭合边界

下列项在没有新证据前保持未闭合：

- 当前 HEAD 的签名 Debug/Release Web 固定门、完整门和外部样本门；
- 视频/Web/Scene 连续互切、进程崩溃与 stale request 恢复；
- 真实锁屏、睡眠、Space、显示器热插拔和音频设备变化；
- 文件选择器、security-scoped bookmark、sandbox、hardened runtime 与发布包权限；
- 首帧、切换 hitch、CPU/GPU frame time、WebContent 内存、能耗和多显示器长期预算；
- 网络离线/恢复、Service Worker/WASM/大型项目和第三方远程依赖的明确产品策略；
- `DedicatedWebWallpaperHostPlaceholderAdapter` 的命名收口和 daemon diagnostics harness 的最终退役条件；
- “所有 Workshop Web 壁纸”“Windows 行为/像素等价”之类无界兼容声明。

## 5. 开发与验收顺序

1. 从当前可复现问题建立 request、host、resource、property/input/audio 或环境根因，不从历史样本得分猜任务。
2. 修共享合同，禁止 sample ID、路径、站点或资产名特判。
3. 先跑受影响的项目自有测试和定向隔离样本；跨宿主生命周期风险再选择固定门。
4. 完整矩阵、外部样本与发布验证只在 milestone/release 或较小证据无法排除跨样本风险时运行。
5. 性能批次按长期[性能与效率合同](../architecture/technology-stack-boundaries.md#8-性能与效率合同)记录首帧、frame time、hitch、内存、能耗和恢复，不能只报告平均分或页面非黑。
6. 验证完成后同步本页的证据状态；批次过程、截图和报告细节进入 regression 或 Git，不继续扩张本页。

## 6. 历史入口

- [统一历史索引](../history/README.md)：2026-04 兼容/输入方案、2026-07 Web/Scene 状态快照，以及两组代表样本基线。历史材料不决定当前开发顺序。
