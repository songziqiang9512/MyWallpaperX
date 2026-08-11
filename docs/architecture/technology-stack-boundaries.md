# MyWallpaperX 技术栈与架构路线边界

> 状态：现役长期规范
>
> 最后复核：2026-08-11
>
> 适用范围：MyWallpaperX 主 App、播放进程、Web / Scene runtime、SceneScript、shader 编译、测试与开发工具

本文规定项目长期由哪些技术承担哪些职责、什么情况下才允许引入新语言或新进程，以及技术栈迁移不得突破的产品语义、性能和证据边界。它不是能力覆盖表，也不表示文中候选依赖已经进入产品。

文档事实按以下入口分工：

1. `AGENTS.md` 约束实现、验证、提交和工作区安全；
2. 本文是技术栈职责、跨语言边界和候选准入的唯一长期入口；
3. [Scene 语义手册](../scene/semantics/README.md)、专项覆盖表与[能力依赖图](../scene/semantics/capability-dependency-map.md)决定能力语义和开发顺序；
4. [运行证据索引](../scene/semantics/runtime-evidence-index.md)决定当前构建、签名和真实运行证据；
5. [Web 现役状态](../web/current-state.md)决定 Web 当前源码所有权、证据边界和待验收项；
6. 带日期的 plan、roadmap、review 和实验报告默认只描述当时批次；只有文档入口明确列为现役迁移目标或现役执行计划的文件才可指导当前顺序，且不反向覆盖本文或当前能力证据。

本文使用三种状态词，禁止混写：

- **现役**：已经在当前生产源码路径中承担产品职责；
- **迁移目标**：方向已经确定，但当前残留尚未清零；
- **候选**：只有研究或 shadow 权限，没有产品执行权，不能据此改变能力台账。

## 1. 当前基线与目标

当前产品代码是 Swift-first 的原生 macOS 工程：AppKit 承担 App 生命周期、主界面、窗口和桌面宿主，少量 SwiftUI 只作为 [0 SwiftUI 迁移计划](appkit-migration-plan-2026-05-17.md)列出的受控残留；Swift 承担产品模型、播放生命周期与 Scene 语义，Metal 承担 Scene GPU 执行，Python 承担测试、矩阵和开发自动化。当前仓库尚未把通用 JavaScript VM、第三方 shader compiler 或 Scene XPC service 接入生产链。

长期目标不是追求单一语言，也不是为技术先进性重写现有代码，而是：

- 产品语义只有一个所有者；
- 每种语言只进入其生态明显更强的职责；
- 不可信输入、编译器和易崩溃组件有明确预算与故障边界；
- 每帧热路径不被跨进程或跨语言细粒度调用切碎；
- 新技术先以无产品执行权的原型证明价值，再按公共能力迁移；
- 项目自有的静态 shader 在构建期编译，作者输入才使用受预算的运行期编译；
- 稳态帧率、首帧、内存、能耗和故障恢复分别测量，不用单个样本或平均 FPS 代替；
- 任何“性能更好”“兼容更多”的结论都由当前代码、基准和用户可见运行证据证明。

## 2. 长期技术职责

| 技术 | 长期职责 | 不得承担的职责 |
|---|---|---|
| Swift + AppKit | App、窗口、设置、桌面宿主、Scene 格式与语义、typed IR、属性、资源、生命周期、Metal 调度、诊断与 IPC 合同 | 不重复实现完整 ECMAScript VM 或通用 HLSL/GLSL 编译器；不新增 SwiftUI 产品面 |
| SwiftUI | 只维护现有迁移残留，直到 AppKit 替代完成 | 不作为新界面、宿主、设置页或模块的默认技术；不得扩大 `NSHostingView`/bridge 边界 |
| Metal + MSL | GPU 渲染、合成、effect、粒子和经性能证据选择的 compute kernel | 不决定样本、路径或资产身份对应的产品语义 |
| C | QuickJS 等嵌入 API、稳定跨语言 ABI、opaque handle、buffer 与销毁合同 | 不承载 Scene 业务规则或第二套资源/属性模型 |
| C++ | 第三方 shader compiler、IR/reflection 转换及必要的 compiler worker 内部实现 | 不接管 App、Scene 主语义、Renderer 高层调度或用户属性系统 |
| JavaScript | Workshop SceneScript 内容及项目自有脚本 fixture | 不作为主 App UI、产品服务或构建系统语言 |
| Python 3.12 | 测试、fixture、benchmark、矩阵、证据聚合和开发工具 | 不进入 App 的帧循环或成为发布产品的 Scene runtime 依赖 |
| Objective-C / Objective-C++ | 仅在 Apple 或第三方 API 无可维护的 Swift/C 入口时使用薄适配层 | 不作为新模块默认实现语言 |

