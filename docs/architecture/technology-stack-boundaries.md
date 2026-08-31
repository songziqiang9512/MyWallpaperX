# MyWallpaperX 技术栈与架构路线边界

<!-- document-role: stable-contract -->

> 状态：现役长期规范
>
> 最后复核：2026-08-15
>
> 适用范围：MyWallpaperX 主 App、播放进程、Web / Scene runtime、SceneScript、shader 编译、测试与开发工具

本文规定项目长期由哪些技术承担哪些职责、什么情况下允许引入新语言或进程，以及迁移不得突破的产品语义、安全和发布边界。它不是能力覆盖表，也不表示文中目标已经进入产品。

文档事实按以下入口分工：

1. [文档入口](../README.md)定义事实角色和冲突裁决，[`AGENTS.md`](../../AGENTS.md)约束实现、验证、提交和工作区安全；
2. 本文是技术栈职责、跨语言边界和依赖准入的唯一长期入口；
3. [Scene 兼容运行时架构](../scene/runtime-architecture.md)规定官方/参考证据如何转化为项目执行结构；
4. [Scene 兼容执行路线](../scene/scene-compatibility-roadmap.md)决定当前迁移顺序和停止项；
5. [Scene 语义手册](../scene/semantics/README.md)和专项覆盖表记录语义合同与当前能力，[能力依赖图](../scene/semantics/capability-dependency-map.md)只记录前置关系；
6. [运行证据索引](../scene/semantics/runtime-evidence-index.md)决定当前构建、签名和真实运行证据；
7. [Web 现役状态](../web/current-state.md)决定 Web 当前源码所有权、证据边界和待验收项。

本文使用三种状态词：

- **现役**：已经在当前生产源码路径中承担产品职责；
- **迁移目标**：方向已经确定，但当前残留尚未清零；
- **评估项**：尚未选定具体依赖或落地形态，不能据此升级能力台账。

每项技术决策还必须同时维护三条轴：**目标合同**由本文和对应长期架构规定最终职责；**当前事实**由当前源码与可复现证据说明现状；**偏差债务**登记二者差异、当前 owner、route state/fallback、纠正门和退役条件。现有代码、测试和目录只证明当前事实，不得反向定义长期技术边界；触达旧实现时必须主动纠正当前纵向结果范围内的偏差，不得为兼容已知错误所有权继续扩张旧架构。

## 1. 产品基线与迁移目标

产品基线是 Swift-first 的原生 macOS 工程：AppKit 承担 App 生命周期、主界面、窗口和桌面宿主，SwiftUI 只作为 [AppKit 迁移计划](appkit-migration.md)列出的受控残留；Swift 承担产品模型、播放生命周期与 Scene host/runtime 所有权，Metal 承担 Scene GPU 执行，Python 承担测试、矩阵和开发自动化。通用 JavaScript VM、shader compiler 或隔离 service 当前是否已取得产品执行权，不在长期合同中保存移动快照；只由当前源码、对应专项覆盖表和运行证据索引裁决。

Scene 的迁移目标已经确定：保留 Swift/Metal 产品底座，把作者内容交给少数通用执行单元处理，而不是继续为已知 effect、脚本表达式或样本建立越来越多的 Swift 专用准入路径。迁移按能够让真实内容立即出画面的纵向切片推进，不先横向建完所有平台。核心目标是：

- 一个 loss-preserving Scene IR 和一套 identity/order/lifecycle 合同；
- 一个通用 shader/material compiler 路径；
- 一个通用 RenderGraph compiler 和 GraphExecutor；
- 一个真实 ECMAScript VM 与 typed host bridge；
- 一个数据驱动的粒子组件解释器；
- 对安全/状态完整性 hard fail，对局部视觉不兼容 fail soft；
- 普通合法作者内容默认获得编译/执行尝试，而不是先进入名称准入表；
- 新的合法未见内容能够因公共 primitive 自动受益；
- 稳态帧率、首帧、内存、能耗和故障恢复分别测量，不以代码行数或单样本结果判断架构优劣。

## 2. 长期技术职责

