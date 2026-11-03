# MyWallpaperX 技术栈与架构路线边界

<!-- document-role: stable-contract -->

> 状态：现役长期规范
>
> 最后复核：2026-09-15（Apple Silicon 平台边界）；2026-10-16（Steam 获取职责与合同路由）；2026-11-03（Scene技术落点）
>
> 适用范围：MyWallpaperX 主 App、播放进程、Web / Scene runtime、SceneScript、shader 编译、测试与开发工具

本文规定项目长期由哪些技术承担哪些职责、什么情况下允许引入新语言或进程，以及迁移不得突破的产品语义、安全和发布边界。它不是能力覆盖表，也不表示文中目标已经进入产品。

文档事实按以下入口分工：

1. [文档入口](../README.md)定义事实角色和冲突裁决，[`AGENTS.md`](../../AGENTS.md)约束实现、验证、提交和工作区安全；
2. 本文是技术栈职责、跨语言边界和依赖准入的唯一长期入口；
3. [Scene 兼容运行时架构](../scene/architecture/runtime-architecture.md)规定官方/参考证据如何转化为项目执行结构；
4. [Scene问题队列](../scene/roadmap/scene-open-breakpoint-queue.md)记录当前缺口和待验证事项；
5. [Scene 语义手册](../scene/capabilities/README.md)和专项覆盖表记录语义合同与当前能力；
6. [运行证据索引](../scene/capabilities/runtime-evidence-current.md)决定当前构建、签名和真实运行证据；
7. [Web 现役状态](../web/current-state.md)决定 Web 当前源码所有权、证据边界和待验收项。

本文使用三种状态词：

- **现役**：已经在当前生产源码路径中承担产品职责；
- **迁移目标**：方向已经确定，但当前残留尚未清零；
- **评估项**：尚未选定具体依赖或落地形态，不能据此升级能力台账。

每项技术决策还必须同时维护三条轴：**目标合同**由本文和对应长期架构规定最终职责；**当前事实**由当前源码与可复现证据说明现状；**偏差债务**登记二者差异、当前 owner、route state/fallback、纠正门和退役条件。现有代码、测试和目录只证明当前事实，不得反向定义长期技术边界；触达旧实现时必须主动纠正当前纵向结果范围内的偏差，不得为兼容已知错误所有权继续扩张旧架构。

## 1. 产品基线与迁移目标

**产品平台：macOS 26 及以上，仅支持 Apple Silicon（arm64），不承担 Intel／Rosetta 产品兼容。** 自有 App、helper、compiler/VM worker 的发行构建统一 arm64；第三方嵌套二进制必须具备可原生执行的 arm64 slice，不为减包盲目修改供应商签名。覆盖 M1 及更新目标设备，具体 Metal 能力按 device/pipeline 查询，不把最新芯片能力作为全机型前提。构建与发布配置保持同一最低系统声明，系统版本调整是独立验证事项。优化边界见[顶层设计](../scene/architecture/runtime-architecture.md)，设备与性能验收归[性能卡](../scene/roadmap/performance-convergence-card.md)。

产品基线是 Swift-first 的原生 macOS 工程：AppKit 承担 App 生命周期、主界面、窗口和桌面宿主，SwiftUI 只作为 [AppKit 迁移计划](appkit-migration.md)列出的受控残留；Swift 承担产品模型、播放生命周期与 Scene host/runtime 所有权，Metal 承担 Scene GPU 执行，Python 承担测试、矩阵和开发自动化。Scene使用QuickJS-NG执行脚本、包内shader编译工具生成MSL、同二进制daemon承载播放；具体支持范围由能力表和运行证据说明。

Scene执行链为 `authored data → prepared Program/graph/resources → typed frame update → Metal encode → unique compositor/output`。Swift管理作者identity、顺序、资源与生命周期；QuickJS-NG执行脚本语言，glslang/SPIRV-Cross处理通用shader编译，数据驱动粒子解释器推进模拟，Metal完成编码和合成。当前能力边界查[Scene能力](../scene/capabilities/README.md)，职责及源码入口查[运行架构](../scene/architecture/runtime-architecture.md)。

## 2. 长期技术职责

