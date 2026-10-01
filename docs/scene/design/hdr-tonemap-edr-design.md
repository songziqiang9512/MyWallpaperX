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

SDR 默认映射的具体参数在第一实施片以自有阶梯/彩色高亮 fixture 和公开观测冻结，随后变更需重跑相同证据。作者/用户未提供曝光时不做自动逐帧曝光，避免亮度泵动。alpha 不作 tone map；在确定的直通/预乘边界处理零 alpha，防止边缘变暗。

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
