# MirageWallpaper Scene 显示链路静态研究

> 状态：现役第三方 clean-room **结构参考**；不是 Wallpaper Engine 官方语义，也不表示 MyWallpaperX 已支持相同能力
>
> 首次整理：2026-08-08
>
> 基础静态审查快照：`laobamac/MirageWallpaper`，revision `8893b25b3fb4abdd63d72e9fe31bdd59e765208a`（tag `v1.0.3`，2026-08-07）；正文既有行号只属于该快照
>
> 全文历史固定复核快照（2026-09-27 粒子/光线局部复核另见 §11.5，固定到 `f5049582e3e334cac6b177bbbccb39736190750a`）：本地 checkout revision `443777e29a8046615db6275f80ff816a4bad444b`。2026-08-15 只读远端查询显示 `origin/main` 已前进到 `899e6820a36d7e7b243b603c299f8a0b4c181775`；因此本文不代表 Mirage 最新实现，也不得把移动的远端 HEAD 静默套用到本文结论
>
> 运行边界：上述 revision 均只做静态源码审查；未构建、未运行、未与 Wallpaper Engine 做像素或时序 golden 对照
>
> 来源分类：`third-party-reference-pattern`（独立 GPL-3.0 开源播放器的静态结构参考）

## 1. 目的、边界与使用方法

本文逐项记录 MirageWallpaper 如何把 Wallpaper Engine 风格 Scene 数据送到最终显示，重点覆盖纹理、合成、effect、FBO、材质、相机、鼠标、脚本、文字、视频、粒子、光照和最终呈现。它用于：

1. 给 MyWallpaperX 的 parse-to-composition 链路提供可审计的结构参照；
2. 把容易在层间丢失的显示合同列成检查清单；
3. 区分 Mirage 中值得借鉴的系统边界、其独立实现选择以及仍有风险的缺口；
4. 为后续修复建立调查入口，不把第三方行为直接写成官方规范。

Mirage 不是 Wallpaper Engine 官方实现。它的 README 明确说明项目仍处早期，复杂作品可能存在 effect、脚本或材质差异。因此，本文只把它当作第三方 clean-room 结构交叉检查：

- 本文只提炼架构、状态传播、资源身份、时序和失败边界，不复制源码、shader、纹理、JSON payload、二进制或算法表达；
- Mirage 与本地官方资料或真实样本冲突时，按本资料库的证据优先级处理，不能修改官方合同去迎合 Mirage；
- 本文不更新 [覆盖台账](coverage-ledger.md) 或 [运行证据索引](./runtime-evidence-current.md)，也不证明 MyWallpaperX 当前能力等级；
- 本轮没有构建或运行 Mirage，也没有以其输出充当像素或时序 golden。所有结论均为固定 revision 的静态源码审查；“疑似缺口”需后续黑盒或样本验证。

下文源码路径均以 `<repo>/Reference Project/MirageWallpaper/` 为根。正文既有行号默认只对应基础 revision `8893b25b3fb4abdd63d72e9fe31bdd59e765208a`；增量复核表中的结论分别绑定其行内 revision、path 与 symbol，不能跨 revision 复用行号。

### 1.1 增量复核与按需使用合同

基础快照保留一份完整、可复核的结构研究；后续不能为了追随移动的 checkout 或远端 HEAD 而机械替换 revision、复用旧行号或把旧结论改称“当前 Mirage 行为”。MyWallpaperX 实现默认先使用官方公开合同、项目 corpus 和现有固定证据；只有这些材料不足以解释 producer-to-consumer 结构或需要核对第三方架构差异时，才为相关问题另选固定 revision，读取直接相关的 producer、typed state/identity、consumer、frame order/lifecycle 与 failure path，并在下表记录模块、结构结论和 divergence。引用以 `revision + path + symbol` 为主，行号只作该 revision 内的辅助定位。

| 日期 / family | 固定 revision | 实际读取模块 / symbol | 结构结论 | divergence 与项目边界 |
|---|---|---|---|---|
| 2026-08-08 全链基础审查 | `8893b25b3fb4abdd63d72e9fe31bdd59e765208a` | 本文 §3 所列 texture/compiler/graph/pass/runtime/particle/surface 模块 | 建立本文 parse-to-present 基础检查表 | 只证明该第三方快照存在静态链；其缺口见 §13，不构成官方或 MyWallpaperX 能力事实 |
| 2026-08-13 optional sampler / active default | `da4fa7b3ee33e9e94c59307f47098aa521f21aa6` | `ShaderAnnotations.cpp`、`SceneCompiler.cpp` 的 sampler annotation、material presence、preprocess 与 default 回填 | author presence 先决定 combo，prepared active slot 才消费 default | 只支持职责顺序；default/optional 的作者合同仍以官方 Shader Variables 为准，不复制 resolver 或 shader 实现 |
| 2026-08-13 pointer / SceneScript click chain | `da4fa7b3ee33e9e94c59307f47098aa521f21aa6` | `MacDesktopHost.mm`、`WallpaperApp.cpp`、`WallpaperEngineRuntime.cpp`、`ScriptRuntime.cpp`、`World.cpp` 的 input、tick、hit/capture、mutation 与 graph-dirty symbols | host polling → edge retention → frame input → hit/capture → cursor callbacks → update → visibility/topology commit → graph rebuild → draw | atomic bit latch不保次数/顺序，world AABB hit-test过宽，solid gate/propagation与local coordinates未闭合，`destroyLayer`也不等同官方语义；只借职责与时序，不能当点击 golden |
| 2026-08-13 bounded Pulse material/composition chain | `443777e29a8046615db6275f80ff816a4bad444b` | `SceneCompiler.cpp` 的 image-effect/material/target编译，`LayerEffectStack.cpp::ResolveEffect`，`SceneRenderPlanner.cpp::ToGraphPass`，`MaterialPass.cpp::CustomShaderPass`，`SceneUniformBinder.cpp::FrameBegin/UpdateUniforms`，`WallpaperEngineRuntime.cpp::on(RenderDraw)`，`PresentPass.cpp::FinPass` | authored material/slot/uniform → layer-local ordered effect/ping-pong → graph texture read/write/version → reflected shader resources/uniforms → offscreen RGBA target → final layer state → present | 只交叉支持资源身份、pass顺序、uniform更新、RGBA target与最终present的职责链；Mirage固定使用RGBA8 UNorm并有自己的blend/load-op/编译兼容选择，不证明Pulse scalar公式、alpha边界、Metal数值或官方像素/时序，本项目仍以官方/合法stock与项目自有GPU fixture为准 |
| 2026-08-13 本地固定 checkout 观察 | `443777e29a8046615db6275f80ff816a4bad444b` | 只确认 §3 关键入口仍存在；相对 `da4fa7b`，粒子 geometry/subdivision 与 large-mesh upload/first-frame handling 已变化 | 为后续 texture/effect/particle/dynamic family 提供固定候选 | 未逐 family 重证，不能把基础或 `da4fa7b` 的全部结论改署到该 revision；2026-08-15 远端 `main` 已是 `899e6820a36d7e7b243b603c299f8a0b4c181775`，本文未审查该远端 revision，也未构建或运行 `443777e` |
| 2026-10-01 parse 四阶段分层 | `da4fa7b3ee33e9e94c59307f47098aa521f21aa6` | `CompilePipeline.cppm:23-26/53-55/85-90/154-183` 四阶段签名；`SceneCompiler.cpp:5608/5617-5624/6041-6085/6087+` 实现 | parse 分 ExpandObjects（纯 JSON+VFS）→BuildContext（含 `_rt_default`/`_rt_MipMappedFrameBuffer` 两默认 RT 产地）→ProcessObjects→FinalizeScene 四阶段；kind 掩码仅 6 位（All=0x3F）、Shape 复用 Image 位、Camera 不受掩码 | 仅第三方结构参考，不入产品合同（`third-party-reference-pattern`） |
| 2026-10-01 shader 注释前端三层 | `da4fa7b3ee33e9e94c59307f47098aa521f21aa6` | `ShaderLexer.cppm`（手写字符级扫描原语：Cursor Skip*/Match*/Read* + LineWalker 块注释掩蔽，:26-28/:190）；`ShaderAnnotations.cpp`（逐行收集 // [COMBO] 与 uniform NAME; // {json} 进 WPShaderInfo，遇 void main( 即止 :224、无条件收集不做 #if 死枝剔除 :12-16、g_Texture 槽位上限 13 拒越界 :33/:167-172）；`MaterialShaderCompiler.cpp` 在其上行级 decl 扫描/include 展开/prologue 合成（:32-93/:1783-1787/:1816-1817/:132-149）；schema 本体在 `UniformSpec.cppm`（WPUniformTex/WPUniformVar/WPCombo，含 corpus 观察未消费字段 hidden/nonremovable/group/linked/format/formatcombo/direction/conversion/order 等） | shader 注释前端三层职责分层：lexer 扫描原语 → 逐行注释收集 → compiler 行扫描/include/prologue 合成 | 仅落本 Mirage 参考文档、不进 forensics、不入产品合同；`MaterialShaderCompiler.cpp:854` 指向 `WPShaderParser_Pegtl.cpp` 为过期指针（该文件不在钉定树）；Mirage 未实现官方已证 // [PASS]（token shadow）shader source metadata 识别，该缺口以官方 client-runtime-static-forensics §5.1 为准 |
| 2026-10-01 pause/power 职责分层 | `da4fa7b3ee33e9e94c59307f47098aa521f21aa6` | `ControlChannel.cpp` pause/resume/play/power 分发（:79-102@da4fa7b3，含 :84-88 “app 是 occlusion/lock/sleep/battery/thermal 唯一裁决者、渲染进程窗口故意从不上报 occluded”自述）；`RendererController.swift` setPower/powerCommand/`MiragePowerState` 三态（:22-32/:2491-2518@da4fa7b3） | app 侧唯一裁决五类策略、渲染进程只服从 run/throttle/pause 三态终态 | 仅支持职责分层对照（对照我方 runtime-systems-reference.md:55 reason-set interruption coordinator）；pause/power wire 语义无官方 parity 主张，不更新覆盖台账与运行证据、不改我方既有断言 |