新增 Rust、Vulkan/MoltenVK、Electron、另一套 UI runtime 或完整 C++ renderer 不属于默认路线。只有当前栈存在经复现且无法通过较小边界解决的缺口，并完成维护成本、发布体积、签名、公证、双架构和退出方案评估后，才能单独提案；“可能更快”或“参考项目这样做”不是准入理由。MirageWallpaper 等项目只提供 clean-room 结构线索，不能成为复制实现、重写当前已验证语义链或引入第二套 renderer 的依据。

## 3. 不可破坏的架构不变量

### 3.1 Swift 拥有产品语义

下列事实必须由 Swift typed contract 统一表达，不能藏入 VM、C++ backend、shader 文本或 IPC 消息解释器：

- project / scene / object / effect / pass / resource identity；
- 作者启用条件、source order、effect order 与 pass order；
- 用户属性、Timeline、SceneScript 和系统输入优先级；
- texture purpose、nullable slot、sampler、color / alpha 和 render state；
- provider generation、surface identity、history 与 teardown；
- Program ABI、reflection 期望、准入结果和稳定诊断；
- unsupported、missing、ambiguous 与 malformed 的 fail-closed 行为。

外部 VM 或 compiler 只能执行已由这些合同限定的工作，不能按样本 ID、layer ID、路径、hash、资产名称或参考项目身份选择可见算法。

### 3.2 Metal 是 macOS Scene 的唯一 GPU 主后端

Scene renderer 保持 Metal-first。引入 shader 转译器只改变作者 shader 到受控 MSL / metallib 的编译路径，不引入并行 Vulkan renderer，也不改变 RenderGraph、资源身份和 compositor 的所有权。

CPU 热点先用 Instruments、Metal System Trace 或同等可复现证据定位；能用 Swift 数据布局、缓存、批处理或 Metal compute 解决时，不为单点性能猜测扩大 C++ 所有权。

### 3.3 跨语言接口必须窄、typed、可销毁

跨 Swift / C / C++ 边界只传递：

- 版本化的 plain data、不可变 byte buffer 或 opaque handle；
- 明确长度、编码、所有权、线程、取消和销毁规则；
- 结构化 diagnostics、reflection 与稳定错误码；
- 显式 capability / ABI version，不以异常文本推断行为。

