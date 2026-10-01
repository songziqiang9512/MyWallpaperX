<!-- document-role: active-plan -->
<!-- retirementCondition: SDR 映射与可选 EDR 的目标合同并入稳定输出架构且通过各自显示验收后归档，删除设计登记。 -->

# D2 — Scene HDR、tone mapping 与 EDR 输出

> 复核基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；已合入 `codex/engine-refactor-program`；实施时按其最新代码重新核对所列 owner，以下行号仍指向原设计基线。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

保留作者高亮的中间精度，在唯一 terminal compositor 的输出阶段做一次有明确颜色语义的显示映射：先完成 SDR 高亮滚降，再开放可选 EDR。跨 target、Bloom、surface 和显示状态 owner，触及唯一输出与外部平台合同。

五判据：横切多个 owner 或主链节点=是；触碰唯一权威合同=是；用户可见且难逆的 API/数据/发布合同=否；触碰机器冻结结构家族=否；依赖官方或平台外部证据=是。

## 当前事实与证据

- [E-2026-09-27-SCENE-COLOR-PRECISION](../semantics/runtime-evidence-current.md#e-2026-09-27-scene-color-precision)（该文件 `:477`）：RGBA16F 已贯穿 graph 到 CAMetalLayer；仍是 display-referred sRGB，没有完整 HDR Bloom/tone mapping 或 EDR。
- `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift:156` 设置 pixelFormat，`:159` 设置 sRGB。格式精度不是 scene-linear 语义证据。
- 交接的静态取证 §7.4 是音频方向，不可用作 HDR 曲线依据；本设计不消费私有曲线、公式或常量。
- [官方 Bloom](https://docs.wallpaperengine.io/en/scene/effects/bloom.html) 公开区分标准与 Ultra HDR Bloom；不公开本项目所需的全部显示映射参数。
- [Apple 自行 tone mapping](https://developer.apple.com/documentation/metal/performing-your-own-tone-mapping) 支持 extended-linear color space、RGBA16Float、`wantsExtendedDynamicRangeContent` 与当前屏幕 headroom；这是 macOS 呈现合同，不是 WE 数值算法。公开资料复核日为 2026-10-01。

## owner

现役 descriptor/preparation 决定颜色内容类型与 storage；Bloom 在同一图内处理；terminal compositor 拥有显示变换；SceneMetalView 只配置 surface 和接收按屏幕发布的显示能力。禁止每个 layer 自做 tone map 或另开 HDR 输出器。

## 方案设计与选型

选择**自有显式输出映射**；直接 clamp 会丢失高亮层次，只换 16F 不能解决显示范围，未经确认的系统 metadata 可能重复映射。

| 阶段 | 输入及输出合同 | 开放边界 |
|---|---|---|
| A：颜色语义确认 | 明确纹理 decode、shader 输出、blend、Bloom 的 transfer/primaries/alpha；沿当前 content/publication 表达 | 不得仅因 target=16F 就 reinterpret 为 linear |
| B：SDR | HDR scene color → 公共 knee/shoulder 映射 → SDR transfer/terminal attachment | 非 HDR 既有 SDR 路径数值守恒；默认先交付此阶段 |
| C：EDR | 相同 HDR scene color → 当前 headroom 的扩展线性显示值 → RGBA16F extended-linear surface | 逐显示器能力、系统开关和用户选择共同允许时开放 |
| D：可选 metadata | 仅存在真实且格式匹配的内容元数据时评估系统映射 | 当前选择自有映射时不叠加系统 tone map；不可从截图猜 metadata |

颜色转换的位置先由 A 的合成 fixture 固定，不能简单给现有 display-referred 输出再套 gamma。HDR Bloom 在输出映射前完成；normal/roughness 等 data 不进入颜色变换。toneMappingKnee 为项目参数概念；设计规定连续、单调、有限、保留中性灰与高亮顺序，不规定或声称官方私有曲线。

阶段 B 第一片冻结项目自有 rational shoulder，作用域为 `general.hdr=true` 且 `camera.clearEnabled=true` 的已合成 display-referred sRGB 数值；不把浮点格式解释为 scene-linear，也不添加 gamma。非 HDR 场景整条映射 route 不创建、不编码，不要求 HDR 场景中的整个 `[0,1]` 区间恒等。冻结 knee 为 0.5：非正有限值归零，暗部不变，高于 knee 后连续、单调地压缩进入 SDR 范围，且连接处斜率连续；浮点舍入允许端点 1。中性灰仍中性，逐通道处理不串色，但不声明保持高亮色相/饱和度。NaN、正负 infinity 全部输出 0，CPU/MSL 一致。输入 1、1.5、3、5、12 的输出分别约 0.75、0.8333、0.9167、0.95、0.9792，必须在 SDR 区间内仍可分辨；此前“`[0,1]` 恒等、超白仍大于 1”的候选会在 SDR 裁成同白，不满足阶段 B。此处参数与映射行为是项目策略，不来自或声称等于官方曲线。

alpha 不作 tone map。仅在作者启用每帧清底时，terminal 合成从 `SceneMetalRenderer+ClearColor.sceneClearColor` 的 alpha=1 清底；阶段 B 的可见颜色合同限定该不透明终端，按已合成 RGB 映射并原样写回 alpha。`f(0)=0` 不能证明非线性映射保持预乘 RGB/alpha 关系，作者关闭清底时，主 pass 使用 load，保留像素可能已被上一帧映射；RF00 首片因此不创建该profile的映射 owner。后继必须先分离未映射 scene color 历史与显示输出，再以多帧反例验收；本段只批准清底首片。本片不开放透明终端或逐 layer 映射；透明输出需先确定 straight/premultiplied 边界并另行验证。作者/用户未提供曝光时不做自动逐帧曝光，避免亮度泵动。参数变更需重跑同一自有阶梯、灰/彩色、非有限、失败源保持及后续帧恢复 fixture；GPU 容差冻结为 `1/1024`，SDR 高亮相邻差至少 `1/64`，不以实现公式镜像作为唯一 oracle。

surface generation 绑定屏幕、颜色空间、format 与 headroom 状态；屏幕迁移或动态 headroom 变化更新 typed display state，不重编译整图。切换 SDR/EDR 使用已准备输出管线，候选失败前保留旧 surface/output。metadata 不是第一阶段的必需品。

## fallback / route

平台不支持、headroom 回到 SDR、可选 metadata 不可用时走已验证 SDR 映射。颜色语义不明的输入保留现役 SDR route 并标记未兼容；不得默默 reinterpret。非法 format/range/generation 拒绝候选输出，保留安全旧帧。普通映射管线失败不破坏前序 graph current。

## 纠正门

- GPU 自有阶梯覆盖暗部、中灰、白点、超白和多彩高亮；检查有限、单调、颜色/alpha 边界与未开启 HDR 的输出守恒。容差在执行前冻结，不以 8 位截图判断浮点精度。
- 同一输入分别经过 SDR 与 EDR；检查实际 colorspace、format、屏幕 headroom、submission completion、terminal present 和 next-frame；EDR 设备不可用则 C/D 标为 not-run。
- 移屏、headroom 改变、暂停恢复、allocation/encoder 失败必须回到有效 SDR，而不是黑屏或双重映射。
- 2684431262 只作为后续隔离回归输入；官方高亮对照与平台 EDR 验收分别记录，不能用一项代替另一项。

## 退役条件

每阶段完成行为门、颜色权威归入稳定架构、旧输出路径按 route 撤权后归档。未验证的 metadata profile 继续显式禁用，不随 SDR 验收自动解锁。