| 技术 | 长期职责 | 不得承担的职责 |
|---|---|---|
| Swift + AppKit | App、窗口、设置、桌面宿主、Scene 格式/typed IR、资源、属性、生命周期、host bridge、Metal 调度、诊断与 IPC 合同 | 不重复实现完整 ECMAScript VM 或通用 HLSL/GLSL 编译器；不新增 SwiftUI 产品面 |
| SwiftUI | 只维护现有迁移残留，直到 AppKit 替代完成 | 不作为新界面、宿主、设置页或模块的默认技术；不得扩大 `NSHostingView`/bridge 边界 |
| Metal + MSL | GPU 渲染、合成、effect、粒子和经性能证据选择的 compute kernel | 不按样本、路径、hash 或资产名决定产品算法 |
| C | ECMAScript VM 嵌入 API、稳定跨语言 ABI、opaque handle、buffer 与销毁合同 | 不承载第二套资源/属性/RenderGraph 模型 |
| C++ | 第三方 shader compiler、IR/reflection 转换及必要的 compiler worker 内部实现 | 不接管 App、窗口、资源生命周期、用户属性或 compositor |
| JavaScript | Workshop SceneScript 内容及项目自有脚本 fixture | 不作为主 App UI、产品服务或构建系统语言 |
| Python 3.12 | 测试、fixture、benchmark、矩阵、证据聚合和开发工具 | 不进入 App 帧循环或成为发布产品的 Scene runtime 依赖 |
| Objective-C / Objective-C++ | Apple 或第三方 API 没有可维护 Swift/C 入口时的薄适配层 | 不作为新模块默认实现语言 |

新增 Rust、Vulkan/MoltenVK、Electron、另一套 UI runtime 或完整 C++ renderer 不属于默认路线。只有当前栈存在可复现且无法通过较小边界解决的缺口，并完成维护成本、发布体积、签名、公证、双架构和退出方案评估后，才能单独提案。MirageWallpaper 等项目只提供 clean-room 结构线索，不是复制实现或引入第二套 renderer 的依据。

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

上述三类动态输入由同一个 frame commit 决定 producer 优先级、同帧/下一帧可见性和冲突，但保持不同 typed channel；resource generation 或 topology mutation 不得为复用普通 property 代码而伪装成 value-only 更新。

sample ID、layer ID、路径、hash 和资产名称可以用于装载作者声明、选择共享 component/API primitive、identity、缓存、provenance、诊断和回归定位；不能选择样本专用可见算法或固定输出。definition/material/shader path 选择对应作者数据，以及 particle/API name 选择共享 registry 项，属于正常数据驱动执行。

### 3.2 失败按风险分级

- 路径逃逸、越界 GPU range、资源/时间/内存预算、target hazard、stale handle、生命周期破坏、VM/compiler timeout 或 OOM 等安全与状态完整性问题 hard fail。
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

第三方 shader compiler 的首个集成形态必须是独立、可终止的 subprocess harness，用于固定输入、预算、diagnostics、reflection 和产物验证，不持有产品执行权。进入产品路径前必须明确二选一：以故障注入证明 in-process compiler 的 crash、hang、timeout、OOM、取消和损坏结果不会杀死 App 或污染 cache/Program；或使用可重启的 bundled compiler worker。完整 XPC/service 平台不阻塞开发 spike，但未完成这项选择不得让不可信作者源码在主 App 内取得产品编译权。

普通 XPC service 不承担桌面窗口或 WindowServer UI 所有权；需要呈现窗口的 renderer 保持在主 App，或在证据成立时使用 bundled helper application。[Designing Daemons and Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/DesigningDaemons.html)

### 3.6 迁移 owner 必须显式路由

每个被通用执行器替代的旧 owner 必须登记以下 route state，不允许从调用顺序猜产品权威：

| route state | 约束 |
|---|---|
| `observe-only` | 新路径只观察/诊断，不发布产品输出 |
| `prefer-generic` | 新路径优先，旧 owner 只处理带 typed reason 的已验证 bounded fallback |
| `generic-only` | 新路径独占产品执行；旧实现至多为离线 oracle |
| `disable-generic` | 显式故障回滚；必须记录触发、影响面与退出条件 |

路由、fallback reason、identity 和计数必须进入 diagnostics/metrics。进入 `generic-only` 前必须有纵向正证、局部失败反例、新组合/未见 fixture、fallback 审计和原子回滚演练；旧 owner 只有在产品引用撤销并同步权威文档后才可删除。长期双执行或长期 `disable-generic` 都是未完成迁移。

## 4. 目标运行单元

```text
MyWallpaperX.app                                  Swift + AppKit
  -> Scene execution domain                      Swift + Metal
       -> Scene IR / state / resources            Swift
       -> material + RenderGraph contracts        Swift
       -> SceneScript domain                      ECMAScript VM + Swift host bridge
       -> shader compiler                         C/C++ backend + stable bridge
       -> GraphExecutor / compositor              Swift + Metal / MSL
  -> compiler subprocess harness（开发隔离项）    无产品执行权、可终止
  -> compiler worker（条件隔离项）                in-process fault proof 不成立时采用
  -> renderer helper app（条件评估项）            仅在窗口与恢复证据成立时
```