Mirage 始终只是 `third-party-reference-pattern` 结构参考，不是每个纹理、graph、effect、粒子或 SceneScript 批次的强制前置，也不决定 MyWallpaperX 的产品 admission。官方合同优先；冲突时记录偏差，并按本项目的安全 hard-fail、局部视觉 fail-soft 策略处理 unknown，不复制源码、shader、纹理、payload、常量组合、表达式、算法或测试资产。

## 2. 总体结论

Mirage 的高价值不在某个单独 effect，而在于它把显示问题组织成一条连续链路：

```text
project / scene / pkg / tex
  -> 对象、材质、纹理和动态 binding
  -> Scene tree（保留声明顺序与父子变换）
  -> 每层 source draw
  -> effect-local camera + ping-pong / named FBO
  -> RenderGraph 资源版本与依赖
  -> 材质 pass（shader variant + slot + sampler + render state）
  -> layer final composite
  -> reflection / global post process
  -> screen RT
  -> swapchain copy 或 linear blit
```

它与 MyWallpaperX 当前排查最相关的结构原则是：

- 纹理不是一只 `MTLTexture`/`VkImage` 就结束；物理尺寸、映射尺寸、UV、过滤、寻址、mip、颜色/alpha 用途和资源代际必须沿每个 slot 继续传播；
- layer source extent、effect working extent、screen-bound extent 和实际设备分配 extent 是不同概念；
- effect 是有序 pass/FBO/command 图，不是“识别到 effect 名后调用一个滤镜”；
- 中间 pass 与最终 composite 使用不同 render state；最终 pass 要恢复作者的 blend/depth/cull、几何、相机和 alpha 来源；
- 鼠标不是只有一个归一化坐标：全局屏幕、SceneScript screen/world/local、camera parallax 和节点 hit-test 是不同消费者；
- 动态系统必须在同一帧的正确位置提交，再决定是否重建图、刷新纹理或只更新 uniform。

同时，Mirage 不能作为数值或像素真值。其自身存在硬编码 texel/bloom 基准、受限 hit-test、未实现 shadow atlas、8-bit 后处理和若干疑似 sampler 接线问题。本文会把这些风险与可借鉴路径分开记录。

## 3. 源码模块与调查入口

| 主题 | Mirage 入口 | 本文用途 |
|---|---|---|
| 帧控制与 live update | `AppRuntime/Controller/WallpaperEngineRuntime.cpp` | 帧顺序、鼠标、音频、属性、graph rebuild |
| `sr.timer` 帧定时器 | `AppRuntime/Timing/ClockModule.cppm` | 纯 partition re-export（`:thread_timer` 独占线程定时器 + `:frame_timer` 帧时钟），无装配逻辑 |
| uniform 与相机输入 | `AppRuntime/Controller/SceneUniformBinder.cpp` | 矩阵、texel、resolution、pointer、parallax、light、audio |
| SceneScript | `AppRuntime/Scripting/ScriptRuntime.cpp` | 输入坐标、hit-test、事件、动态拓扑、watchdog |
| Scene 编译 | `Wallpaper/Compiler/CompilePipeline.cppm`（阶段入口）、`Wallpaper/Compiler/SceneCompiler.cpp`（实现） | ExpandObjects→BuildContext→ProcessObjects→FinalizeScene 四阶段、对象顺序、材质、effect、FBO、相机、文字、Bloom |
| TEX 解码 | `Wallpaper/Compiler/TextureDecoder.cpp` | 物理/映射尺寸、flags、sprite、mip、sampler |
| 材质与 pass schema | `Wallpaper/Schema/MaterialSpec.cpp`、`ImageLayerSpec.cpp` | 空槽、override、bind、target、command、compose |
| effect 栈 | `Domain/Scene/LayerEffectStack.cpp` | ping-pong、最后一跳、状态恢复 |
| Scene/相机 | `Domain/Scene/World.cpp`、`CameraRig.cpp` | 层级变换、camera path、reflection、动态状态 |
| RenderGraph | `Frame/Graph/FrameGraph.cpp`、`Gpu/Pipeline/SceneRenderPlanner.cpp` | 资源版本、读写依赖、clear/preserve、linked layer |
| GPU pass | `Gpu/Pipeline/MaterialPass.cpp`、`PipelineShared.cppm` | descriptor、blend/depth/cull、load op、draw order |
| 纹理缓存 | `Gpu/Vulkan/TextureCache.cpp` | sampler、mip、视频更新、资源复用 |
| RT 尺寸与相机 fill | `Gpu/Pipeline/VulkanFrameEngine.cpp` | logical/physical extent、screen scaling、present scope |
| 最终呈现 | `Gpu/Pipeline/PresentPass.cpp` | screen RT 到 swapchain 的 copy/blit |
| macOS surface/input | `Host/macOS/MacDesktopHost.mm` | Retina drawable、多屏坐标、桌面层级、输入轮询 |

固定 checkout `443777e` 的 `SceneRenderer/Tests` 可见 5 个项目自有 regression test translation units（合计 1,982 行），但没有覆盖本文整条 parse-to-present 主链的视觉 golden。本轮也没有构建或运行这些测试。因此后文“已实现”只表示相应固定 revision 中存在一条静态源码路径，不表示测试已通过，更不表示它已通过 Wallpaper Engine 对照验证。

## 4. 一帧的真实执行顺序

`WallpaperEngineRuntime.cpp:1111-1234` 给出了最有价值的主时序。每帧按以下顺序推进：

1. 开始 frame timer 和 shader updater frame；
2. 读取归一化鼠标位置，更新 Scene pointer 和 shader pointer；
3. 组装 SceneScript 输入：frame time、runtime、canvas/screen、时刻、鼠标按钮和音频；
4. 合并系统与外部音频，超过 250 ms 未刷新时归零，避免画面冻结在旧频谱；
5. 执行 node field animations；
6. 执行 SceneScript，包括鼠标回调和 `update()`；
7. 提交脚本产生的动态拓扑与可见性变化；
8. 更新 camera paths、material shader animations 和 transform updaters；
9. 如 topology/visibility/combo 改变了图，重建 RenderGraph；
10. 发射粒子并刷新已准备 mesh/material 的脏事件；
11. 在绘制前推进视频纹理；
12. 在脚本生成新字形后、绘制前上传 font atlas dirty rect；
13. 绘制 RenderGraph；
14. 最后推进 Scene elapsed time，并结束 shader frame。

这一顺序解决的是“本帧写入何时可见”问题。脚本写 transform 后，本帧 draw 才计算矩阵；脚本写文字后，本帧先生成 glyph、上传 atlas、调整 mesh/RT，再 draw；动态 visibility 先提交再决定 graph 是否重建。把这些系统拆成互不知情的异步旁路，很容易造成晚一帧、旧尺寸 RT、残影或 effect 仍引用旧资源。

帧时钟排程语义（`third-party-reference-pattern`，固定 revision `da4fa7b3ee33e9e94c59307f47098aa521f21aa6`，属 Mirage 参照实现结构而非官方 2.8.42 取证）：产品唯一消费者是 WallpaperEngineRuntime 渲染控制器内嵌的 FrameTimer（`WallpaperEngineRuntime.cpp:25/:1040`@da4fa7b3）。SetInterval 经原子 revision 递增加 notify 即刻生效；回调被拒（上一帧仍在飞）时按短间隔重探测而不是跳过整格；正常触发后 deadline 追赶至超过 now 且不补帧——与官方 2.8.42“到期每帧至多执行一次、不追补积压周期”及我方[运行时系统语义](runtime-systems-reference.md)的不补帧合同同向（runtime-systems-reference.md:352/:485，可交叉引用）；Stop 断言不得在定时器线程内调用（`WorkerTimer.cpp:20-88`@da4fa7b3）。

### 4.1 live property 的分流

`WallpaperEngineRuntime.cpp:1326-1381` 没有把所有用户属性变化都粗暴重载场景，而是按影响层级处理：

- shader uniform、clear color、image alpha/color、camera 参数可走动态更新；
- material texture 尝试刷新已准备 pass 的绑定；若 slot 数、依赖类别或资源身份发生结构变化才重建图；
- combo、visibility、topology 等改变执行形状的状态触发 graph rebuild；
- text/point-size 变化既可能更换 atlas，也会改变 mesh 与 layer RT 尺寸，所以还要消费 mesh/material dirty event，防止放大文字被旧 RT 裁切或残留旧字形。

可借鉴点是给动态更新分级：`uniform-only`、`resource-rebind`、`geometry/extent`、`graph-topology`，而不是只区分“需要/不需要刷新”。

## 5. 纹理从文件到 shader slot 的链路

### 5.1 物理尺寸、映射尺寸与 UV

`TextureDecoder.cpp:162-217` 同时保存 TEX 的底层尺寸、映射尺寸、mip 和 flags。`SceneCompiler.cpp:1946-2005` 为每个材质 slot 形成四分量 resolution：底层物理尺寸与有效映射尺寸不会在上传后丢失。`SceneCompiler.cpp:315-322` 再用映射/物理比例缩放 layer UV，避免 power-of-two padding 或容器边缘进入可见采样。

这条路径区分了：

- `physical size`：GPU 纹理或 mip 0 实际像素范围；
- `mapped size`：作者图像真实有效区域；
- `object/effect extent`：该层或 effect 的工作坐标范围；
- `screen/RT physical extent`：当前输出或受设备上限约束后的分配大小。

这些量只有在数值恰好相同时才能合并。Mirage 对普通导入纹理保留物理/映射四元组；对动态 render target，uniform 更新使用实际 physical extent（`SceneUniformBinder.cpp:206-223`）。

### 5.2 sampler 与 mip

