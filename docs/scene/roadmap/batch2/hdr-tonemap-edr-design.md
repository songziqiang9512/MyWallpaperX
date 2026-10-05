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

## HDR Bloom 参数与运行分支（2026-10-06）

**首断点与目标。** Earth 作者 `general.bloomhdrstrength` 绑定 HDR slider；实际 App 三次修改均被 live consumer 拒绝。本批基线仅解析标准 Bloom，不能把 HDR slider 改绑标准强度当作兼容。保留 `bloomhdrstrength/threshold/scatter/feather/iterations` 的作者数值，沿现有 Document → CameraDescriptor/BloomConfiguration → property Program → typed snapshot → 唯一 Bloom owner 进入实际 GPU。标准 Bloom 和 HDR Bloom 各自使用其参数；显示 SDR/EDR 仍由终端 owner 决定。

**实施约束。** 扩展现有 Bloom owner，不建立新 renderer、资源池或逐帧参数解析。HDR 明亮提取、扩散与合成使用自有实现；标准分支保留。有限 strength/threshold 不按猜测的编辑器 UI 范围截断；scatter/feather/iterations 的边界与缺省依公开合同及有界官方自有输入实验裁决，不从两个样本反推默认。强度为零不分配/编码，值变化消费下一帧快照，不重启场景；浮点颜色先参与 Bloom 再进入 SDR 裁剪。中间资源在现有预算内准备，编码失败不把半成品加回原图，下一帧可恢复；超预算局部保留安全原图。

**自有 GPU 方案。** 根据官方自有色块对照选择多尺度明亮提取、下采样和上采样重建，不消费第三方或私有 shader。超白提取保留浮点能量，feather 控制阈值下方的连续贡献，scatter 控制多尺度贡献，权重经有界均匀场和未参与推导的输入验证；中间凸组合、末端与强度/染色一起恢复公共权重，避免大扩散/小强度提前半精度截断，tint 与 strength 在加回原图时应用；不将定性行为相同表述为数值 parity。物理层数受源图可用 mip 尺寸约束，缓存以尺寸及实际层数匹配，prepare/encode 共用计划。所有中间 pass 成功后才进行一次 RGB additive combine，alpha 不变；非法非有限参数或工作量不成立时只跳过 Bloom。

**缺省判定。** 官方 2.8.0.42、640×256 自有灰阶块对照中，逐个省略 HDR 五字段与显式 strength=2、threshold=1、scatter=1.619、feather=0.1、iterations=8 逐像素相等；每项另有可区分替代输入。运行配置使用这组缺字段等价值，不宣称所有输入或未来版本的默认 parity。

**验收。** HDR 开关/profile隔离、五字段实际消费、strength/threshold方向、scatter半径、feather边界与iterations差分均需GPU输出和有界官方对照；原标准Bloom、raw history、零贡献、失败恢复与SDR白点回归。真实Earth验证slider多次更新同PID/窗口、实际合成及退出；未闭合的官方数值差异保留明确边界，不以属性接线冒称HDR完成。官方自有输入的 iterations=0/1 出现独立于 Bloom strength 的全图 transfer，当前未解释；作者值低于2只跳过可选 Bloom、保留原图，不猜 gamma。该边界及精确空间核继续研究，不随本批开放。当前实施/运行证据见[冻结记录](../../history/sdr-white-preservation-implementation-2026-10-06.md#hdr-bloom-参数与重建后继)。

## RF07-HISTORY：已实施的原始颜色与显示导出边界

原始颜色与显示导出的隔离已实施，过程、失败门和验收边界统一见[冻结执行记录](../../history/rf07-persistent-color-output-implementation-2026-10-02.md)，不在本待实施设计复写。本次 HDR Bloom 必须保留其约束：作者有序合成写入未映射 raw；Bloom 只写 display scratch，终端显示结果不累积回 raw；每帧仍只有一次 layer traversal 和一个 compositor/present。

资源沿现役 allocation cache/residency pin 与 SubmissionCoordinator 管理，只有身份匹配且 GPU completed 才提升 raw。暂停导出不重跑 VM/模拟；resize/reset 后的新 raw epoch 先安全初始化。Bloom 或显示映射失败保留安全原图，资源/代际错误拒绝对应候选；不新增历史、完成回调或资源 owner。后续 HDR 改动继续通过 raw 多帧累积、paused resize、失败恢复和预算门。

## fallback / route

平台不支持、headroom 回到 SDR、可选 metadata 不可用时走已验证 SDR 导出。颜色语义不明的输入保留现役 SDR route 并标记未兼容；不得默默 reinterpret。非法 format/range/generation 拒绝候选输出，保留安全旧帧。普通映射管线失败不破坏前序 graph current。

## 纠正门

- GPU 自有阶梯覆盖暗部、中灰、白点、超白和多彩高亮；检查有限、单调、颜色/alpha 边界与未开启 HDR 的输出守恒。容差在执行前冻结，不以 8 位截图判断浮点精度。
- 同一输入分别经过 SDR 与 EDR；检查实际 colorspace、format、屏幕 headroom、submission completion、terminal present 和 next-frame；EDR 设备不可用则 C/D 标为 not-run。
- 移屏、headroom 改变、暂停恢复、allocation/encoder 失败必须回到有效 SDR，而不是黑屏或双重映射。
- 2684431262 只作为后续隔离回归输入；官方高亮对照与平台 EDR 验收分别记录，不能用一项代替另一项。

## 退役条件

每阶段完成行为门、颜色权威归入稳定架构、旧输出路径按 route 撤权后归档。未验证的 metadata profile 继续显式禁用，不随 SDR 验收自动解锁。
