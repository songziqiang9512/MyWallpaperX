<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->
<!-- retirementCondition: shared与owned目标在实际格式下唯一计费，真实HDR反例、预算边界和生命周期门通过独审后移交稳定资源合同并退役窄登记。 -->

# RF11 — shared graph 工作纹理的格式计费纠正

> **历史证据 — 非现役入口**。

状态：已实施并通过独立产品终审，窄登记退役；本文保留批准时的设计依据，现役合同由[架构§3.3](../../scene/design/runtime-architecture.md#33-保留事务安全不扩大视觉失败半径)拥有，执行事实见[本批记录](rf11-shared-hdr-target-budget-implementation-2026-10-02.md)。基线`006390390bda2d4a5940aa242cc3f16ca734e684`。本片属于[RF11工作卡](../../scene/design/reference-evidence-implementation-cards.md#rf11-frame-target-budget)，承接[F3发现的完整场景首帧失败](d3-pbr-map-emission-implementation-2026-10-02.md)，不是重新定义HDR输出。

## 目标合同

实际格式与实际物理owner决定逻辑预算。owned graph拥有自己的工作pair和作者FBO；shared graph仅拥有自己的FBO，其工作pair由共享池按原key唯一计费。RGBA16F与8位格式遵守同一规则，不能让shared graph继续计入已转交共享池的纹理，也不能少计history或作者FBO。

本片修复准备期计费错误，保留原预算、画质、作者顺序、资源身份、复用范围与唯一compositor。不是通过丢弃效果、缩放分辨率或增大配额使场景放行；不引入跨graph新别名机制。

## 当前事实与证据

代码路径以下均相对`MyWallpaperX/Core/SteamWorkshopScene/`，行号对应基线：

- `Runtime/Frame/SceneRenderDescriptor.swift:46–48`将已启用HDR映射到rgba16f；`Rendering/Targets/SceneGraphRenderTargetFormat.swift:7–21`已有统一逻辑格式字节定义。3662790108原scene entry SHA`faea17adcce6b09b40c1a722c08b53bc4f3588c3189873986c754517a9500cc5`的general.hdr为true（只读作者JSON）。
- `Rendering/Targets/SceneLayerGraphTargetPlan.swift:287–305`已按每槽实际格式求总计费，`:317–324`却用旧格式固定成本扣除shared pair。HDR因此残留不存在于该graph owner下的工作纹理费用。`:104–112`另有同类固定成本getter，无产品调用，仅一条旧测试读取。
- `Rendering/Targets/SceneOffscreenTexturePool.swift:46–48,370–384`从pool实际格式计算目标成本；`SceneOffscreenTexturePool+PersistentGraphTargets.swift:402–425`按共享pair key取得待驻留成本，再由`:304–327`交同一allocation cache整帧准入。共享池仍是pair的唯一计费/分配owner。
- `Rendering/Targets/ScenePersistentGraphTargetAllocator.swift:87–119`在shared模式实际只分配非pair槽，pair使用reservation提供的共享纹理；因此当前plan的多计费不对应实际分配。
- F3冻结新旧App在同作者输入、单surface配置、同宿主显示环境和预算下均出现首帧拒绝：首次required805390384、budget794569728、residents29，随后required801766144、residents26，无完成帧。全包未生成PNG，实际drawable尺寸未直接记录；不能将此共同失败归为F3新增回归。这里只证明预算阻断，计费错误对其实际影响须修复后同输入验证。

## owner与方案

`SceneLayerGraphTargetPlan.make`拥有每graph准备期布局与逻辑成本。沿它已有的逐槽成本遍历，仅累加本graph实际拥有的槽；shared pair不进入私有成本运算，真实pair的溢出与预算仍在pool分配边界拒绝。history仍只计作者历史槽。删除没有产品consumer的重复getter，并将旧测试迁移为实际plan/cache预算行为断言。产品写入初始范围仅`Rendering/Targets/SceneLayerGraphTargetPlan.swift`；若真实验证发现其他owner错误，先给出事实并修订设计，不顺手扩大。

选该方案，是因为它让实际owner和格式共同决定成本，消除固定格式假设与重复推导，也不计算不存在的私有pair费用。备选“按格式另算一套pair成本”可以改掉眼前常量，但继续保留两条易漂移计费路径；不选。提高预算、降为8位格式、无依据扩大复用或关闭效果均不能纠正计费合同，不选。

五判据：①跨graph plan与共享pool/allocator的归属边界、②触唯一resource计费/lifecycle准入，命中设计前置；③不改用户持久化，④不新增冻结结构家族，⑤本片不需要新外部行为或私有算法。设计批准前只做自有反例与只读诊断。

## fallback与不变量

保持现有非法extent、溢出、history闭包、stale identity、in-flight pin、generation和预算超限拒绝。只消除重复计费；真正超过原预算的需求仍不能绑定。正常帧不新增资源扫描、哈希或诊断。准备期输入已决定格式、pair槽与owner，不新增无产生者guard或第二预算表。

## 纠正门

1. 使用真实Swift plan构造行为反例：无作者FBO的shared HDR graph不应形成私有resident费用；同等8位格式已正确，owned仍完整计费。先保存旧实现FAIL，不能用Python模拟代替产品结果。
2. 自有不同尺寸、两种格式、owned/shared、普通FBO/history组合，核原预算恰好足够/少一点、整数溢出；测试输入/结果，不锁源码写法。多个graph共享同一pair时只由pool计一次，不同尺寸仍按既有key分开。
3. 实际Metal allocation、preflight、reserve/commit、GPU completion和下一帧；保持history保全、拒绝时不发布、不同generation及迟到completion安全。复用现役target/pool harness，仅补缺失格式组合。
4. checkpoint Debug构建与实际失败原包隔离回归，记录旧/新相同输入及预算、completed/publication/terminal/next-frame、可见ROI和剩余首断点。不得以budget放行或首次非黑单独声称完整Scene兼容或性能完成。
5. 独立终审核对精确diff、执行身份、guard与防御面；完成后窄提交并说明下一职责。三份受保护Scene权威与并行`script/scene_source_layout.json`保持只读。

## 退役条件

shared/owned与格式计费合同经实际反例和资源门验证，真实HDR场景不再被本错误阻断，独审完成后移交[稳定架构](../../scene/design/runtime-architecture.md)，删除对应窄登记。本片不退休仍存在的真实超预算、其它画面缺口或完整Scene一致性责任；后继仍由唯一路线决定。