TEX flags 决定 nearest/linear 与 clamp/repeat（`TextureDecoder.cpp:165-170`）。这些状态进入 `SceneTexture`、材质 slot、`TextureKey` 和最终 Vulkan sampler；effect source 为 point sampling 时，Mirage 还把 nearest 传播到整条 ping-pong RT（`SceneCompiler.cpp:2946-2955,3302-3321`）。

这很重要：即使 source 已正确解析 nearest/repeat，如果 offscreen 中间纹理或 final composite 又换回固定 linear-clamp，像素画会变糊、滚动纹理会拉边、mip 选择也会改变。正确合同应当按 slot/target 保留 sampler，而不是只在最初上传时保存。

### 5.3 sprite、video 与动态纹理

- sprite 不只切换 texture index；compiler 保留 frame 几何、轴、rate 与 frame count，binder 每帧更新当前 active image slot；
- 视频纹理使用稳定 RGBA8 目标，按播放状态处理 seek/pause/rate/loop，按 PTS 追帧并丢弃已经过时的中间帧，一帧最多推进 12 次、只上传最后实际可显示的帧；YUV 转 RGBA 使用解码帧声明的 color space 与 range（`TextureCache.cpp:956-1243`）；
- font atlas 使用 per-face atlas 与 dirty rect 增量上传，脚本新增 glyph 可在同一帧显示（`SceneCompiler.cpp:4588-4600` 与 runtime frame order）。

这些动态 provider 最终仍回到同一材质 slot/资源代际链路；它们不应建立另一套绕开材质、sampler 和 graph identity 的私有绘制通道。

材质纹理名以 `_rt_` 开头时（IsSpecTex，`SemanticTextures.cppm:210`@da4fa7b3），编译期经 `ParseSpecTexName` 单点准入分派（`SceneCompiler.cpp:1633-1675`@da4fa7b3；`third-party-reference-pattern`，固定 revision `da4fa7b3ee33e9e94c59307f47098aa521f21aa6`），端点三态加兜底：

- `_rt_FullFrameBuffer` → 改写为 `_rt_default`；材质为 genericimage2 且无 BLENDMODE combo 时清空；
- `imageLayerComposite_<id>` → 改写 `_rt_link_<id>`；
- `_rt_MipMappedFrameBuffer*`、`_rt_bloom_mip*`、`_rt_effect_pingpong*` → 原样保留；
- `_rt_Reflection*` → 归一化为 `_rt_Reflection` 并触发 EnablePlanarReflection；
- `_rt_HalfCompoBuffer*`、`_rt_QuarterCompoBuffer*`、`_rt_FullCompoBuffer*`、`_rt_EightBuffer*` → 原样保留；
- volumetrics、QuarterForceRG、`_rt_Bloom`、QuarterFrameBuffer、EighthFrameBuffer、shadowAtlas 前缀 → 清空；
- 已注册 effect-local FBO（如 `_rt__coc_<addr>`）→ 保留；
- 其余未知 `_rt_` 名 → `rstd_warn("ignoring unsupported special tex")` 后清空。

WE 来源 `_rt_` 前缀全集恰 14 个（`SemanticTextures.cppm:26-40`@da4fa7b3；:25 “来自 Wallpaper Engine 内容”注释与 :42-48 “sr 自造”注释构成二分类）：imageLayerComposite_、FullCompoBuffer、HalfCompoBuffer、QuarterCompoBuffer、EightBuffer、FullFrameBuffer、MipMappedFrameBuffer、shadowAtlas、Reflection、volumetrics、QuarterForceRG、Bloom、QuarterFrameBuffer、EighthFrameBuffer；sr 自造名为 effect_pingpong_a/b、bloom_mip、`_rt_default`、`_rt_link_`。命名不对称事实：常量标识符作 EightCompoBuffer，字符串实为 `_rt_EightBuffer`（`SemanticTextures.cppm:30`@da4fa7b3），与 `_rt_QuarterCompoBuffer`（:29）不对称。CompoBuffer 四前缀在该钉定 revision 准入保留但无引擎级专门生产者，闭合靠 authored effect fbos 经通用 effect FBO 注册路径（`SceneCompiler.cpp:3355-3410/4953-4968`@da4fa7b3）与 `ImageLayerSpec.cpp:202-208` compose 特例；我方官方 2.8.42 审计（[Windows 客户端取证记录](../../history/scene/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md):658-663）可作官方资产自带 fbos 声明的静态取证。各前缀的官方行为规格须经[官方客户端行为研究工作流](official-client-behavior-research-workflow.md)定案，Mirage 分派表与其 corpus 注释仅作对照材料、不得直接升为官方语义；sr 自造名仅作 Mirage 隔离记录。

### 5.4 Mirage 自身的 sampler 风险

以下不是可借鉴合同，而是固定 revision 的静态风险：

- `TextureCache.cpp:67-85,404-421,857-874` 中 2D sampler 的 V 轴寻址读取 `wrapS`，`wrapT` 被写到 W；若 S/T 不同，会得到错误的 V 轴行为；
- `TextureKey::HashValue` 在 `TextureCache.cpp:330-343` 计入 `magFilter`，但未计入 `minFilter`，而相等性/请求 identity 的其他路径会比较两者；这可能造成 hash bucket 碰撞增加，若下游只依赖 hash 还可能产生错误复用，需动态确认；
- 普通 render target 的 sampler identity 可以来自 `SceneRenderTarget.sample`，但另一个 `CreateRenderTargetTex` 入口固定 nearest-clamp；需要按调用路径确认哪个入口实际拥有目标，不能从函数名推断全局行为。

## 6. layer、effect、FBO 与合成

### 6.1 layer 顺序与父子树

Mirage 在一次 JSON 顺序扫描中记录所有对象，再在 finalize 阶段按声明顺序 append 到各自父节点；注释明确把同级声明顺序视为 z-order（`SceneCompiler.cpp:6080-6106,6415-6449`）。父子关系负责变换、可见性和 parallax 传播，但不会用对象 ID 排序来替代作者顺序。

需要注意：SceneScript 的 `sortLayer` 在此 revision 是 no-op（`ScriptRuntime.cpp:2951-2957`），所以静态顺序保留并不等于动态排序已支持。

### 6.2 每层独立 effect working space

普通 image layer 有 effect 时，Mirage 先把 source draw 写入该层私有 ping-pong RT。working extent 的选择不是统一屏幕大小：

- fullscreen effect 跟随 active camera/screen；
- 非 fullscreen effect 使用作者对象/effect target size；
- per-layer effect camera 是与该 extent 对应的正交 camera，并附着在 source node 上，继承父容器的世界位置但避免全局相机状态泄漏；
- linked/composite group 可拥有单独 group camera 与私有 target；
- source 是 nearest 时，A/B 两只 ping-pong 目标都继承 nearest；
- 非 fullscreen 私有目标在需要时透明清除，composite group 目标可声明 preserve-on-write。

对应入口为 `SceneCompiler.cpp:3243-3322`。这条链避免了用底层纹理分辨率冒充 layer/effect logical extent，也避免用一个全局 offscreen pool 尺寸覆盖所有 layer。

### 6.3 effect pass 与 FBO 的解释

`ImageLayerSpec.cpp:146-214` 解析 effect 的 FBO、material pass、bind 和 command。旧式两 pass `compose` 会被改写成显式私有 FBO 与绑定关系，而不是留成一个无人执行的 metadata 标志。

`SceneCompiler.cpp:3349-3577` 对每个 effect：

- 合并 effect 级 material 与当前 pass override，同时保留 texture 空槽；
- 把 pass target、显式 bind、named FBO、用户纹理和当前 `previous` 映射到具体资源；
- 若 pass 自己读取正在写入的目标，读取的是进入本 pass 前的资源版本；
- 记录 pass 是否使用 unit final quad、是否需要 puppet/mask 子材质以及最后一跳是否可直接承担 final composite。

`LayerEffectStack.cpp:52-163` 负责运行态 ping-pong：

- 所有指向当前 ping-pong A 的输入重定向到当前 source；
- 默认输出或 B 重定向到另一只目标；
- 中间 effect 的 blend 归一为内部覆盖，避免中间 pass 提前与场景背景混合；
- effect 完成后交换 source/destination；
- 最后一步恢复 layer 的最终目标、作者 blend/depth/cull、final geometry/camera 和 alpha 来源。

这解释了一个常见错误：source draw、effect pass、final composite 不是同一个 pipeline state。只把 shader 串起来而不恢复最终状态，alpha、背景混合、3D depth 或裁剪都会错。

### 6.4 RenderGraph 的资源版本

`FrameGraph.cpp:357-420` 给同一 logical texture 的连续写入创建不同版本，并建立 reader-before-next-writer、旧 reader-before-new write 等依赖。`SceneRenderPlanner.cpp:247-440` 再把 scene node/submesh/material 转成 pass：

- 每个材质 slot 的纹理是显式 read；
- 每个输出 target 是显式 write；
- self-read/write、copy、linked layer consumer、reflection 和 post-process 都进入依赖图；
- first write、透明 clear、force clear、preserve、depth 初始化分别决定 attachment load op；
- 隐藏但被其他层采样的 linked source 仍可写入私有 target，未被引用的可消除子树才跳过。

这类版本化比“两个纹理轮流写”更重要：A/B 只是物理资源策略，graph identity 还要描述某次写前/写后的逻辑版本。

### 6.5 clear、preserve 与残影

`SceneRenderTarget` 明确区分：

- `force_clear`：每次写都透明清除，适合文字等会缩短/移动的私有 layer 目标；
- `clear_on_first_write`：本图第一次写清除；
- `preserve_on_write`：后续 graph version 保留既有颜色，适合 composition target；
- depth attachment 单独决定首次 clear 与后续 load。

`MaterialPass.cpp:516-575,737-752` 将 blend mode、preserve、clear 和 target policy 合并成 Vulkan load op；透明私有目标清为 `(0,0,0,0)`，scene target 才使用 live clear color 且 alpha 为 1。错误地统一成 `.clear` 会破坏累积/compose，统一成 `.load` 则会跨帧残影。

### 6.6 mask 与 puppet