| 技术 | 长期职责 | 不得承担的职责 |
|---|---|---|
| Swift + AppKit | App、窗口、设置、桌面宿主、Scene 格式/typed IR、资源、属性、生命周期、host bridge、Metal 调度、诊断与 IPC 合同 | 不重复实现完整 ECMAScript VM 或通用 HLSL/GLSL 编译器；不新增 SwiftUI 产品面 |
| SwiftUI | 只维护现有迁移残留，直到 AppKit 替代完成 | 不作为新界面、宿主、设置页或模块的默认技术；不得扩大 `NSHostingView`/bridge 边界 |
| Metal + MSL | GPU 渲染、合成、effect、粒子和经性能证据选择的 compute kernel | 不按样本、路径、hash 或资产名决定产品算法 |
| C | ECMAScript VM 嵌入 API、稳定跨语言 ABI、opaque handle、buffer 与销毁合同 | 不承载第二套资源/属性/RenderGraph 模型 |
| C++ | 第三方 shader compiler、IR/reflection 转换及必要的 compiler worker 内部实现 | 不接管 App、窗口、资源生命周期、用户属性或 compositor |
| C# + .NET（限定获取服务） | 独立 SteamService 的 Steam 网络认证、结构化浏览/订阅查询与 CDN 传输；单一获取职责已生效，按 [Steam 获取合同](steam-workshop-acquisition-contract.md)维护 | 不进入播放 multiplexer，不接管 UI、用户意图、库记录、Scene 状态、graph 或 compositor；不得扩成通用后台平台 |
| JavaScript | Workshop SceneScript 内容及项目自有脚本 fixture | 不作为主 App UI、产品服务或构建系统语言 |
| Python 3.12 | 测试、fixture、benchmark、矩阵、证据聚合和开发工具 | 不进入 App 帧循环或成为发布产品的 Scene runtime 依赖 |
| Objective-C / Objective-C++ | Apple 或第三方 API 没有可维护 Swift/C 入口时的薄适配层 | 不作为新模块默认实现语言 |

新增 Rust、Vulkan/MoltenVK、Electron、另一套 UI runtime 或完整 C++ renderer 不属于默认路线。只有当前栈存在可复现且无法通过较小边界解决的缺口，并完成维护成本、发布体积、签名、公证、arm64 原生依赖和退出方案评估后，才能单独提案。MirageWallpaper 等项目只提供 clean-room 结构线索，不是复制实现或引入第二套 renderer 的依据。

## 3. 不可破坏的架构不变量

### 3.1 Swift 拥有产品状态，语言运行时拥有语言语义

以下事实必须由 Swift typed contract 统一表达，不能藏入 sample dispatch、VM 全局状态、C++ backend 或 IPC 文本协议：

- project / scene / object / layer / effect / pass / resource / target identity；
- 作者声明的 source order、effect order、pass order 和 graph dependency；
- immutable value/event snapshot 中用户属性、Timeline、pointer/audio event/value 与系统输入的提交顺序；
- resource/provider publication 中 generation、readiness、surface identity、history 与 teardown；
- topology/VM mutation transaction 中动态对象/层/effect/graph 变化、handle identity 与 mutation 顺序；
- Program ABI、reflection、资源绑定、render state、诊断和产品 fallback 状态。

作者 shader 的词法、语法、类型和代码生成由通用 compiler backend 承担；ECMAScript 语言行为由真实 VM 承担；粒子组合由 component interpreter 承担。Swift host 负责输入规范化、能力/资源边界、调用预算、结果校验和生命周期，不再把这些完整语言逐项重写成 Swift 专用 parser/compiler。

所有 Scene effect 共用实际编译、活跃接口/表示、资源依赖和执行合同。效果名、固定源码形状、pass/target数量或kernel/方向/scale组合不能成为播放许可白名单；准备 owner 已接纳的事实不由另一效果 owner 重判。拒绝须落到确实未实现的语言/操作/组件、实际接口或资源不相容、越界/预算及生命周期错误，并限于受影响单元。现有按源码形状工作的兼容补偿属于待通用化债务，应由原编译器/typed ABI边界替代，不能持续扩大模式名单或变成永久规范。

上述三类动态输入由同一个 frame commit 决定 producer 优先级、同帧/下一帧可见性和冲突，但保持不同 typed channel；resource generation 或 topology mutation 不得为复用普通 property 代码而伪装成 value-only 更新。