compiler 在 scene load 或 variant 变化时工作，不持有 drawable、长期 GPU 资源或真实 Workshop 根目录权限。开发 harness 先稳定输入/输出协议；产品采用 in-process backend 还是 worker，按上一节的故障证明门决定。脚本按 surface 隔离，以批量 snapshot/mutation 与 Swift 交换，避免细粒度跨语言调用。renderer 的进程拆分晚于协议和每帧交换粒度稳定，不为形式分层提前引入。

## 5. SceneScript 路线

通用 SceneScript 不继续沿“在 Swift 中逐步补成完整 JavaScript 解释器”的路线。首选上游 QuickJS-NG，因为其 C API 可控制 runtime heap、stack 和 interrupt budget，适合先闭合最小 per-scene VM + typed mutation 纵向链。[QuickJS-NG C API](https://quickjs-ng.github.io/quickjs/developer-guide/intro/)

JavaScriptCore 只保留为系统框架对照；除非能够证明项目所需的执行时间、内存、可靠终止和 teardown 合同，否则不作为首选实现。固定 Wallpaper Engine 2.8.42 Windows 客户端的静态观察识别到 V8 runtime，这只支持“应使用真实 ECMAScript VM”的方向，不是官方公开或跨版本保证，也不代表项目应承担完整 V8 的体积和构建成本。

VM 执行 ECMAScript；Swift host bridge 负责 source/binding/owner/target IR、global/per-surface phase、官方 host API/module allowlist、typed handle/generation、mutation buffer、event/timer/effective time、pause/seek、作者值 fallback 和 teardown。

VM 首次进入受控开发产品路径前至少满足：

1. 项目 fixture 覆盖代表语法、module、数值、host API 和 lifecycle 正反例；
2. 默认无 DOM、Node、WebWorker、文件、网络和任意 native module；
3. heap、stack、单次执行、每帧总预算和 job/timer 数量有可测上限；
4. surface domain、handle generation、reload 和 teardown 相互隔离；
5. 无限循环、异常、OOM、stale handle 和销毁竞态不会杀死主 App；
6. 跨 VM/Swift 调用按帧批量化，并记录最小 CPU/内存基线；
7. 上游、固定版本、许可证和可重复构建已登记。

不要求完整 API、双架构、签名或公证后才开始开发验证；这些属于 release gate。未实现 host API 必须可诊断，并只回退受影响 binding/script domain。Hello World 或单个样本成功只证明集成链可运行，不证明 SceneScript 完整兼容。

## 6. Shader compiler 路线

### 6.1 所有权转向

迁移期间仍保留的 Swift authored-shader frontend/emitter 只可作为已验证子集的 bounded fallback 或差分 oracle，不是永久扩张方向；它是否仍持有产品 route 只查专项覆盖表。Swift 继续拥有 source provenance、author metadata/variant preparation、resource identity、host uniform、Program ABI、render state 校验、预算和 lifecycle；通用 compiler backend 负责语言解析、类型、stage link、代码生成和 reflection。

### 6.2 首选后端与对照

| 路径 | 合理用途 | 边界 |
|---|---|---|
| 迁移期 Swift frontend/emitter | 已验证子集、差分 oracle、有界 fallback | 不再扩张为完整通用语言编译器；产品 route 以专项表为准 |
| Slang | HLSL-like corpus、MSL 与 reflection 评估 | Metal target 状态和 dialect 兼容需实测，[Slang](https://github.com/shader-slang/slang) |
| DXC -> Metal Shader Converter | 现代 HLSL 到 DXIL/metallib 路径 | 不自动兼容历史 dialect 或 SM3 行为，[DXC](https://github.com/microsoft/DirectXShaderCompiler)、[Metal Shader Converter](https://developer.apple.com/metal/shader-converter/) |
| **glslang -> SPIR-V -> SPIRV-Cross** | **选定 backend：WE GLSL-like normalization 后生成 MSL/reflection** | 从独立上游固定版本集成；不得复制 Mirage vendor、bridge 或 shader rewrite，[glslang](https://github.com/KhronosGroup/glslang)、[SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross) |

第一轮只建设首选后端。只有真实 corpus spike 证明 dialect、MSL 或 runtime 约束无法以小型 normalization 解决，才带着失败分类评估 Slang 或 DXC；不并行建设三套 compiler。最终保持“Swift compatibility/host layer + 一个 production backend”。

### 6.3 取得产品执行权的门

backend 先在独立 subprocess harness 中通过项目 fixture 和只读隔离 corpus 的 source/dialect 分类、parse/type/stage link、reflection/ABI、MSL/library/pipeline preflight以及输入大小/编译时间预算。完成 in-process fault proof 或 bundled worker 的显式选择后，才可在受控 route state 下取得 ordinary representative content 的开发产品执行权；不要求先为所有未知 state/slot/color 建立逐项 exact admission，也不等待完整发行审计。

产品验证必须证明：

- 至少一个真实 ordinary effect 实际执行；checkpoint 再加入未见内容或新组合，证明不依赖名称视觉特判；
- 编译结果经 Swift 校验后进入统一 Program 和 GraphExecutor；
- compile/pipeline 失败只降级相关 pass/effect，安全与状态错误仍 hard fail；
- 代表隔离样本具备 GPU、publication、terminal compositor 和 next-frame 证据；
- fallback 有诊断和显式路由，不是静默双 owner；
- 稳定替代后再撤销对应 Swift 专用产品 owner。

外部 compiler 接受源码只证明 frontend 能力，不证明运行时语义或视觉等价。

## 7. 迁移顺序

具体纵向切片、快速回滚和退役条件以[Scene 兼容执行路线](../scene/scene-compatibility-roadmap.md)为准：

1. V0 普通 authored material/shader 从声明到 compositor；
2. V1 多 pass、FBO、command、history 和 cross-layer graph；
3. V2 真实 SceneScript VM 与 typed host bridge；
4. V3 particle component interpreter。

V4 不是排在 V3 之后的阶段，而是贯穿 V0–V3 的动态输入、provider、text、audio、media 和交互横切轨；每项输入各自闭合 typed producer、frame-commit channel、consumer、可见/事件结果、teardown 和 owner 退役。V5 也不是单体平台阶段；Puppet、2D lighting/HDR、3D、RGB、offline、color/multi-display/device recovery 与 performance/release 是独立 epics，每项单独定义输入、输出、门、回滚和退役条件，不互相等待或外推完成。

V0 必须先取得真实可见结果；V1–V3 的独立研究和 fixture 可以并行，但不以完成整个子系统阻塞上一条纵向链。迁移按三层分别声明：`slice-visible` 证明一个真实纵向结果；`owner-migration` 再证明 `generic-only`、fallback 审计、回滚演练和旧 owner 撤权；`parity-release` 最后证明 bounded 官方黑盒容差、性能/长稳、依赖/许可证与签名发布。受控 route state、差分 oracle 和迁移期 fallback 允许存在，但前一层不能冒充后一层，发行门也不能倒灌阻塞首个普通 effect 或 VM property 结果。

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
- arm64/x86_64、最低系统和动态库解析；
- Developer ID、hardened runtime、notarization、stapling 与 Gatekeeper；
- sandbox/entitlement、文件和网络权限最小化；
- crash、timeout、OOM、取消、更新、损坏缓存恢复和长稳；
- release package 中的版本、校验和可追溯清单。

依赖升级重新执行其保护风险相关的合同门，不能只因包管理器解析成功就合入。

这些规则适用于 glslang、SPIRV-Cross、QuickJS-NG 及以后确有必要的 compiler/VM 依赖；采用通用语言库不等于授权引入第二套 renderer，也不改变 MirageWallpaper 的 clean-room 边界。开发门只保护第一次受控执行所需的来源、预算和故障隔离，完整 source archive、双架构、签名和公证不阻塞 V0 第一张真实画面。

## 10. 工具链与语言模式

- 仓库 Python 工具链固定为 Python 3.12.x；本地入口和 CI 显式选择解释器，不依赖裸 `python3` 默认值。
- 产品 target 的实际 Swift language mode 以 Xcode project 为准。Swift 6 迁移是独立工具链工作，不与 Scene 能力扩展混交。
- 新隔离 module/target 和并发风险高的 provider/resource/compiler worker 边界可优先启用 Swift 6 strict concurrency；不得用批量 `@unchecked Sendable`、`nonisolated(unsafe)` 或关闭检查制造通过。[Swift version compatibility](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/compatibility/)
- Xcode、deployment target 或 Metal API 大版本升级独立验证源码、运行、签名发布和性能基线。

## 11. 变更本文的门

只有语言、GPU backend、VM、compiler、service、跨语言/跨进程 owner、生命周期、安全边界或现役架构路线改变时修改本文。单个 capability 完成度、样本数字、一次性能结果和实验日志进入专项覆盖表、运行证据索引或对应批次记录。

修改本文时必须同时检查 `AGENTS.md`、[文档入口](../README.md)、[Scene 专题入口](../scene/README.md)、[兼容运行时架构](../scene/runtime-architecture.md)、[语义手册](../scene/semantics/README.md)和链接门，避免产生第二份技术栈真相。