Mirage 没有把所有 mask 当作 fragment shader 的额外纹理开关。Puppet clipping 使用两步图：先用 mask parts 写 mask RT，再用克隆的 main material、mask target combo 和专用 slot 绘制 clipped parts；原 main draw 会移除这些 parts，避免重复绘制（`SceneCompiler.cpp:3127-3238`）。

多 material/submesh 仍保留文件 part 顺序，`MaterialPass.cpp:947-965` 按 draw range 顺序绘制，使后面的部件覆盖前面的部件。mask、submesh、material slot、draw range 和 final effect 必须作为同一 layer source 的组成部分，不能只捕获 mesh 0。

## 7. 材质、shader 与 GPU render state

### 7.1 Material/pass 合并

`MaterialSpec.cpp:58-138` 的关键行为：

- clone 保留 blending、cull、shader、depth test/write、textures、combos、constants、user values、puppet 和 bindings；
- pass override 只覆盖非空 texture slot，空槽不会压缩；
- sparse user texture 数组保留索引；
- combos、constant values 和 runtime binding 按 key 覆盖。

因此 material identity 不应只用 shader 文件名或 effect 名。slot 空洞、combo、state、constant、动态 binding 和纹理 purpose 都会改变真实程序。

### 7.2 shader 编译与 reflection

Mirage 的 `MaterialShaderCompiler.cpp` 是一套独立的兼容前端：解析 include/define/combo/声明，将受支持的 HLSL/GLSL/geometry 形态交给 glslang 生成 SPIR-V，再反射 vertex input、descriptor binding 和 uniform block。`MaterialPass.cpp:422-469` 只绑定 shader 实际声明的 slot；不存在的 slot 不强行写 descriptor。

uniform buffer 先写 shader default，再写 material constants，最后每帧覆盖 host/runtime 值。多 uniform block 目前只绑定一个实际 buffer，源码会告警；所以它仍不是任意 shader 兼容证明。

### 7.3 blend、alpha write、depth 与 cull

`PipelineShared.cppm:12-87` 和 `MaterialPass.cpp:516-575` 将材质状态映射到 pipeline：

- normal/disable 不启用 blending；translucent 使用 straight source-alpha 混合；additive 使用 source-alpha 加法；alpha-to-coverage 走 multisample state；
- translucent/additive 不写 depth；normal/disable/alpha-to-coverage 可按材质 depthwrite 写 depth；
- depth compare 是 less-or-equal；
- front/back/no-cull 原样进入 raster state；
- global/direct display path 默认不写 alpha，而 effect-local/final target 可写 alpha。

这里还存在一项需要对照验证的独立实现选择：Mirage 的 imported texture 数据与上述 source-alpha blend 是否在所有材质路径保持 straight/premultiplied 一致，源码静态检查不足以证明。MyWallpaperX 不应直接复用 blend factor，而应先确认自己的 texture content contract。

### 7.4 uniform 数据源

`SceneUniformBinder.cpp:117-169,190-575` 按 shader reflection 只准备被声明的值，包括：

- model/view/projection、effect transform、normal matrix及其逆；
- time、frame time、day time、pointer current/last、screen、texel；
- 每槽 resolution/mipmap；
- sprite frame 变换；
- layer alpha/color/brightness 动态覆盖；
- camera parallax：`g_ParallaxPosition` 为 float2、由 node uniform 声明驱动探测（`G_PARALLAXPOSITION`，`SemanticTextures.cppm:176`@da4fa7b3）；parallax.enable 时上传“中心 0.5 + 平滑鼠标经翻 Y × mouseinfluence”的二维向量（0.5+flipY(m−0.5)*inf），不乘 amount/depth/ortho，与 modelTrans 视差位移是两条独立通路且方向相反（uniform 通路 mouse−0.5、modelTrans 通路 0.5−mouse）；parallax 关闭时输出中心 {0.5,0.5} 而非零（`SceneUniformBinder.cpp:433-441/:152`@da4fa7b3）；我方现役实现与之代数等价（SceneAuthoredShaderFrameInputs+FrameContext.swift:21-22、SceneResolvedMaterialUniformEncoder.swift:87-95 以 NDC→0..1 上传、SceneResolvedMaterialUniformHostSchema 同名声明驱动）；
- 最多四灯；
- 16/32/64 档左右声道音频；
- puppet bones 与 bone alpha。

这套 binder 的优点是“声明驱动、按 pass 更新”；它的限制见第 13 节。

## 8. effect、global post-process、reflection 与 lighting

### 8.1 layer effect 与 global post-process 分层

Mirage 把 layer effects 放在 layer-local ping-pong 中，把 Scene global post-process 放在主 scene graph 全部完成之后。`SceneRenderPlanner.cpp:568-580` 最后追加 post-process pass/copy，所以 Bloom 不会误插到某一层的 source/final composite 中间。

### 8.2 Bloom/HDR

`SceneCompiler.cpp:6196-6381` 构建 screen-bound Bloom graph：声明降采样目标、按 HDR/LDR 分支装载不同 material、执行多步降采样/模糊/上采样/合成，最后 copy 回默认 screen RT。threshold、strength、tint、feather、scatter 等 Scene 参数进入材质常量。

Bloom post-process 对象名为 `__bloom`；其 fboMap 把 `previous` 与 `_rt_default` 都别名到 `_rt_default`（`SceneCompiler.cpp:6221-6222`@da4fa7b3），故首个 pass 直接读默认 screen RT。同时 Mirage 对官方材质引用的 `_rt_Bloom*` 前缀 RT 在特殊纹理准入中清空（`SemanticTextures.cppm:38`、`SceneCompiler.cpp:1663-1666`@da4fa7b3），自建 `_rt_bloom_mip*` 前缀则保留（`SceneCompiler.cpp:1652`@da4fa7b3），两套前缀准入命运不同。

可借鉴的是 Bloom 作为正式 post-process graph，而不是一段末尾可选 shader。不可照抄的是其当前数值与存储：HDR 分支的采样 offset 以 1920×1080 为硬编码基准，而且 RT/最终 screen path 仍为 RGBA8 UNORM；这只能说明它有 HDR-named 分支，不能证明 HDR 动态范围或任意分辨率 kernel 正确。

### 8.3 planar reflection

`SceneRenderPlanner.cpp:479-525` 在主 scene traversal 前单独发射 reflection view：只绘制标记为 reflected、且自身不采样 reflection target 的节点，避免递归反馈；材质读取 reflection target 后，RenderGraph 自然建立依赖。

`CameraRig.cpp:95-123` 的 reflection camera 镜像 eye 和 center 的 Y，保持 up 不变，以维持画面直立。这是 Mirage 的 Y=0 平面实现，不是任意反射平面或官方数值证明。

### 8.4 lighting、fog、shadow 和 volumetrics

Mirage 解析 point/spot/directional light、颜色、radius、intensity、cone、attenuation、shadow/volumetric flags，并把最多四灯的位置、颜色/radius、方向/type、cone/exponent、shadow flag 上传给 shader。ambient、skylight 与两类 fog 参数进入全局 uniforms。

固定 revision 没有 shadow atlas。`MaterialShaderCompiler.cpp:288-318` 对正交 image layer 的 shadow-casting light 采用抑制策略，避免把本应有阴影的光错误当无阴影全屏照明。`castvolumetrics` 被解析，但未发现与 `_rt_volumetrics` 闭合的正式 pass。结论只能写成“字段/部分 lighting uniform 已接线”，不能写成 shadow/volumetric lighting 已支持。

## 9. 相机、坐标和 fill mode

### 9.1 三类 camera context

`SceneCompiler.cpp:2487-2558` 至少建立三类相机：

- `effect`：2×2 正交相机，用于 NDC fullscreen/effect pass；
- `global`：以 Scene orthographic projection extent 为基准的 2D 相机；
- `global_perspective`：用于正交场景内嵌 3D 或真正 perspective Scene。

正交 Scene 内嵌 3D 的 perspective camera 使用独立距离/FOV，并采用反向 near/far 设置；真正 perspective Scene 读取 scene camera 的 eye/center/up 与 FOV，并成为 active camera。per-layer effect 又会建立自己的 local orthographic camera。

这说明 `mvp` 不是全局唯一值。source mesh、effect-local quad、final layer composite、linked capture、reflection 和 3D node 需要知道自己处在哪类 view。

### 9.2 camera node、path 与恢复

`CameraRig.cpp:16-147` 对 node camera 使用完整 world transform 的逆作为 view，避免父子 scale 泄漏进 local effect camera；遇到非有限或不可逆 frame 会回退 identity。也支持显式 look-at camera。

`SceneCompiler.cpp:2561-2640` 与 `World.cpp:856-910,1335-1362` 把 camera object 的 origin/angles/zoom/FOV curves、用户可见性和 script binding 组织成 camera path。每帧只 tick enabled path；同一 camera 没有 enabled path 时恢复保存的默认 transform/viewport；更新后同步 linked camera。

### 9.3 fill mode 与 resize

`VulkanFrameEngine.cpp:1402-1454` 不在 final blit 阶段裁 UV，而是根据 Stretch/AspectFit/AspectCrop 调整 global orthographic viewport，同时更新 perspective aspect/FOV、linked cameras，并重新捕获 camera path 的默认 viewport。

这意味着 fill mode 会影响：

- 主相机可见范围；
- camera animation 的默认 width/height；
- parallax、world-to-screen 与 hit-test 的坐标假设；
- fullscreen effect 的 target extent。

只在最终 drawable 上做 aspect-fit/crop，而脚本、鼠标和 effect 仍使用旧 scene viewport，会形成显示与交互错位。

### 9.4 camera parallax 与 shake

`SceneUniformBinder.cpp:80-123`@da4fa7b3（parallax/delay/mouse 现集中于该区间；既有引用 `:262-333` 已随 revision 漂移为 shake 区间）：

