<!-- document-role: active-plan -->
<!-- retirementCondition: 材质受光和各可选光照子能力分别通过合同门并进入稳定架构后归档，未完成 profile 保持明确准入限制。 -->

# D3 — 2D 材质光照、PBR 与阴影

> 复核基线：2026-10-02（首片输入/坐标合同补全），原设计基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；已合入 `codex/engine-refactor-program`；实施时按其最新代码重新核对所列 owner，以下行号仍指向原设计基线。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

只有作者启用 lighting/reflection 的 image material 接收光照；plain image 不因场景存在灯光而改变。lpoint/lspot/ltube 的动态状态由统一 light snapshot 传至材质 producer，再进入既有 effect/geometry/compositor。跨 material frontend、光照、资源与 graph，须先定义唯一 light/material 权威。

五判据：横切多个 owner 或主链节点=是；触碰唯一权威合同=是；用户可见且难逆的 API/数据/发布合同=否；触碰机器冻结结构家族=是；依赖官方或平台外部证据=是。

## 当前事实与证据

- `docs/scene/semantics/coverage-ledger.md:1289` 将 2D PBR maps 列为 L0，`:1290` 区分 standalone lspot 与 material interaction，`:1292` 将通用 shadow/reflection/light volume 列为 L0。
- `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/SceneLightSnapshot.swift:5` 已定义共享 snapshot；`:6` 上限为四灯，`:31` 已含 directional/point/spot；`:68` 读取 typed dynamic intensity，`:121` 从作者执行顺序筛选灯。
- 交接的 `E-2026-09-28-POINT-LIGHT-ROI` 在此基线未找到，不能据此声称当前 2D 材质已受光；既有静态模型 consumer 与此设计分开验收。
- [官方 Lighting & Reflections](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html) 公开规定 image material 的启用开关及 normal/metallic/roughness 等映射方向（2026-10-01 复核），不提供私有 shading 算法。

2026-10-02 首片补证的来源边界：

- `official-public-contract`：再次读取上述官方页面，材料开关决定 receiver、normal map 提供深度观感、light 数量最多四个。页面未规定缺 normal 必須硬拒绝，也未公开序列化键或 shading 数学；flat-normal fallback 是本设计的项目策略，不能写成官方像素结论。
- `authored-corpus-observation`：只读合法 Scene 包中的 JSON，`2815826216/materials/98367037_p5.json` 为 `genericimage2 + LIGHTING=1`、单 albedo；`3662790108/materials/sun-4.json`、同包 `sun-1.json` 与 `3437487219/materials/Universe.json` 为 `genericimage4 + LIGHTING=1`。启用键位于 material pass，不能只检查 `objects[].instance`；本轮未读取任何私有 shader/算法。以上证明作者数据可达性，不证明 PBR 或官方显示结果。
- `MyWallpaperX-strategy`：首片采用世界空间距离衰减、法线与入射方向夹角及 spot 锥体权重的有界漫反射，保留 albedo、环境光、光色和强度各自的职责，仅为独立项目实现；reflection/PBR/emissive/shadow/ltube 保持后继 profile。只有灯位置的真实 Z 参与 N·L，不能用固定抬升常量掩盖坐标问题。共享 snapshot 保留作者明确 black ambient，纠正原 `SceneLightSnapshot.make` 在无灯时将显式 zero 升成 white 的产生者错误；ambient/skylight 均缺省时保留既有兼容默认，3D 默认规则尚未取证，不因本片扩大解释。`LIGHTING=0` 图层仍使用原 unlit producer。

## owner

Compilation/Material 与 ShaderFrontend 归一化 authored material feature 和 slots；Resources 沿唯一 texture/publication 提供颜色或 data；SceneLightSnapshot 是帧灯光唯一输入；image material producer 消费它。阴影/反射仅是既有 graph 的资源与 pass。`SceneLitMaterial`、`SceneShadowMap`、`SceneLightVolume` 不代表新增 renderer。

## 方案设计与选型

选择**forward material lighting + graph shadow target**。全屏后处理光照缺少每材质法线与接收开关；另建 deferred renderer 会扩大 G-buffer 与透明排序职责，第一阶段不采用。屏幕空间阴影不能表达离屏投影者，不能作为通用阴影默认。