sample ID、layer ID、路径、hash 和资产名称可以用于装载作者声明、选择共享 component/API primitive、identity、缓存、provenance、诊断和回归定位；不能选择样本专用可见算法或固定输出。definition/material/shader path 选择对应作者数据，以及 particle/API name 选择共享 registry 项，属于正常数据驱动执行。

### 3.2 失败按风险分级

- 路径逃逸、越界 GPU range、实际在用资源或执行超过硬预算、target hazard、stale handle、生命周期破坏、VM/compiler timeout 或 OOM 等安全与状态完整性问题拒绝最小不安全单元。可选缓存满、缺失或损坏只跳过缓存并沿原读取链重建，不成为壁纸播放许可。
- shader/pipeline、optional provider、单个 effect/pass/script binding/particle system 等局部视觉问题默认 fail soft：停用失败单元，保持可安全执行的 base layer 和其他对象，并输出 typed status。
- optional 输入使用作者默认、关闭 combo 或保持原始输入；未知且未被消费的非关键 metadata 保真并告警。
- 不得伪造资源、target、history 或 binding，也不得静默切换到语义不同的算法。

### 3.3 Metal 是 macOS Scene 的唯一 GPU 主后端

Scene renderer 保持 Metal-first。引入 shader compiler 只改变作者 shader 到 MSL/metallib 的编译路径，不引入并行 Vulkan renderer，也不改变 RenderGraph、资源身份和 compositor 的所有权。

CPU 热点先用 Instruments、Metal System Trace 或同等可复现证据定位；能用 Swift 数据布局、缓存、批处理或 Metal compute 解决时，不为单点性能猜测扩大 C++ 所有权。

### 3.4 跨语言接口必须窄、typed、可销毁

跨 Swift / C / C++ 边界只传递版本化 plain data、不可变 byte buffer 或 opaque handle，并明确长度、编码、线程、取消、所有权和销毁规则；编译结果返回结构化 diagnostics、reflection、稳定错误码和显式 ABI version。

