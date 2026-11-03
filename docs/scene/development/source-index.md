# Scene 资料来源

<!-- document-role: reference -->

本页是 named source taxonomy 的唯一分类入口；记录可用于开发的资料及其证明边界。当前能力见[能力索引](../capabilities/README.md)，当前执行依据见[运行证据](../capabilities/runtime-evidence-current.md)，研究方法见[官方行为研究](official-client-behavior-research-workflow.md)。

<a id="named-source-taxonomy"></a>
## 来源分类

| 类别 | 用途 | 证明边界 |
|---|---|---|
| `official-public-contract` | 官方作者文档、公开类型声明与示例 | 作者可观察合同；不公开私有格式或内部算法 |
| `official-client-dynamic-golden` | 固定官方客户端、输入和条件下的实际输出 | 只证明所测版本、事件、画面与时序范围 |
| `official-client-static-observation` | 固定客户端安装物的有界静态观察 | 字段、存储与可达关系；不能替代运行或像素证明 |
| `authored-corpus-observation` | 合法作者工程的输入、引用和声明 | 只说明该材料存在，不证明官方默认或项目已支持 |
| `third-party-reference-pattern` | 固定第三方 revision 的结构与实现研究 | 可解释候选设计，不能定义官方语义或项目能力 |
| `MyWallpaperX-current-evidence` | 当前源码/配置及绑定输入、App、环境的运行证据 | 代码存在不等于可见；每项结果只覆盖实际执行范围 |
| `MyWallpaperX-strategy` | 项目架构、平台和验证取舍 | 项目决定，不冒充官方内部处理或已运行结果 |

## 官方作者资料

| 内容 | 入口 |
|---|---|
| Scene 能力与作者文档 | [Designer Documentation](https://docs.wallpaperengine.io/en/)、[Scene Overview](https://docs.wallpaperengine.io/en/scene/overview.html) |
| SceneScript API | [在线 API](https://docs.wallpaperengine.io/en/scene/scenescript/reference.html)、[在线类型声明](https://docs.wallpaperengine.io/reference/lib.sceneScript.d.ts) |
| Shader | [Shader Overview](https://docs.wallpaperengine.io/en/scene/shader/overview.html)、[Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html)、[Headers](https://docs.wallpaperengine.io/en/scene/shader/headers.html) |
| Effect | [Effects Overview](https://docs.wallpaperengine.io/en/scene/effects/overview.html) |
| Particle | [Particles](https://docs.wallpaperengine.io/en/scene/particles/introduction.html) |
| Timeline | [Animation](https://docs.wallpaperengine.io/en/scene/timeline/introduction.html) |
| 属性与外部输入 | [User Properties](https://docs.wallpaperengine.io/en/scene/userproperties/overview.html)、[Audio](https://docs.wallpaperengine.io/en/scene/audiovisualizer/overview.html)、[Media](https://docs.wallpaperengine.io/en/scene/audiovisualizer/mediainformation.html) |
| 文档源码与页面发现 | [官方文档仓库](https://github.com/Wallpaper-Engine-Team/wallpaper-engine-docs)、[Sitemap](https://docs.wallpaperengine.io/sitemap.xml) |

仓库内的 [SceneScript v2.8 类型声明](reference/lib.sceneScript-v2.8.d.ts) 是固定参考输入，SHA-256 为 `d9ccc5cd1383bbb91c8a589a34874833d13798d163f2b427117023ea2bfac3f4`；它不表示在线声明仍为该版本，也不进入 App 运行时。API 更新时先比较声明差异，再沿实际 bridge 和事件消费者验证。

公开页面用于核对行为，不用页面数量、词条出现或编辑器 UI 推导播放支持。私有 schema、shader 数学、随机/物理参数或未公开默认仍需区分当前输入与实际结果。

## 平台与上游

| 资料 | 用途 |
|---|---|
| [Apple Metal](https://developer.apple.com/documentation/metal)、[CAMetalLayer](https://developer.apple.com/documentation/quartzcore/cametallayer) | 设备能力、资源、编码、提交与呈现合同 |
| [AVFoundation](https://developer.apple.com/documentation/avfoundation)、[AppKit](https://developer.apple.com/documentation/appkit) | 媒体供帧和桌面/窗口生命周期 |
| [QuickJS-NG](https://github.com/quickjs-ng/quickjs)、[本地引入说明](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/QuickJSNG/README.md) | VM 上游来源与项目引入差异；Scene host API 由本项目 bridge 决定 |
| [MirageWallpaper](https://github.com/laobamac/MirageWallpaper)、[linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) | 第三方架构与行为候选；使用时固定 revision、核源码和许可证，独立实现并运行验证 |

本地参考工程和客户端按实际存在位置发现，记录本次版本与身份；不把个人路径、旧 HEAD 或历史工具版本写成默认环境。真实 Workshop 内容只读，观察使用隔离副本。官方客户端结构清单可用 [提取工具](../../../script/extract_wallpaper_engine_client_evidence.py) 重新生成到任务目录；字段标签、changelog 或模块依赖均不能自动决定运行语义。