1. prepare 为 material 建立 bounded feature profile：lighting enabled、reflection enabled、normal、roughness、metalness、emissive 与可用遮挡数据。首片由 `passes[].combos.LIGHTING == 1` 的内建 `genericimage2/4` 材质默认值启用，layer instance 同键显式值覆盖；内建身份与 ShaderContract 的 source 分类共享 owner。自定义 authored shader 沿既有 frontend 执行，不叠加内置光照，多 pass/未知 tier 不猜测。slot 存在不自动启用功能。
2. albedo/emissive 使用明确颜色解码；normal/roughness/metalness 为 data，禁止 sRGB decode。缺省 normal 使用项目平面法线；其余缺省值仅在公开声明/合法 authored 数据可确定时开放，不猜私有打包通道。
3. 光照在 base material producer 完成、layer effects 之前执行。graph claim 使用其 source capture；无 effects 的普通 receiver 使用同一材质 fragment，经现役 compositor 的 offscreen source capture/target 再进入唯一最终合成，不建立假 effect 或第二 graph。世界位置按 unit quad 的上方对应纹理首行约定与完整 model matrix 计算；世界距离/spot 锥角不随矩形尺寸、旋转或非均匀 scale 扭曲，法线用同帧逆转置 basis。缺 map 与中性 map 均计算同一 N·L，不添加虚构 z lift；法线图暂仅接受已有 data-purpose semantic registry，任意作者 normal 槽仍 unknown。typed light snapshot 由 renderer 每帧只发布一次，所有 consumer 使用同一份；lit PSO 在 launch preparation 完成，普通帧只读。Puppet/mesh 的变形后世界位置不能由 source atlas unit quad 推出，首片对此局部保持 unlit 并报告 `receiver-geometry-unsupported`，退役门为 geometry owner 提供同帧变形后 receiver mapping。结果仍保留原 alpha/几何，HDR 接 [D2](hdr-tonemap-edr-design.md)。不把 standalone 可见光束当受光证据。
4. 首片为已有 point/spot 的无阴影受光。ltube 必须先补公开/自有行为 profile，不能伪装成一个 point；灯数量沿既有预算，超额灯的选择遵守作者顺序并记录 bounded 限制。
5. 阴影采用显式 caster/receiver 与 graph-owned depth/visibility target。首个阴影 profile 限一个 spot shadow、一个不超过 2048×2048 的 depth target，实际字节按格式计入现役 resident budget；point 全向和 ltube 阴影暂不开放，不把一张平面图伪装成全向遮挡。这些是项目实施预算，不是官方上限，prepare 时验证峰值并允许按用户质量选更低分辨率；没有可证明的深度/遮挡输入时关闭该 material 的 shadow 分量，不从图片颜色推断高度。
6. Reflection 与 light volume 分为后继独立 profile：前者复用 graph/camera/target，后者仍由现役独立几何绘制但可消费相同遮挡 publication；两者不由受光上线自动准入。

## fallback / route

按 feature 精确降级：normal map 不可用时可走已声明 flat-normal；可选 shadow/reflection 缺失保留已验证直射与 base material；完整 lighting shader 失败保留安全 unlit base current，并报告局部 miss。非法 GPU range、预算或 stale light/target hard reject 最小 unsafe unit。`prefer-generic` 只选一条 material 输出，完成后 `generic-only`。

## 纠正门

- 同场景同灯：receiver 有响应，未启用 receiver 逐像素保持；移动灯、旋转法线、强度归零/恢复、四灯到超额及不同作者顺序分别检查 ROI。
- 矩形 200×100/80×320、旋转和上下灯位使用独立世界坐标 oracle；缺 map 与中性 map 逐像素相等，正对平面的 -Z spot 必须可执行。无 effects receiver 与 claimed effects receiver 都须从作者 pass 键贯穿最终合成。
- 法线 data 错按 sRGB、光强被应用两次、透明边缘颜色泄漏均须有失败反例。point/spot/ltube 不以一个样本互相代验。
- 阴影测试移动 caster、离屏 caster、无深度、target resize、GPU failure；只影响 shadow 分量且下一帧恢复；reflection/volume 各自另设 ROI。
- 每个 profile 记录输入/执行身份、light snapshot generation、GPU completion、publication、terminal compositor 与 next-frame；官方对照未做时只记项目有界实现。

## 退役条件

稳定架构接管 material/light/target 边界，已开放 profile 验收且旧重复受光路径撤权后归档。设计批准不等于 PBR、shadow、reflection、ltube 已支持。