不得把编译器 AST、C++ 模板容器、裸引用、Swift 对象图或 renderer 内部对象作为长期公共 ABI。长期跨模块或可替换依赖优先使用 C ABI 或进程协议；Swift C++ interoperability 只用于同一受控模块内的有界实现。[Swift C++ interoperability](https://www.swift.org/documentation/cxx-interop/)

### 3.5 进程边界服务于故障隔离

XPC 或 bundled helper 只有在需要隔离不可信代码、编译器崩溃、权限或可重启资源时才引入。允许跨进程的消息是场景启动/停止、属性或输入批次、编译请求、缓存结果、surface/resource handle 和 diagnostics；禁止把 draw、pass、uniform、JS property access 或每帧小对象调用拆成 XPC 往返。[Apple XPC](https://developer.apple.com/documentation/xpc)

作者shader由包内固定的glslang/SPIRV-Cross工具在可终止子进程中编译。Swift准备owner持有输入、超时/输出预算、取消、产物接纳及失败归因；作者内容不能选择可执行文件或任意启动参数。

Video、Web、Scene 采用一致的控制面/播放面隔离：主 App 管用户意图、设置、唯一共享采集与异步会话控制；独立后台 AppKit 播放进程管桌面窗口、时钟、输入和渲染，不依赖主界面逐帧驱动。高频音频经后台有界单向投递，控制和目标身份变化仍由各会话 owner 串行裁决；新输出就绪后才退休旧输出。普通 XPC service 不承担桌面窗口或 WindowServer UI 所有权，窗口 renderer 使用 App 包内的独立 AppKit 入口。[Designing Daemons and Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/DesigningDaemons.html)

产品切换事务由 WallpaperManager 的唯一意图权威持有；引擎只报告身份化准备/可交接事实并执行授权的激活、回滚和退休。正常退出等待三类型精确播放进程的实际退出，父死亡兜底独立于子主循环；Web/Video窗口可见确认与Scene实际presented保持不同证据等级。迁移职责与旧分支退出见[播放生命周期设计](playback-lifecycle-transaction-design.md)。

系统锁屏与屏保仅支持Video，使用单一MyWallpaperXSystemWallpaper.appex；App唯一publisher发布视频与静帧，扩展独立用AVFoundation播放，macOS管理远程surface、认证和退出。系统目录只提供screenSaver，desktop为空，不捕获、覆盖或恢复桌面；不依赖主App存活/逐帧驱动。私有协议局限ScreenSaverSources/Native，不改系统Index、不重启服务、不编入Scene/Web。旧.saver源码及target退役，已安装旧组件保留同根别名，确认后按已知ID移除；活动socket只用于桌面暂停。主动即时锁屏尚未实现，自动屏保、锁定及预览按[专项](../development/lock-screen-screensaver-design.md)分别验证。

### 3.6 迁移 owner 必须显式路由

每个被通用执行器替代的旧 owner 必须登记以下 route state，不允许从调用顺序猜产品权威：

| route state | 约束 |
|---|---|
| `observe-only` | 新路径只观察/诊断，不发布产品输出 |
| `prefer-generic` | 新路径优先，旧 owner 只处理带 typed reason 的已验证 bounded fallback |
| `generic-only` | 新路径独占产品执行；旧实现至多为离线 oracle |
| `disable-generic` | 显式故障回滚；必须记录触发、影响面与退出条件 |

路由、fallback reason、identity 和计数必须进入 diagnostics/metrics。进入 `generic-only` 前必须有纵向正证、局部失败反例、新组合/未见 fixture、fallback 审计和原子回滚演练；旧 owner 只有在产品引用撤销并同步权威文档后才可删除。长期双执行或长期 `disable-generic` 都是未完成迁移。

## 4. Scene运行单元

```text
MyWallpaperX.app：用户意图、设置与系统采集
  → 同二进制Scene daemon：Host / Session / Surface
    → Swift：作者数据、准备产物、typed状态、资源与生命周期
    → QuickJS-NG + typed host bridge：SceneScript
    → glslang → SPIR-V → SPIRV-Cross → MSL：shader准备
    → Swift + Metal：GraphExecutor、合成与每屏呈现
```

每个Session持有同一QuickJS domain和场景clock；Surface持有本屏模拟实例、冻结帧与图形资源。准备、控制、脚本和draw调用在其实际进程内完成；IPC不承载逐draw、uniform或JS属性调用。当前接线见[运行架构](../scene/architecture/runtime-architecture.md)及[daemon合同](../scene/architecture/scene-runtime-daemon-contract.md)。

## 5. SceneScript

QuickJS-NG core和本地维护补丁位于`Systems/Script/QuickJSNG`，固定上游与许可证由其README和LICENSE记录。Swift bridge负责host API、typed mutation、事件/计时、属性优先级和销毁；JS heap与typed提交有不同的撤回边界。运行域不提供DOM、Node、文件、网络或任意native module，执行、heap、stack和任务预算由现有runtime管理。

具体API、clone、shared/localStorage、暂停及失败范围查[SceneScript能力](../scene/capabilities/scenescript-api-coverage.md)。VM可运行不表示全部作者API已实现。

## 6. Shader编译

包内`SceneShaderCompilerTools`提供glslang与SPIRV-Cross，来源和许可证由`SceneShaderCompilerLicenses.bundle`中的manifest记录。Swift负责作者预处理、source provenance、variant/资源需求、host uniform、Program ABI和生命周期；通用后端生成MSL及reflection。现有Swift frontend仍为有界fallback，按typed route决定是否使用，不能让两条路径各自发布输出。

编译与PSO准备发生在加载或实际失效边界；普通帧消费准备产物。编译失败局限到受影响的pass/effect，资源/提交身份错误仍拒绝对应无效单元。执行范围查[材质与shader能力](../scene/capabilities/render-graph-shader-coverage.md)，缓存与准备查[启动合同](../scene/architecture/scene-launch-responsiveness-contract.md)。

## 7. 能力工作入口

当前未实现与待验证事项由[问题队列](../scene/roadmap/scene-open-breakpoint-queue.md)维护；实现和验收按[Scene开发工作流](../scene/development/development-workflow.md)选择真实消费者及最近门。

## 8. 性能与效率合同

性能工作先分辨瓶颈属于 CPU、GPU、编译、资源、IPC、窗口合成还是环境；没有 profile 不进行 Swift 到 C/C++ 的性能型迁移，也不以参考项目的语言或代码行数推断瓶颈。

默认优化顺序为：减少无效工作和同步 -> 修正资源生命周期与数据布局 -> 缓存/批处理 -> Metal pass/带宽/shader 优化 -> 经证据选择局部 Metal compute 或 C/C++ kernel。

- 项目自有固定 MSL 使用 `.metal` 构建期编译；Workshop 作者 shader 才运行期编译。
- 作者 shader 在 preparation/variant 阶段完成 normalization、digest cache、reflection 和 pipeline preflight，不在 draw/pass encode 热路径首次同步编译。
- 运行期编译有稳定 cache key、并发合并、取消、超时、内存预算、失败缓存和 compiler/OS/GPU 失效条件；缓存命中不得绕过 Program ABI、resource/state 和 lifecycle 校验。
- `MTLBinaryArchive` 等持久化只有在目标系统和冷启动测量证明收益后采用，损坏或升级时安全回落。[Metal shader libraries](https://developer.apple.com/documentation/metal/shader-libraries)、[MTLBinaryArchive](https://developer.apple.com/documentation/metal/mtlbinaryarchive)

性能批次按影响面记录首帧、warm switch、CPU/GPU frame time p50/p95/p99、hitch、encoder 数、冷热编译、单/多 surface 内存、30/60/120 Hz frame pacing、暂停/睡眠/显示变化和长时间恢复。首次建立基线时记录硬件、OS、显示器、构建、App 身份、fixture/corpus 和采集工具；不凭主观体验预写阈值。[Analyzing Metal performance](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app)

## 9. 第三方依赖的开发门与发布门

新增 native runtime/compiler 进入受控开发 target 前必须完成：

- 使用场景、替代方案和退出条件；
- 官方上游、固定 revision、获取方式、项目 patch、toolchain、架构、构建参数、产物哈希和可重复构建；
- license 与已知分发义务；
- 当前开发架构、最低系统和链接方式；
- 输入大小、timeout/OOM、取消或 interrupt、失败隔离；
- CI 无私有 Workshop corpus 时仍可运行的项目 fixture；
- 不在运行时下载或执行未固定的 compiler、VM、module 或脚本依赖。

进入发行构建前再完成：

- NOTICE/third-party notices 和全部分发义务；
- binary、dependency manifest、固定源码 revision、项目 patch 与构建产物哈希的一一对应；
- 完整 corresponding-source/source archive；若使用 submodule，必须验证归档包含实际源码而非只有 gitlink；
- arm64 原生架构、最低系统和动态库解析（不要求 x86_64）；
- Developer ID、hardened runtime、notarization、stapling 与 Gatekeeper；
- sandbox/entitlement、文件和网络权限最小化；
- crash、timeout、OOM、取消、更新、损坏缓存恢复和长稳；
- release package 中的版本、校验和可追溯清单。

依赖升级重新执行其保护风险相关的合同门，不能只因包管理器解析成功就合入。

这些规则适用于 glslang、SPIRV-Cross、QuickJS-NG 及以后确有必要的 compiler/VM 依赖；采用通用语言库不等于授权引入第二套 renderer，也不改变 MirageWallpaper 的 clean-room 边界。开发门只保护第一次受控执行所需的来源、预算和故障隔离，完整 source archive、发行架构核验、签名和公证不阻塞 V0 第一张真实画面。

## 10. 工具链与语言模式

- 仓库 Python 工具链固定为 Python 3.12.x；本地入口和 CI 显式选择解释器，不依赖裸 `python3` 默认值。
- 产品 target 的实际 Swift language mode 以 Xcode project 为准。Swift 6 迁移是独立工具链工作，不与 Scene 能力扩展混交。
- 新隔离 module/target 和并发风险高的 provider/resource/compiler worker 边界可优先启用 Swift 6 strict concurrency；不得用批量 `@unchecked Sendable`、`nonisolated(unsafe)` 或关闭检查制造通过。[Swift version compatibility](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/compatibility/)
- Xcode、deployment target 或 Metal API 大版本升级独立验证源码、运行、签名发布和性能基线。

## 11. 变更本文的门

只有语言、GPU backend、VM、compiler、service、跨语言/跨进程 owner、生命周期、安全边界或现役架构路线改变时修改本文。单个 capability 完成度、样本数字、一次性能结果和实验日志进入专项覆盖表、运行证据索引或对应批次记录。

修改本文时必须同时检查 `AGENTS.md`、[文档入口](../README.md)、[Scene 专题入口](../scene/README.md)、[兼容运行时架构](../scene/architecture/runtime-architecture.md)、[语义手册](../scene/capabilities/README.md)和链接门，避免产生第二份技术栈真相。
