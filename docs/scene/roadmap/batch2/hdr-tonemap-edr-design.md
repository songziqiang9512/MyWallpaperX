<!-- document-role: active-plan -->
<!-- retirementCondition: SDR 映射与可选 EDR 的目标合同并入稳定输出架构且通过各自显示验收后归档，删除设计登记。 -->

# D2 — Scene HDR、tone mapping 与 EDR 输出

> 复核基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；已合入 `codex/engine-refactor-program`；实施时按其最新代码重新核对所列 owner，以下行号仍指向原设计基线。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

保留作者高亮的中间精度，在唯一 terminal compositor 的输出阶段做一次有明确颜色语义的显示映射：先保持 SDR 正常颜色与 HDR Bloom，再开放可选 EDR。跨 target、Bloom、surface 和显示状态 owner，触及唯一输出与外部平台合同。

五判据：横切多个 owner 或主链节点=是；触碰唯一权威合同=是；用户可见且难逆的 API/数据/发布合同=否；触碰机器冻结结构家族=否；依赖官方或平台外部证据=是。

## 当前事实与证据

- [E-2026-09-27-SCENE-COLOR-PRECISION](../../capabilities/runtime-evidence-current.md#e-2026-09-27-scene-color-precision)（该文件 `:477`）：RGBA16F 已贯穿 graph 到 CAMetalLayer；仍是 display-referred sRGB，没有完整 HDR Bloom/tone mapping 或 EDR。
- `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift:156` 设置 pixelFormat，`:159` 设置 sRGB。格式精度不是 scene-linear 语义证据。
- 交接的静态取证 §7.4 是音频方向，不可用作 HDR 曲线依据；本设计不消费私有曲线、公式或常量。
- [官方 Bloom](https://docs.wallpaperengine.io/en/scene/effects/bloom.html) 公开区分标准与 Ultra HDR Bloom；不公开本项目所需的全部显示映射参数。
- [Apple 自行 tone mapping](https://developer.apple.com/documentation/metal/performing-your-own-tone-mapping) 支持 extended-linear color space、RGBA16Float、`wantsExtendedDynamicRangeContent` 与当前屏幕 headroom；这是 macOS 呈现合同，不是 WE 数值算法。公开资料复核日为 2026-10-01。

## owner

现役 descriptor/preparation 决定颜色内容类型与 storage；Bloom 在同一图内处理；terminal compositor 拥有显示变换；SceneMetalView 只配置 surface 和接收按屏幕发布的显示能力。禁止每个 layer 自做 tone map 或另开 HDR 输出器。

## 方案设计与选型

选择**显式区分 authored HDR 合成与显示 EDR**。HDR 的超白先参与 Bloom，SDR 终端保持正常颜色并裁剪显示范围；不为了压入全部超白层次而默认降低普通白点。只换 16F 不是 EDR，未经确认的系统 metadata 可能重复映射。

| 阶段 | 输入及输出合同 | 开放边界 |
|---|---|---|
| A：颜色语义确认 | 明确纹理 decode、shader 输出、blend、Bloom 的 transfer/primaries/alpha；沿当前 content/publication 表达 | 不得仅因 target=16F 就 reinterpret 为 linear |
| B：SDR | HDR scene color/Bloom → 正常 SDR 范围恒等、超白裁剪 → SDR terminal attachment | 非 HDR 既有 SDR 路径数值守恒；默认先交付此阶段 |
| C：EDR | 相同 HDR scene color → 当前 headroom 的扩展线性显示值 → RGBA16F extended-linear surface | 逐显示器能力、系统开关和用户选择共同允许时开放 |
| D：可选 metadata | 仅存在真实且格式匹配的内容元数据时评估系统映射 | 当前选择自有映射时不叠加系统 tone map；不可从截图猜 metadata |

颜色转换的位置先由 A 的合成 fixture 固定，不能简单给现有 display-referred 输出再套 gamma。HDR Bloom 在输出映射前完成；normal/roughness 等 data 不进入颜色变换。SDR 导出规定连续、单调不减、有限、保留正常范围内的颜色；超白可同白，不声称官方私有曲线或 EDR 高光验收。

**2026-10-06 阶段 B 纠正裁决。** 用户报告默认颜色变暗；无曝光输入、无 EDR surface/headroom 路由却仅因 `general.hdr=true` 自动使用 knee=0.5 的 shoulder，使普通白点 1 变为 0.75。该曲线是本项目旧策略，并非官方合同，本次撤销该默认压暗策略。官方公开 Bloom 文档说明 HDR 超白参与发光，不足以支持对全部普通图像强制降白点；本次是按用户目标纠正产品策略，不宣称官方数值 parity。 阶段 B 的唯一终端输出在 Bloom 之后对有限 RGB 饱和到 `[0,1]`，区间内逐通道恒等；非有限 RGB 归零，alpha 原样保留。非 HDR 路线不创建该 owner。中间 HDR target、raw history、反射及 Bloom 继续保留超白，不提前裁剪；只有最终 SDR 显示丢失超白强度区分，超白的空间发光贡献仍由 Bloom 保留。不要以可选 EDR 尚未完成为由维持默认普通颜色错误，也不能把 SDR 裁剪称为 HDR 显示完成。以后若需要曝光或保高光映射，应有显式输入/显示合同与独立对照，不恢复无条件的压暗曲线。

沿 RF07 的 distinct raw/display 导出与完成权威实施，不新增 renderer、历史、资源池或逐帧分析。清底与累积场景同样保持正常白点；raw 永不接收 Bloom/显示结果，暂停导出不重复合成。现有不透明 surface 边界不变，透明输出另验。GPU 纠正门使用独立已知 SDR 色块（含 0.625、0.75、0.875、1）的逐位保持、超白有限裁剪、非有限局部处理、Bloom 超白产生邻域增亮、source/alpha 保持、失败恢复和 raw 多帧累计；SDR 正常色不以旧曲线公式为 oracle。实际 App 验证 clear true/false 与暂停 resize。EDR 仍按 C 的平台门另行实施。

surface generation 绑定屏幕、颜色空间、format 与 headroom 状态；屏幕迁移或动态 headroom 变化更新 typed display state，不重编译整图。切换 SDR/EDR 使用已准备输出管线，候选失败前保留旧 surface/output。metadata 不是第一阶段的必需品。

## RF07-HISTORY：原始颜色与显示导出分离（设计裁决）

本后继独立于已验收的阶段 B 首片。以下为 RF07 开工基线的首断点，实施结果仅见[冻结执行记录](../../history/rf07-persistent-color-output-implementation-2026-10-02.md)：当时 `SceneMetalRenderer.swift:189/:251` 同时将 drawable 用作 admission mainTarget 和真实 attachment，`:925` 后 Bloom/映射又覆写它；`SceneDisplayMappingPostProcess.swift:43` 因此保留 clear=false guard。`SceneOffscreenTextureAllocationCache.swift:160` 与 `SceneOffscreenTextureResidency.swift:90` 已拥有 reset epoch、驻留及 pin；`SceneResolvedMaterialSubmissionCoordinator+Completion.swift:157` 是完成后提升的权威，但其 `+FrameCommit.swift:516` 的空 graph 分支尚不登记提交。`compositionTarget` 不具有跨帧内容保留权，不能冒充 history，也不能假造 layer/effect identity。

**目标与选型。** HDR、clear=false 的 authored composition 写入未映射的 raw sceneColor，终端从它导出 Bloom 和现有 SDR 映射。选择复用现役 allocation cache/pin 与 SubmissionCoordinator：每 surface 保留一个 completed raw、一个 candidate raw，显示 scratch 复用并收敛现有 D2 intermediate 职责。拒绝原地反复映射、renderer 私有 history 字典和第二资源池。它仍只有一次 layer traversal、一个 terminal compositor/present；普通帧不新增 reflection、建图或哈希。非 HDR 和 clear=true 路径数值守恒。

**颜色和首次初始化。** 新 surface/generation 无 completed raw 时，用现役 sceneClearColor（alpha=1）初始化一次；关闭逐帧清底不授权 load 未初始化纹理。此 bootstrap 是项目保守策略，不宣称官方初帧一致。raw 保存作者有序合成且尚未 Bloom/显示映射的 display-referred sRGB 数值；不 reinterpret 为 linear。Bloom 仅作用显示 scratch，不能累积回 raw。终端仍限定现有不透明 surface；透明导出、逐层 tone mapping、EDR 不开放。RGB 及 alpha 的存储/混合遵循现有合成合同，映射原样保留 alpha；不得因此声称任意透明终端预乘关系成立。

**版本、暂停和失效。** identity 使用现役 surface lifetime、pool reset epoch、exact extent/format、allocation generation/physical token 和 simulation frame identity；不新增时钟。首次 reserve 将 completed raw 拷入 candidate，无历史则 bootstrap。同一 raw epoch 已存在 completed frame 时，只有新的 simulation frame 才执行 authored draw；同 epoch/已完成 frame 的 paused 重绘只重新导出 raw，不能重复追加半透明层。resize/format/reset 后没有当前 epoch 的 completed raw，即使 simulation frameIndex 未变也必须 bootstrap 并合成当前 snapshot 一次；沿既有 render invalidation 解除 Surface.didSubmitSimulationFrame 的跳过，并用同一已存 snapshot 更新 render-only viewport/context/camera，不调用 updateSimulation、不推进 VM 或模拟；View.renderFrame 的旧 screenSize/camera 不能跨新 drawable extent 直接复用。尚未完成的同 frame 不另造候选。尺寸、format、颜色合同或 scene generation 改变开启新 raw epoch，不重采样旧历史；clear=true→false 也重新 bootstrap，不读取已映射 drawable 作为 seed。旧 epoch 的 completion 只释放原资源，不提升新版本。

**提交与失败。** 原 coordinator 同时登记 graph 与 terminal sceneColor（包括零 resolved-effect 的场景），GPU completed 且身份匹配才提升 raw。首片最多一个 pending raw candidate；busy 只 deferred 该 surface 的 render，现役 Session 仍每 cadence 消费并提交 VM/simulation/control revision，不回退或补播。cancel、raw/main encoder失败或GPU失败不提升 raw；SceneMainPassEncoder.finishEnsuringClear 必须交付真实编码结果，不能将吞掉的清底 encoder 创建失败当作已初始化候选。可选 Bloom/map encoder 失败时，若安全 raw→drawable 导出成立则局部降级并明确未映射，此整 buffer 正常 completed 后仍提升有效 raw；若无有效输出则取消该 surface 候选。display-only paused 导出也必须由原 coordinator 登记 submission pin/terminal，不得因没有 candidate/graph 而空分支早退。GPU 错误时保证逻辑 raw/display 版本不提升，恢复帧从最近 completed raw 导出；现有预排队 present 不保证屏幕瞬时物理回滚，不新增完成后呈现器来暗中扩大合同。

**预算与生命周期。** 使用现役实际分配预算及 pool logical budget，两者均准入；全分辨率 RGBA16F，不做 silent dimension clamp。4K raw pair 与 display scratch 约189.84 MiB，resize 时旧 in-flight pin 同时计入，分配不足保留安全旧结果。新用途直接扩现有 residency pin，独立的 D2 intermediate 缓存随职责迁入退役，不额外常驻第四张全幅纹理；释放等待 GPU terminal，reset/stop 不提前重用。

**纠正门。** 实施前建立真实 owner 的修前反例，不能仅断言 guard/符号。实际 GPU 依次验证：一次 HDR 色块加多个无新绘制导出，raw 不变且显示不反复变暗；半透明新增内容按独立合成 oracle 追加；Bloom 切换不改 raw；空 graph completion/promotion；每个分配失败点、cancel、提交拒绝、GPU失败与 stale completion；resize/reload、paused同帧重绘、跨 surface busy/恢复、诊断关闭与导出失败。沿同一 token/version 记录 completion、publication、terminal present 与 next-frame；保留 clear=true/非HDR回归，不将受控多surface冒称物理多屏或官方 parity。

**owner / 退役。** target cache/residency owns物理存储和pin；现役SubmissionCoordinator owns候选、terminal与completed版本；Renderer仅编排唯一输出。2026-10-02 独立只读设计复核已确认现 owner 可承载；本段按复核收紧 paused 新 epoch、显示降级提升和 display-only pin 三项后作为实施合同，设计登记同步批准，不代表产品验收；上述多帧和失败门全部闭合后由稳定target/output合同接管，删除派生卡及过渡设计入口。

## fallback / route

平台不支持、headroom 回到 SDR、可选 metadata 不可用时走已验证 SDR 导出。颜色语义不明的输入保留现役 SDR route 并标记未兼容；不得默默 reinterpret。非法 format/range/generation 拒绝候选输出，保留安全旧帧。普通映射管线失败不破坏前序 graph current。

## 纠正门

- GPU 自有阶梯覆盖暗部、中灰、白点、超白和多彩高亮；检查有限、单调、颜色/alpha 边界与未开启 HDR 的输出守恒。容差在执行前冻结，不以 8 位截图判断浮点精度。
- 同一输入分别经过 SDR 与 EDR；检查实际 colorspace、format、屏幕 headroom、submission completion、terminal present 和 next-frame；EDR 设备不可用则 C/D 标为 not-run。
- 移屏、headroom 改变、暂停恢复、allocation/encoder 失败必须回到有效 SDR，而不是黑屏或双重映射。
- 2684431262 只作为后续隔离回归输入；官方高亮对照与平台 EDR 验收分别记录，不能用一项代替另一项。

## 退役条件

每阶段完成行为门、颜色权威归入稳定架构、旧输出路径按 route 撤权后归档。未验证的 metadata profile 继续显式禁用，不随 SDR 验收自动解锁。