- parallax 只在 Scene general 启用后计算；
- 鼠标按配置 delay 平滑，delay 为 0 时显式避免 NaN；
- MouseInput 实时回退：新输入把 `m_mouseDelayedTime` 按“距上次输入的实时间隔”回退并 clamp≥0，持续移动时不累积 delay；FrameBegin 每帧推进封顶后以 t 对平滑位置 lerp，delay==0 时 t 强制 1.0 防 NaN（@da4fa7b3）；
- layer 的两轴 parallax depth 可从父节点传播，遇到 disable-propagation 截断；
- effect-local source 不重复施加 parallax，避免 source 和 final 两次位移；
- Mirage固定revision的shake作用于active camera VP，自身按canvas最小边缩放，并允许显式perspective camera object抑制global shake；这是该参考项目的策略，不是Wallpaper Engine合同。

官方2.8.42哈希匹配客户端的bounded静态复核与上述两点冲突：orthographic shake以作者projection height为尺度，true perspective使用XYZ displacement，且explicit perspective camera不会关闭全局shake；官方parallax还读取shake后的working camera XY。Mirage只能支持“shake进入shared camera frame”的架构方向，不能用于MyWallpaperX的幅度、维度、projection admission或parallax顺序。其shake函数属于参考项目自有实现，不能搬入MyWallpaperX当作兼容公式。

## 10. 鼠标输入、SceneScript 事件和 hit-test

### 10.1 macOS 输入来源

桌面 wallpaper window 设置 `ignoresMouseEvents = YES`，因此 Mirage 不从窗口 event responder 获取交互，而是轮询全局 `NSEvent.mouseLocation` 和 `pressedMouseButtons`（`MacDesktopHost.mm:287-327,377-413`；2026-10-01 于 da4fa7b3 复核：同段位于 `MacDesktopHost.mm:527-568`（PollInput）/:661-679（NSTimer、input_hz 上限 240）/:346-370（NormalizeGeometry），与 v1.0.3 快照行为一致、仅行号平移）。

它按选定 `NSScreen.frame` 归一化：X 左到右，Y 从 macOS 底部原点翻为上到下，并只发送前三个按钮。按钮 held/pressed/released 使用原子 bitset；edge 会保留到下一帧消费，避免一次 render tick 之间的快速按下/释放完全丢失（`WallpaperEngineRuntime.cpp:986-1007`）。

Web 壁纸走与上述 Scene 轮询并行的独立输入转发链（职责分层对照，固定 revision `da4fa7b3ee33e9e94c59307f47098aa521f21aa6`）：桌面窗口收不到事件，由全局 NSEvent 监视 + CGWindowList 桌面层 hit-test 决定是否向 WKWebView 合成鼠标事件。Mirage 为 `WRDesktopInputForwarder.mm` 全局 monitor、约 0.2s 缓存 hit-test、坐标归一化后经 WebRendererEngine 注入 `__wr_dispatchMouse`（`WebRendererEngine.mm:498`@da4fa7b3）；我方对应 `MyWallpaperX/Core/SteamWorkshopWeb/Host/` 的 +InputForwarding、+InputForwardingMonitors、+InputForwardingHitTesting 三文件同构。

WebRenderer 其余职责维度对照（`third-party-reference-pattern`，@da4fa7b3）：资源 serving owner——`we-wallpaper://` 自定义 scheme 同源服务+overlay/loadFromMemory，对照我方受控 scheme+loopback 双凭据（[Web 现役状态](../../web/current-state.md):18/41/46）；WE 页面桥接——document-start user script+evaluateJavaScript，对照我方 messageHandlers+兼容脚本 frame 门；频谱 producer 归属——引擎内 WRAudioTap 麦克风自采，对照我方 App 系统 tap 唯一 producer 按 typed demand 分发（runtime-as-built-map 不变量 18 不变）。只补职责归属对照，不新增行为规格、不改我方任何既有裁决。

### 10.2 shader pointer 与 SceneScript 坐标

- shader 得到归一化 current/last pointer；camera parallax 使用平滑后的归一化鼠标；
- SceneScript `cursorScreenPosition` 使用 top-down screen/canvas units；
- `cursorWorldPosition` 把 X 乘 canvas width，并翻转 Y 后乘 canvas height；
- 此 revision 的 `cursorLocalPosition` 直接等于 world position，没有对当前 layer 做 inverse transform。

`WallpaperEngineRuntime.cpp:1135-1138` 还把 `screen_w/h` 设置为 Scene ortho canvas，而不是实际 drawable pixel extent。因此 Retina、多屏、fit/crop 下的 script screen 语义仍需黑盒验证。

### 10.3 event 顺序与 pointer capture

`ScriptRuntime.cpp:3791-3854` 在 script `update()` 前分发 cursor enter/leave/move/down/up/click：

- down 只在按下时命中 node 才触发；
- down 后按 button 捕获该 node，移出 bounds 仍继续 move/up；
- up 在捕获 node 上必达；
- click 只在 release 时仍命中才触发。

这种顺序允许 `update()` 在同一帧观察 cursor callback 写入的状态。

### 10.4 当前 hit-test 限制

`ScriptRuntime.cpp:1224-1245` 只把节点矩形四角变换到 world，再对其 world-space AABB 做测试。它不处理：

- 旋转四边形的精确多边形边界；
- alpha/透明孔洞、puppet mesh、mask；
- depth、遮挡、z-order；
- perspective camera projection；
- fill-mode 的 letterbox/crop 映射；
- 当前 layer 的 local inverse transform。

此外，全局轮询看不到 scroll、keyboard、pressure 和三键以外按钮；wallpaper window 忽略鼠标事件时，轮询仍可能观察到本来投向桌面图标或其他窗口的点击。Mirage 这一路径适合作为“如何在不可接收事件的桌面窗口上获得基本鼠标”的平台参照，不应当作完整 SceneScript 输入语义。

## 11. 其他直接影响画面的运行系统

### 11.1 SceneScript 与动态拓扑

SceneScript 在 camera path、material animation、transform updater 和 particle emit 之前执行。脚本可以改变 layer 字段、text、visibility、material texture/combo、camera、video 等；提交阶段把值分流为 uniform/resource/geometry/graph 更新。

Mirage 为脚本设置内存、stack、初始化和每帧时间预算；单帧所有 timer、cursor callback 和 `update()` 共用 100 ms watchdog。超时后脚本永久停止调用，但 actuators 保留最后值，renderer 继续显示。这种“脚本故障不拖死 render thread”的失败隔离值得保留；其具体预算不是官方合同。

### 11.2 时间、动画与音频

- node field animation 先于 script，camera/material/transform animation 后于 script；同类值发生冲突时，顺序会决定最终覆盖者；
- shader time 使用 Scene elapsed time，frame time 使用 speed-adjusted tick；视频也按 speed-adjusted frame time推进；
- SceneScript 得到真实 local time-of-day；shader day-time 路径在此 revision 实际仍有缺口，见第 13 节；
- 音频左右声道以 64 bins 进入 script，binder 再按声明生成 16/32/64 档；粒子另使用 16-bin average，并与 embedded sound 信号 max-with-decay 合并；
- 250 ms stale policy 让失联 audio source 回到 silence，防止最后一帧频谱永久停住；
- Mirage 帧时钟家族分层（`FrameClock.cpp:11-72`@da4fa7b3，`third-party-reference-pattern` 参照结构、非官方 2.8.42 取证）：FrameTimer 内持 ThreadTimer 专用线程定时器；busy CAS 帧不重叠门（上一帧未 FrameEnd 则本 tick 直接拒绝）；steady_clock FrameBegin/FrameEnd 实测进 5 帧滑动窗口求均值；对外暴露 FrameTime（实测均值）与 IdeaTime（max(实测,理想)）双帧时；构造默认 15 FPS。作为我方 SceneFrameTiming 的对照参照，不修改我方合同。

### 11.3 文字

Mirage 使用 FreeType/fontconfig 解析字体，按 face+pixel size 维护 atlas，布局负责 alignment、padding、outline/background 和动态 mesh。动态文字预留有限 mesh/RT 容量，超出范围裁切；point-size 或 text 改变时可更换 atlas、更新 UV/geometry 并调整 layer target。

文字常见显示错误不是“字体没画出来”，而是 atlas 已更新但材质仍绑旧 texture、mesh 尺寸变了但 RT 未变、RT 未透明清除导致旧字残留、final UV 仍按旧 bbox 采样。Mirage 的 dirty event 分流就是为这四类状态保持同步。

### 11.4 视频

视频 decode、播放时钟与 GPU texture 是分开的：播放 state 保存 playing/rate/seek sequence；decoder 按 PTS 产出；texture registry 只给本图仍 active 的 slot 更新；同一稳定 RGBA target 被材质持续引用。硬件路径失败可回退 CPU NV12，而不是替换材质资源身份。

### 11.5 粒子与光线逐项对照（2026-09-27）

本节单独固定到本地开源 checkout `f5049582e3e334cac6b177bbbccb39736190750a`，其余章节未整体重证。参考是独立实现线索，不是官方正确画面的判据；本轮未构建运行 Mirage。下表检查定义、默认值和实际 consumer，明确保留尚未逐字段核实的部分，不把组件名称相同视为实现等价。

参考入口均相对 `SceneRenderer/Sources/SceneRenderer/`：`Kernel/Json.cpp`、`Wallpaper/Schema/ParticleLayerSpec.cpp/.cppm`、`Wallpaper/Compiler/ParticleCompiler.cpp`、`Domain/Particles/ParticleSystem.cpp`、`ParticleEmitter.cpp`、`WallpaperParticleGeometry.cpp`。我方入口为 `SceneParticleDefinitionParser`、`SceneParticleInitializerExecutionPlan`、`SceneParticleOperatorExecutionPlan`、`SceneParticleSimulator`、`SceneParticleRuntime`、`SceneParticleRenderSupport` 和唯一 compositor。