不得把编译器 AST、C++ 模板容器、裸引用、Swift 对象图或 renderer 内部对象直接作为长期公共 ABI。Swift 支持直接 C++ interoperability，但该能力仍在演进，因此直接互操作只可用于同一受控模块内的有界实现；长期跨模块或可替换依赖优先使用 C ABI 或进程协议。[Swift C++ interoperability](https://www.swift.org/documentation/cxx-interop/)

### 3.4 进程边界服务于故障隔离，不服务于形式分层

XPC 或 bundled helper 只有在需要隔离不可信代码、编译器崩溃、权限或可重启资源时才引入。Apple 的 XPC 服务由 `launchd` 管理并可在崩溃后重启，适合作为此类故障边界。[Apple XPC](https://developer.apple.com/documentation/xpc)

允许跨进程的消息应是场景启动/停止、属性或输入批次、编译请求、缓存结果、surface/resource handle 和 diagnostics。禁止把每个 draw、pass、uniform、JS property access 或每帧小对象调用拆成 XPC 往返。

普通 XPC service 不承担桌面窗口或 WindowServer 用户界面所有权；Apple 将 XPC service 的 UI 能力限定为无 UI，除 IOSurface 等非常有限的交换方式。[Designing Daemons and Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/DesigningDaemons.html) 因此 compiler worker 可优先评估 XPC，若 renderer 需要直接拥有桌面窗口，则保持在主 App 或使用可呈现窗口的 bundled helper application；不能仅为形式隔离把 renderer 预设为 XPC。

## 4. 目标运行单元

以下是通过准入后允许形成的目标边界，不表示现有 target 已经完成拆分：

```text
MyWallpaperX.app                              Swift + AppKit
  -> Scene execution domain（当前在 App）     Swift + Metal
       -> Scene core / typed IR               Swift
       -> RenderGraph / compositor            Swift + Metal / MSL
       -> per-surface script domain（候选）   C VM + Swift host bridge
  -> Scene renderer helper app（条件候选）    仅在窗口/崩溃/资源证据成立时
  -> Scene shader compiler worker（候选）     C/C++ 内部 + 稳定 C/XPC 合同
       -> prepared source                     只消费 Swift 已规范化输入
       -> MSL/metallib/reflection              返回后再由 Swift 校验
```

- 主 App 负责用户界面、壁纸选择、显示器与高层播放控制；当前 Scene execution domain 仍在 App 内，这一现状不能被目标图误写成已经拆分。
- Scene runtime 负责每帧脚本、动态 snapshot、Metal 编码和 compositor；脚本与渲染保持同一故障域内的批量 typed 交换，避免每帧跨 XPC。
- renderer helper 只有在能同时证明窗口所有权可行、跨进程 surface 成本可接受、崩溃恢复更可靠时才落地；普通 XPC 不作为它的默认容器。
- shader compiler worker 只负责加载期或 variant 变化时的编译、reflection、取消和缓存；它不持有 drawable、长期 GPU 资源或真实 Workshop 根目录权限。
- 只有真实崩溃、资源预算、权限或生命周期证据证明进程拆分收益时才落地 worker/helper；在此之前以同进程协议实现验证合同。

## 5. SceneScript 路线

### 5.1 候选结论

通用 SceneScript 不继续沿“在 Swift 中逐步补成完整 JavaScript 解释器”的路线。首选评估候选为 QuickJS-NG，因为其公开 C API 提供 runtime 级内存上限、栈上限与 interrupt handler，适合为不可信脚本建立显式预算；JavaScriptCore 可保留为 Apple 原生对照候选。候选身份不等于依赖已选定，也不升级任何 SceneScript 覆盖等级。[QuickJS-NG C API](https://quickjs-ng.github.io/quickjs/developer-guide/intro/)

VM 只解决 ECMAScript 执行，以下 Wallpaper Engine 语义仍由 Swift host bridge 实现：

- source / binding / owner / target IR；
- global 与 per-surface evaluation phase；
- `thisLayer`、`thisScene`、engine、input、audio、media、storage；
- Vec/Mat/Color 行为与官方 module allowlist；
- typed handle、generation、mutation buffer 与原子 snapshot；
- event、timer、effective time、pause/seek 与 teardown；
- 作者值回退、异常隔离和稳定 diagnostics。

### 5.2 VM 准入门

VM 进入生产前至少满足：

1. 项目自有 fixture 覆盖现役合同要求的语法、module、数值与 lifecycle 正反例；
2. 默认无 DOM、Node、WebWorker、文件、网络和任意 native module；
3. heap、stack、单次执行时间、每帧总预算和 job/timer 数量均有可测上限；
4. 每个 surface 的脚本执行域、handle generation、reload 与 teardown 相互隔离；
5. 无限循环、异常、OOM、stale handle、错误 module 和销毁竞态不会杀死主 App；
6. 跨 VM/Swift 调用按帧批量化，并有 CPU、内存和抖动基线；
7. 通过 [SceneScript API 覆盖表](../scene/semantics/scenescript-api-coverage.md) 和[实现层合同](../scene/semantics/scenescript-runtime-implementation-contract.md)指定的逐项门；
8. 许可证、版本固定、源码/二进制来源、双架构、签名、公证和更新流程完成审计。

Hello World、单段脚本成功或固定样本不崩溃不能授予 generic SceneScript execution owner。

## 6. Shader compiler 路线

### 6.1 现役所有权

当前 Swift authored-shader frontend / emitter 继续是已经准入能力的生产基线和迁移 oracle。它不因为某个外部 compiler 能解析更多源码而被整体替换；兼容 normalization、source provenance、annotation/combo、texture purpose、host uniform、color contract、Program ABI 和 fail-closed admission 始终由 Swift 拥有。

### 6.2 候选后端

| 路径 | 合理用途 | 当前边界 |
|---|---|---|
| 现有 Swift frontend / emitter | 已验证子集的生产基线、typed contract 与迁移 oracle | 不无限扩张为完整通用语言编译器 |
| Slang | HLSL-like corpus 的首个 shadow candidate，评估直接 MSL 与 reflection | 官方仍将 Metal target 标为 experimental，只能先 shadow compile，[Slang](https://github.com/shader-slang/slang) |
| DXC -> Metal Shader Converter | 规范化后的现代 HLSL 到 DXIL / metallib 路径 | 不自动兼容 WE 历史 dialect 或 SM3 行为；Converter 接受 DXIL 并提供 C 接口，[DXC](https://github.com/microsoft/DirectXShaderCompiler)、[Metal Shader Converter](https://developer.apple.com/metal/shader-converter/) |
| glslang -> SPIR-V -> SPIRV-Cross | GLSL 专用评估路径及 MSL/reflection | glslang 的 HLSL frontend 已弃用，不作为统一 HLSL 路线；SPIRV-Cross 优先稳定 C API，[glslang](https://github.com/KhronosGroup/glslang)、[SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross) |

这些候选用于对照实验，不要求永久全部随产品发布。评估完成后应收敛为“Swift 兼容层 + 最少必要生产 backend”，删除没有独立 corpus 价值的依赖和路由。

### 6.3 Backend 准入门

任何新 backend 先进入无产品执行权的 shadow 模式，并对项目自有 fixture 与只读隔离 corpus 记录：

- source dialect 与 normalization 分类；
- parse、type-check、stage link 和稳定 diagnostics；
- Program ABI、reflection、uniform layout、texture/sampler 和 vertex/fragment interface；
- MSL / metallib 编译与 pipeline preflight；
- 冷/热编译时间、峰值内存、缓存 key 和取消；
- arm64 / x86_64、最小 macOS、签名、公证、包体和许可证；
- GPU/compositor/next-frame 与用户可见多相位像素证据；
- malformed、unsupported、未知 state/slot/color 的负向 fail-closed 结果。

只有按公共语法/语义 capability family 完成上述门后，才允许在一个独立批次迁移该 family；同批必须撤销被替代的旧产品 owner，禁止 sample/layer/path/hash dispatch、双 owner 或失败后静默回退。外部 compiler 接受源码只证明 frontend admission，不证明运行时语义或视觉兼容。

## 7. 迁移顺序

技术栈路线服从 Scene 公共能力和当前 owner 收敛顺序：

1. **先完成当前 R4/R5**：R4 迁移所有旧产品 execution owner，R5 只删除残留；不得把 VM、compiler 或 XPC 大迁移混入未闭合的 owner 批次。
2. **冻结 typed contracts**：先稳定跨模块所需的 Program、script value、runtime input/output、diagnostics、handle 和 lifecycle 合同，不为候选依赖泄漏其内部类型。
3. **建立隔离原型**：QuickJS-NG / JavaScriptCore 对照原型和 shader backend census 都无产品执行权，不改变能力台账。
4. **一次迁移一个公共能力**：验证、撤销旧 owner、同步专项文档和运行证据、独立提交后再选下一项。
5. **再决定进程拆分**：合同和每帧交换粒度稳定后，用崩溃、预算和性能证据决定是否落地 runtime/compiler service。
6. **最后做性能型语言迁移**：只有 profiling 证明 Swift/CPU 是真实瓶颈，才选择 Metal compute 或局部 C/C++ kernel。

本文不替代 [Scene 能力依赖图](../scene/semantics/capability-dependency-map.md) 的具体开发波次，也不把 R4/R5、SceneScript、shader 或进程隔离标记为已完成。

## 8. 性能与效率合同

### 8.1 优化顺序

性能工作先分辨瓶颈属于 CPU、GPU、编译、资源、IPC、窗口合成还是环境；使用 Instruments、Metal System Trace、GPU capture、signpost 或同等可复现证据。没有 profile 不进行 Swift 到 C/C++ 的语言迁移，也不以参考项目的语言选择推断本项目瓶颈。

默认优化顺序为：减少无效工作和同步 -> 修正资源生命周期与数据布局 -> 缓存/批处理 -> Metal pass、带宽和 shader 优化 -> 经证据选择局部 Metal compute 或 C/C++ kernel。稳定帧率提升不能掩盖首帧、内存、能耗或故障恢复回退。

### 8.2 Shader 与 pipeline

- 项目自有、源码在构建时已知的固定 MSL 进入 `.metal` 源文件并由 Xcode 构建期生成 metallib；新增固定 shader 不默认使用 `makeLibrary(source:)`。
- Workshop 作者 shader 才允许运行期编译；必须在 scene preparation/variant 变化阶段完成 normalization、digest cache、编译、reflection 与 pipeline preflight，不在 draw/pass encode 热路径首次同步编译。
- 运行期编译必须有稳定 cache key、并发合并、取消、超时、内存预算、失败缓存和 compiler/OS/GPU 失效条件；缓存命中不得绕过 Program ABI、reflection、render state 和 color contract 校验。
- `MTLBinaryArchive`、Metal 4 compilation API 或其他 pipeline 持久化只有在目标系统和冷启动测量证明收益后采用；archive miss、损坏和系统升级必须安全回落到受控编译。[Metal shader libraries](https://developer.apple.com/documentation/metal/shader-libraries)、[MTLBinaryArchive](https://developer.apple.com/documentation/metal/mtlbinaryarchive)

当前以 Swift 字符串承载的固定 shader 是已知迁移债务，不因此否定其现役执行权，也不在 R4/R5 中机械搬迁。R4/R5 完成后按 effect family 独立迁移；每批先建立冷启动/首帧基线，再迁到 `.metal`、验证像素和性能、撤销旧 source owner，不能一次性重写全部 pipeline。

### 8.3 基线与门禁

性能批次至少按受影响面记录：

- 冷启动到首个有效可见帧、warm scene switch 与首次 effect/variant 命中；
- CPU/GPU frame time 的 p50/p95/p99、hitch/掉帧和 command buffer/encoder 数量；
- shader/library/pipeline 冷热编译时间，以及阻塞主线程或渲染线程的时间；
- 单 surface、多显示器下的 CPU、GPU、resident/峰值内存、纹理与 render target 预算；
- 30/60/120 Hz、暂停、遮挡、锁屏、睡眠和显示器变更下的 frame pacing 与无效工作；
- 代表负载连续运行后的内存增长、能耗、温度和恢复行为。

首次建立基线时记录硬件、OS、显示器、构建配置、App 身份、样本/fixture 和采集工具，不凭主观体验写死阈值。后续 gate 使用已批准的绝对目标或相对回退上限；单次平均 FPS、非黑画面、进程存活或固定样本通过均不能证明性能闭环。[Analyzing Metal performance](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app)

## 9. 第三方依赖与发布门

任何新增 native runtime/compiler 依赖都必须在进入产品 target 前完成：

- 使用场景、替代方案和退出条件；
- 官方上游、固定版本、校验值和可重复构建；
- license、NOTICE、third-party notices 与分发义务审查；
- arm64 / x86_64 slice、最低系统版本和运行时动态库解析；
- Developer ID 签名、hardened runtime、notarization、stapling 与 Gatekeeper；
- sandbox/entitlement、文件与网络权限最小化；
- crash、timeout、OOM、取消、更新和损坏缓存恢复；
- CI 无私有 Workshop corpus 时仍可运行的项目自有 contract fixture；
- 不在运行时下载或执行未固定的 compiler、VM、module 或脚本依赖。

依赖升级必须重新执行其保护风险相关的合同门，不能只因包管理器解析成功就合入。

## 10. 工具链与语言模式

- 仓库 Python 工具链固定为 Python 3.12.x；本地统一入口和 CI 必须显式选择兼容解释器，不能依赖 runner 的裸 `python3` 默认值。升级 minor/major 前先运行完整 Python 测试和正式 gate，并同步 CI 与本文。
- 当前产品 target 使用 Swift 5 language mode。它不是渲染性能缺陷；在 R4/R5 结束前不进行全仓 Swift 6 迁移。
- R4/R5 后优先让新隔离 module/target 和并发风险高的 provider、resource、compiler worker 边界启用 Swift 6 strict concurrency，再按模块迁移；不得用批量 `@unchecked Sendable`、`nonisolated(unsafe)` 或关闭检查制造通过。[Swift version compatibility](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/compatibility/)
- Xcode、macOS deployment target 或 Metal language/API 大版本升级是独立工具链批次，必须区分源码兼容、运行兼容、签名发布和性能基线，不能与能力迁移混交。

## 11. 变更本文的门

只有以下情形需要修改本文：

- 某种语言、GPU backend、VM、compiler 或 service 正式进入或退出长期职责；
- 跨语言/跨进程所有权、生命周期或安全边界改变；
- 候选通过准入成为生产依赖，或官方状态变化使路线不再成立；
- 当前 owner 收敛顺序或不可破坏的不变量发生经验证的架构调整。

单个 capability 的完成度、样本数字、一次性能结果和实验日志不写入本文；它们进入专项覆盖表、运行证据索引或对应批次记录。修改本文时必须同时检查 `AGENTS.md`、文档入口、相关 Scene 合同及链接门，避免产生第二份技术栈真相。