| 定义 / 默认输入 | Mirage 实际 consumer / 行为 | MyWallpaperX consumer / 差异 | 可区分输入 / 下一门 |
|---|---|---|---|
| 数值标量转三维向量 | `Json.cpp` 固定数组只写 X，Y/Z 为零；vector string 走另一解析分支 | `SimulationMath.vector` 广播 XYZ | scalar `0.6` 与三个单轴向量；旧标量官方轴合同仍 unknown，不能据此改成 X 或 Z |
| General `maxcount/starttime/flags` | Schema 默认 `1/0`；System 预热最多 240 步但覆盖完整 starttime | authored capacity + 既有预算；固定步长预热，已修 15 秒被截为 4 秒 | 比较同总时长出生数/相位；不同步长不是官方等价证据 |
| `boxrandom` | Emitter 消费 origin、distances、directions、CP、speed、rate/instantaneous/duration | SpawnPlan → shared birth state；已有 centered box 与方向/速度准入 | 零/单轴/反向范围、带 CP 旋转的径向速度；完整默认与分布待逐字段公式对照 |
| `sphererandom` | sphere 半径、方向、sign、CP 与 speed 进入出生状态 | `randomSphereOffset` 直接按有效维度采样，已消除拒绝采样固定 X 回退 | 8 种轴子集、YZ shell、径向速度；官方 RNG/分布仍未证明 |
| `lifetimerandom` | 默认 `0...1`，exponent 随机值 → lifetime | 同默认，scalar plan → particle lifetime | 零寿命、exponent、子系统 death 顺序；随机序列不作等价声明 |
| `sizerandom` | 默认 `0...20` → size；几何又使用 half size | 同默认；Runtime 发布 `size * 0.5` 后几何按宽度/aspect 消费 | 自制 100/200/400 卡已实测；[同状态GPU消融](runtime-evidence-current.md#e-2026-09-27-lightshaft-geometry-ablation)中×2将内部亮峰移出顶部，单改角度轴无此结果；用户确认中部也应有渐变，不能用峰值出屏当验收。倍率仍待作者单位判别，不增加裁根算法。两项目都有 half size 不证明官方单位正确 |
| `alpharandom` | 默认 `0.05...1` → initial alpha | 同默认 → initialAlpha/current alpha | 重叠 alpha operators 的最终片元，而非只看创建值 |
| `colorrandom` | 默认黑至白，单一随机数插值 RGB；此分支不消费 exponent | RandomColor plan 另有 exponent 输入，创建后存 initialColor | 固定端点、非灰端点/exponent；通道相关性与色域需独立核实 |
| `velocityrandom` | 缺省 XY `-32...32`、Z0；加到出生速度 | 缺省全零，加到出生速度 | 只写 max 的单向速度；默认值差异已定位，本轮无新官方默认值证明 |
| `rotationrandom` | 缺省 Z `0...2π`；显式 numeric scalar 经 X-only 路径 | 同缺省 Z；显式 scalar 广播 XYZ | scalar/明确 XYZ/单轴三组；直接影响光束缩短、倾斜与宽根 |
| `angularvelocityrandom` | 缺省 Z `-5...5`；scalar 同上 | 同缺省；scalar 广播 XYZ | 固定角速度 + 有/无 Angular Movement |
| `turbulentvelocityrandom` | compiler 闭包保存自己的 curl-noise 游走位置，消费 scale/time/offset/speed/basis | 自有 prepared turbulence plan → initializer velocity | 两者噪声/状态演进不同，不能当公式来源；待固定输入、时间和方向的轨迹对照 |
| `movement` | drag/gravity 更新速度；System 在所有 operators 后无条件积分位置 | authored-order Movement 自身积分；本批修 finite negative drag 被截零 | 无 Movement、Movement 前/后 force、多 Movement；保留官方“需要 Movement”的合同，精确顺序仍待判别 |
| `angularmovement` | 更新角速度；System 在 operators 后无条件积分角度 | 只有 Angular Movement 积分；本批同样修 signed drag | 无组件静止、负/零/正 drag、Float 溢出原子拒绝 |
| `sizechange` | normalized life 的 start/end 插值，含 instance size factor | scalar change plan → current size | 与 General size 叠加是否重复、倒置时间/缺字段；本轮不宣称等价 |
| `alphachange` | normalized life 插值 → current alpha multiplier | scalar change plan → current alpha multiplier | 两个 change 的顺序、start=end 与 fade 组合 |
| `alphafade` | 默认 in/out 均 .5；`if/else if` 重叠时只走一边 | 两个独立 if，重叠区相乘 | in=.8、out=.2 与普通不重叠对照；重叠合同 unknown |
| `colorchange` | 三通道 normalized life 插值 → color multiplier | color change plan → current color | 非白 initial color + 两个 change，逐通道核实 |
| `oscillatealpha` | age seconds；frequencymax=0 时用 min；随机 phase 上界额外加 2π | ScalarOscillationPlan 保留 authored max；phase 范围不作同样扩展 | 两种寿命、显式零频率、固定 phase；不能因名字一致认定同相位 |
| `oscillatesize` | 同上，scale 默认 .8...1.2 | 同 scale 默认，复用自有 oscillator | 尺寸峰谷时间与 instance size 组合 |
| `oscillateposition` | 各轴缓存 frequency/scale/phase，按导数 × dt 累加位移 | PositionOscillationPlan/cache → Simulator position | mask 阈值、scalar scale、phase、不同 dt；公式/时间语义未闭合 |
| `turbulence` | compiler 选择 phase/speed，自有 curl-noise 加速度 | 自有 TurbulencePlan/Simulator | 相同位置/时间/多个粒子的相关性；两者近似不能互证官方噪声 |
| `vortex` | CP frame、offset/axis、内外速度作用；非法 CP 会取模；自有径向公式 | bounded Vortex plan/Simulator，保留 CP/profile 准入边界 | 轴上零半径、环内外、CP 旋转、world-space；不能移植取模 identity |
| `controlpointattract` | CP frame→距阈值内 constant radial acceleration | bounded ControlPointForce→Simulator；已有 lifetime blend 与 strict identity | 恰好中心/阈值、负力、pointer/world-space；falloff 与完整空间合同待验 |
| Sprite / SpriteTrail | Schema length .05、maxlength10；geometry + common material | RenderSupport/ShaderSource；我方省略 trail length 走既有 bounded 合同 | 单位速度、不同尺寸/长宽比、固定/屏幕/up 基底；不能用缺省值覆盖既有作者合同 |
| Rope / RopeTrail | Schema subdivision3（ropeTrail1）、segments4；geometry 按连接序列 | prepared renderer/topology → 同一 GPU pipeline；已有 shared join/有限 subdivision | 折角、重复点、birth/death、多个 child、pointer 连续轨迹；schema 侧缺省（length .05/maxlength 10/subdivision 3/segments 4、renderer 名恰为 ropetrail 时 subdivision 强制覆写 1）已在 Mirage da4fa7b3 逐行重证（`ParticleLayerSpec.cppm:41-46`、`ParticleLayerSpec.cpp:57-65`@da4fa7b3），字段读取条件（rope 前缀/精确名）与 DescribeParticleRender→option→Gen* 消费者分派链属 Mirage 实现细节仅隔离记录；不升级官方 parity 宣称 |
| Child / CP / overrides | child maxcount20、probability1、origin0/scale1/angles0；CP index 有取模行为；override color 覆盖并平方 | shared ChildRuntime/Expansion + typed instance override；多处 strict bounded admission | child 非均匀 scale/angles、eventfollow、CP identity、color 乘法；不得退回宽松身份或覆盖作者颜色 |
| 材质 / atlas / texture / blend / refraction | geometry 继续走材质 sampler、blend、depth、camera binder | 现有粒子纹理/ShaderSource/unique compositor；宽度/aspect、BC3、normal/R-mask 已有专项门 | 最终像素与背景变形；本轮没有对所有 shader permutation 宣称闭合 |

Mirage host-pause 结构性冻结粒子（运行时证据链，@da4fa7b3，`third-party-reference-pattern`）：host 暂停冻结帧时钟后 `Emitt()`=Tick(scene.frameTime) 不再执行，粒子私有累积器 m_time、emitter state.timer/elapsed、trail 采样累积器全部停在同一值，恢复后无跳变，粒子侧无专用暂停钩子（`WallpaperEngineRuntime.cpp:1101-1116/1232`→`ParticleSystem.cpp:235/510-513/583-589`→`ParticleEmitter.cpp:210-213`@da4fa7b3；注意 trail 采样累积器行号署 `ParticleSystem.cpp` 而非 ParticleEmitter.cpp）。与我方共享 clock“pause 冻结、resume 首帧 delta 为 0”行为同构，仅互证、不改我方断言。

本轮材质合同补充：公开 stock `genericparticle.frag` 在 `ConvertTexture0Format` 后做两帧混合，再与颜色相乘；其注释明确保留透明帧RGB参与插值的旧加色行为。`common_fragment.h` 将R8解释为白色alpha、RG88解释为亮度alpha。MyWallpaperX现让普通粒子的root/child纹理、generated fallback和片元统一到该顺序：R8/RG88用同格式Metal swizzle view，过滤/混合后乘alpha并交给既有premultiplied compositor；无需CPU逐mip展开或按样本补偿。160组生产GPU反例与自制App渐变卡见[运行证据](runtime-evidence-current.md#e-2026-09-27-particle-straight-interpolation)。该改动不裁定size单位/标量角度，1315486372的光束原图alpha全满，亮根形状仍待单独闭合；也不把本轮结果外推为Mirage或官方全部材质等价。

参考 compiler 的两个 emitter、八个 initializer、十二个 operator 分支已逐项列出。此计数不含 renderer/child，不能与我方 parser 名称总数相除当覆盖率。我方另有 HSV、color list、position offset/around CP、event inheritance、boids、cap velocity、remap、reduce movement、collision plane、layer-image 等 bounded 路径；整体替换为 Mirage 会丢失这些行为。详细字段的严格边界仍由[粒子专项表](particle-component-coverage.md)负责。

**三种“光线”必须分别定位。** `1315486372` 的光线是带不对称 RGB 的粒子卡片，走上述尺寸/轴/基底/纹理链；authored Light Shafts effect 走 shader/material graph；`lspot` 等 light object 走 light snapshot 或 bounded spotlight projection。不能通过重写 light object 修复粒子纹理几何。

| Light 定义 / 字段 | Mirage `f5049582` 最终消费者 | 我方当前对应 / 缺省与边界 | 判别门 |
|---|---|---|---|
| Point/Spot/Directional，origin/angles/color/intensity/radius | LightLayerSpec → SceneLight → SceneUniformBinder → 自有 LightingV1，最多四灯 | 三类 Definition → SceneLightSnapshot，最多四灯；material producers 消费 | 单灯/四灯/溢出、父变换、可见性、动态强度与受光像素 |
| innercone/outercone/exponent | cone/exponent uniform 有 shader 计算 | Snapshot 携带 cone cosine；bounded SpotLightPlan 另消费 exponent | 普通 material 光照与独立锥形投影公式不能混为同一实现 |
| castshadow | Desc/uniform 有接线；正交 image LightingV1 抑制整灯；shadowAtlas 请求在特殊纹理准入中清空（§5 统一记载） | 本轮未重证我方完整 shadow producer/消费者 | 需要真实 shadow target + 遮挡物接收像素；字段存在不足以证明支持 |
| castvolumetrics / volumetricsexponent / density | castvolumetrics 保存在 Desc；volumetricsexponent 只见 schema；未见完整计算；`_rt_volumetrics` 特殊纹理名在特殊纹理准入中清空（§5 统一记载） | SpotLightDefinition/Plan/Runtime/Pipeline 有严格 bounded 2D 锥形投影，要求 solid、timeline 与有限参数等；不是通用体积散射 | 单锥/多锥、depth/遮挡、角度与密度；不得用 Mirage 作为完整体积光参考答案 |
| attenuation / mindistance / lightsourcesize / cascadedistance0/1/2 | schema→Desc，未找到实际渲染消费者 | 本轮未完成全部对应字段追踪，维持未验证 | 逐字段消融必须改变其目标 ROI 才能认定加载后有效 |
| scale/parent/parallax/dependencies/visibility 与 metadata | 通用 node/属性链；不是所有 metadata 都应影响像素 | shared layer frame/typed state；bounded spotlight 对 parent/dependencies 等有准入限制 | 先核实最终 world frame，再测相应光型；不凭解析成功扩张能力 |

重写顺序按共享首错点：①解析单位/标量轴和缺省值 → ②出生空间/基底/几何 → ③operator 顺序与时钟 → ④材质/光照资源及合成。已确定且有判别输入的职责可整体替换；unknown 留在对照门，不用随机拉伸、裁根或样本分支掩盖。负 drag 的产品结果与证据见[运行索引](runtime-evidence-current.md#e-2026-09-27-signed-drag)；亮根问题继续由原[诊断入口](runtime-evidence-current.md#e-2026-09-27-lightshaft-root)持有。

### 11.6 linked layer、隐藏 source 与 visibility

隐藏 layer 可能仍是别层依赖。Mirage 先从 snapshot 找出 linked source IDs；隐藏层无论是否被采样都进 visibility_elidable，由消费端 `!linked` 守卫使被引用者不被消除、继续写私有 `_rt_link_<id>`（该名来自 §5 特殊纹理准入改写；EnsureLinkRenderTarget 按 source layer 尺寸惰性注册 allowReuse=false，`World.cpp:1443-1453`@da4fa7b3；GraphLinkFinalizer::apply 见 `SceneRenderPlanner.cpp:196`@da4fa7b3），而不是直接混入 screen；未被引用的可消除子树才跳过。visibility 改变若影响依赖或 effect 数，会触发 graph rebuild。

可见性判定链（@da4fa7b3）：解析在 `Visibility.cppm` 纯函数（用户属性 payload 取 value 字段→bool 直取或 condition 标量等值比较）；消费在 `World.cpp` 四类入口——node/effect/light/camera path 各有 ApplyUser*VisibilityBindings；变更按 SetNodeVisible→`m_pending_node_visibility_changes`→CommitNodeVisibilityChanges 顺序提交，同帧先 false 后 true 只看最终态，elidable 集合 delta 才置 graph dirty（`World.cpp:1070-1085/1112-1124`@da4fa7b3；消费端 `SceneRenderPlanner.cpp:453/462/534-560`@da4fa7b3）；用户驱动 binding 命中无条件 rebuild，而脚本 tick 不走此路径；light 只改 runtimeVisible 不动 graph。

这个边界可避免两种相反错误：把隐藏 provider 完全丢掉，或把仅供采样的隐藏层重复画到最终背景。

## 12. Surface、分辨率与最终呈现

### 12.1 macOS drawable

`MacDesktopHost.mm:150-190,377-413`：

- window 位于 desktop icon 层以下，borderless、无阴影、跨 Space、stationary；
- `CAMetalLayer` 使用 BGRA8Unorm；
- `contentsScale` 取屏幕 backing scale；
- `drawableSize` 使用 view 到 backing 的转换，因此以物理像素创建 surface；
- 激活前后会验证 window/frame/layer/drawable 与目标 display 是否一致。

Scene 逻辑 canvas 与 drawable 物理像素因此天然分离，不能从 `NSScreen.frame` point size 直接推断 RT 像素大小。

多屏职责切分 Mirage 观察（`third-party-reference-pattern`，@da4fa7b3）：App 层 DisplayRegistry 为唯一屏身份/枚举 registry（`NSApplication.didChangeScreenParametersNotification` 驱动 invalidate+广播，`DisplayRegistry.swift:48-75/137-160/162-169`@da4fa7b3）；渲染层每个 MacDesktopHost 实例只绑定单 config→display_id（0 则取 `screens[screen_index]`，缺省 0 即主屏惯例），并按该屏 frame 归一化窗口与输入（`MacDesktopHost.mm:280-284/346-370/530-555/596-610`@da4fa7b3）；App 层 WallpaperViewModel 以 `CGDirectDisplayID` 为 key 维护 per-display assignment/pending 状态（`WallpaperViewModel.swift:68/158-159/328-341`@da4fa7b3）。DisplayKey 派生串格式（uuid:/vms:/idx: 前缀、#index 后缀）属 Mirage 特有实现细节、非官方规则。对我方价值在多屏开放边界（[覆盖台账](coverage-ledger.md):396/:1050）立项时的 App 层/渲染层职责切分对照，不构成对我方现有合同的修正。

### 12.2 render target logical/physical extent

`VulkanFrameEngine.cpp:313-374` 先解析 screen-bound 或 parent-bound logical width/height，再按 GPU framebuffer limit 得到 physical allocation，二者同时保留。mip count 按 physical extent 计算；screen uniforms 使用实际 surface extent。

值得注意的是 binder 对 render-target resolution 上传 physical/physical，而不是 logical/physical 混合四元组。若 shader 需要作者 logical extent，这条信息需要从其他 uniform/geometry 取得；不能把 Mirage 的选择推广为官方规则。

### 12.3 最终 copy/blit

`PresentPass.cpp:369-583` 把默认 screen RT 转成 transfer source：

- 目标尺寸和格式完全一致时直接 copy；
- 尺寸或格式不同时做全幅 linear blit；
- 随后转为 swapchain present layout；
- frame dump 与 Metal texture callback 观察的是同一最终结果。

此路径没有单独的 tone map、gamma encode、ICC/display color-space 转换或 alpha composite。screen RT 固定 RGBA8Unorm，host layer 是 BGRA8Unorm。它适合说明“最终只负责搬运已经合成好的 screen RT”，不证明颜色管理正确。

## 13. Mirage 固定 revision 的已知或疑似缺口

| 级别 | 观察 | 可能画面影响 | 证据状态 |
|---|---|---|---|
| 高 | sampler V 轴读取 `wrapS`，而 `wrapT` 写到 W | S/T 不同的 2D texture 在 Y 轴重复/夹取错误 | 源码静态确认；需构造纹理验证 |
| 高 | Bloom HDR offset 以 1920×1080 为基准 | 非该分辨率 blur radius/采样位置漂移 | 源码静态确认 |
| 高 | HDR-named Bloom 和 screen RT 仍为 RGBA8 UNORM | 高亮范围截断，不能证明真正 HDR | 源码静态确认 |
| 高 | SceneScript hit-test 只有 world AABB，无 camera/fill/alpha/depth | 旋转、透视、遮挡或裁切层交互区域错误 | 源码静态确认 |
| 中 | `cursorLocalPosition` 等于 world position | 依赖 layer local 坐标的交互脚本错误 | 源码静态确认 |
| 中 | script `screen_w/h` 使用 ortho canvas，不是 drawable | Retina、fill mode、多屏下 screen 坐标可能偏离 | 源码静态确认；需黑盒 |
| 中 | shader day-time 的实际更新时间代码被注释，默认成员为 0 | 直接声明 day-time uniform 的 shader 固定在零时刻 | 源码静态确认；SceneScript time-of-day 不受此项影响 |
| 中 | `SetTexelSize` 未发现生产调用，默认 1/1920×1/1080 | 依赖全局 texel uniform 的 effect 在非 1080p 偏差 | 静态搜索确认；per-slot RT resolution 是另一条路径 |
| 中 | 无 shadow atlas；部分正交 image lighting 抑制 cast-shadow light | 阴影/光照强度与官方不同 | 源码明确声明 |
| 中 | `castvolumetrics` 有 schema/light state，未见闭合 volumetric RT graph | 体积光可能缺失 | 静态路径未闭合 |
| 中 | present 无显式颜色管理/tone map | gamma、广色域、HDR display 可能不一致 | 源码静态确认 |
| 中 | particle emitter sort 固定 false；dynamic `sortLayer` no-op | 透明粒子或脚本调层顺序可能错误 | 源码静态确认 |
| 高 | shake按canvas最小边缩放并可被显式perspective camera抑制，与官方2.8.42的projection-height/XYZ及全局enable行为冲突 | 2D振幅随纵横比错误，perspective shake缺失；parallax相对位移也可能不同 | Mirage源码静态确认 + 哈希匹配官方客户端bounded Ghidra交叉 |
| 低/待证 | TextureKey hash 未计入 minFilter | cache 碰撞或特定实现下错误复用 | 静态确认 hash 字段；后果需检查容器 equality |
| 低/待证 | reflection 固定 Y=0 平面 | 任意平面反射不支持 | 源码静态确认 |
| 低/待证 | 单 uniform buffer 承载多 reflected blocks | 多 UBO shader 绑定不完整 | 源码告警明确 |

这些问题是使用第三方参考时必须保留的反例：架构闭合不等于所有数值、边界和平台行为都正确。

## 14. 与本地官方语义资料的对照方式

Mirage 只能提供“一个第三方实现怎样连线”的 `third-party-reference-pattern`。决定 MyWallpaperX 应该实现什么、哪些字段可被视为作者合同，仍须回到本地已经归档的官方资料与真实样本：

| Mirage 调查主题 | 本地优先核对入口 | 使用边界 |
|---|---|---|
| effect、pass、FBO、`previous`、compose/copy/swap | [场景格式与 Render Graph](scene-format-and-render-graph.md)、[内置 Effects 语义全集](effects-reference.md) | Mirage 的 target 名、pass 数和 fallback 不能反推官方默认 |
| material、slot、combo、shader built-ins | [Render Graph 与 Shader 覆盖表](render-graph-shader-coverage.md)、[Shader source 前置合同](shader-prelude-and-backend-abstraction.md) | 第三方 shader translator 和 stub 不能作为官方算法 |
| camera、parallax、mouse、audio、media、text | [运行时系统语义](runtime-systems-reference.md)、[运行输入与属性覆盖表](runtime-input-property-coverage.md) | 先确认作者启用条件、坐标域与生命周期，再比较 Mirage 接线 |
| SceneScript cursor/event/update | [SceneScript API 覆盖表](scenescript-api-coverage.md)、[SceneScript 2.8.42 静态研究](scenescript-runtime-implementation-contract.md) | Mirage 的 AABB hit-test、local=world 和 watchdog 都是独立实现选择；两份静态研究都不是 implementation input |
| particles、lighting、3D、puppet | [粒子组件覆盖表](particle-component-coverage.md)、[高级对象覆盖表](advanced-object-coverage.md) | 字段被解析或 uniform 被上传不代表完整执行 |
| 当前 MyWallpaperX 是否已支持 | [总覆盖台账](coverage-ledger.md)、[运行证据索引](./runtime-evidence-current.md) | 本页不能单独提升任何等级；必须有项目代码、测试和隔离运行证据 |

具体判断顺序为：先用官方页面/类型声明确定作者可见合同，再用客户端固定版本静态取证收窄内部结构，用真实样本确认 wire 形态，最后把 Mirage 当作结构交叉检查。如果只有 Mirage 一条证据，结论只能保持 `third-party-reference-pattern` 候选，不能进入通用执行准入。

## 15. 对 MyWallpaperX 的错误路径审计清单

本节只列“应沿当前代码继续核实的候选错误路径”，不是能力台账，也不覆盖工作区正在进行的其他批次。每一项都应以项目自有 fixture、隔离样本和可见截图收口。

### P0：先核实会系统性改变画面的三条链

1. **offscreen extent 身份**
   - Mirage：非 fullscreen effect 使用 layer/effect authored extent；screen-bound effect 才跟随 surface；设备 physical clamp 另存。
   - MyWallpaperX 候选：`SceneImageLayerCompositor+Uniforms.swift:72-82` 的 legacy 路径只在显式 `offscreenSize` 缺失时回退 source texture 物理宽高；普通 image request 在 `SceneMetalRenderer.swift` 目前只为 solid 显式给 offscreen size。需要核实 layer authored size、mapped size、capture size 和 graph target extent 是否在普通 image/effect 路径被合并。
   - 可见症状：effect 范围、blur radius、mask/UV、文字 bbox、nested layer capture 和 final scale 同时错。

2. **sampler 是否穿过中间目标与最终 composite**
   - Mirage：TEX sampler 进入 slot，point source 传播到 ping-pong；每个 sampled image descriptor 带自己的 sampler。
   - MyWallpaperX 候选：typed candidate/binding 已保存 sampling，但通用 `SceneMetalPipeline.swift:135-150` 和 `SceneLayerColorBlendPipeline.swift:27-35` 仍在 shader 内固定 linear-clamp；final offscreen texture 又回到同一 main/color-blend draw。需要逐条证明 source slot、effect input、named target、dependency、final texture 各自使用哪只 sampler。
   - 可见症状：nearest 变糊、repeat 拉边、mip 丢失、不同 purpose 的 data texture 被线性插值。

3. **final composite state 是否来自作者最终 material**
   - Mirage：effect 中间 pass 强制内部覆盖，最后恢复 final blend/depth/cull、geometry、camera、alpha source。
   - MyWallpaperX 候选：`SceneImageLayerCompositor.swift:239-280` 把 offscreen 输出以 identity texture frame、通用 layer pipeline/color-blend pipeline重新画回 main pass。需要核实 authored final pass 的 blend、alpha write、depth/cull、UV、sampler、dependency 和 layer color blend 是否被精确带回，而不是由通用 source-over 状态替代。
   - 可见症状：透明边发黑/发白、additive 变 source-over、alpha 被二次乘、隐藏依赖混入背景、3D 层遮挡错误。

### P1：按链路继续核实

| 链路 | Mirage 参照 | MyWallpaperX 要回答的问题 |
|---|---|---|
| object/source order | JSON declaration order + parent tree | 当前 descriptor 排序、父子 attach、dynamic order 是否保持同一合同 |
| sparse slots | 空槽保留、pass 只覆盖非空项 | 8 槽 IR 到 binder/encoder 是否始终不压缩 |
| graph version | 每次写产生 logical version | target pool 的 physical reuse 是否与 logical generation/reader closure 分开 |
| self read/write | 读进入 pass 前版本，必要时 copy | 同一 target 既读又写时是否有显式 prior identity |
| clear/preserve | transparent first clear、force clear、preserve 分开 | 每个 authored target 的 load/store/跨帧 history 是否被统一 clear/load |
| linked hidden source | 只写私有 dependency target，不直接上屏 | hidden provider 的 visibility、capture、consumer 与 final draw 是否分开 |
| local effect camera | 每层独立 extent/camera，避免双 parallax | source、effect、final 是否使用正确 camera/geometry frame |
| fill mode | 改 global camera，再同步 paths/linked camera | render、cursor、script、capture、parallax 是否共享同一 viewport mapping |
| dynamic property | uniform/rebind/extent/topology 分级 | live edit 是否错误沿用旧 graph/RT/material，或不必要地全重建 |
| masks/puppet | mask prepass + clipped submesh + source completion | mask 是否只在 dedicated effect shader 中生效，完整 layer capture 是否包含所有 submesh |
| post process | 主 scene graph 后追加全局 graph | layer Bloom 与 Scene Bloom 是否仍混为同一路线 |
| surface/color | 最终 RT 与 present 明确分层 | BGRA/RGBA、linear/sRGB、straight/premultiplied、capture/present 是否一致 |
| input coordinates | screen/world/local/parallax/hit-test 分消费者 | 当前 cursorUV 是否经过 fill/camera/layer inverse，事件命中是否与视觉一致 |
| time/provider | script/text/video/audio 在 draw 前提交 | 是否存在晚一帧、旧 generation、stale provider 或暂停/seek 时钟分叉 |

### P2：验证方式

每条修复至少需要一个项目自有正向 fixture 与一个负向/边界 fixture。纹理/合成类结果不能只看 non-black、route count 或 matrix PASS；至少检查：

- 映射区域四边、nearest/repeat/mip 的放大与缩小；
- 非 fullscreen 与 fullscreen extent；
- translucent/additive/opaque 的 RGB 与 alpha；
- effect 开关前后、连续多帧、target clear/preserve/history；
- parent transform、camera/fill mode、左右/上下鼠标边界；
- linked hidden source 只被消费者看到、不直接出现在 screen；
- final screenshot 与必要的中间 RT readback。

## 16. 后续研究清单

本文已完成主静态链路，但以下项目仍需后续按固定 revision 或新 revision 增补：

1. 选取项目自有最小 fixture，对 Mirage 的 S/T sampler、texel size、Bloom 非 1080p、AABB hit-test 做静态假设验证；不使用其资源作为项目资产；
2. 深入核对 MaterialShaderCompiler 的 combo/include/default texture、geometry shader 与颜色/alpha约定，只记录接口合同，不摘录 shader 实现；
3. 继续调查 3D model、MDL/MDAT/MDLA、attachment、puppet animation、normal/PBR、fog 与 reflection 的完整 pass 边界；
4. 补齐 particle renderer、child/control point、trail/rope、transparent order 与 camera-facing 细节；
5. 核实文字 alignment、fallback font、outline/shadow/background、动态增长上限和 Unicode shaping 的可见边界；
6. 核实 video color matrix 到最终 UNORM surface 的 transfer/gamma，及 pause/seek/loop 与 Scene speed 的组合；
7. 对照本地官方资料与真实样本，逐项标出 Mirage 的 compatible、heuristic、stub、missing；
8. 当 Mirage revision 变化时，只增量复核本页引用模块，并在页首更新 revision、日期和差异，不用新 HEAD 静默覆盖旧结论。

## 17. 维护约定

- 新结论必须给出固定 revision、源码入口和证据类型；没有运行验证时写“静态确认”或“推断”；
- 只记录对显示合同有长期价值的事实，不复制第三方算法或资产；
- Mirage 的 bug、TODO 和 heuristic 单独放在限制表，不能进入官方语义段落；
- 若某条调查推动 MyWallpaperX 能力变化，应在相应专项覆盖表和运行证据索引另行登记代码、测试、样本与证据；本页只保留参照链路；
- 本页与 [资料来源与证据索引](source-index.md) 互相链接；第三方 revision 或许可证变化时同步更新两处。
