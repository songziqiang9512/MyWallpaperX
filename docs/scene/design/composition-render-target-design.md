<!-- document-role: active-plan -->
<!-- retirementCondition: 组隔离目标、作者顺序与失败事务通过实施门且并入稳定架构后，归档本文并删除对应设计登记。 -->

# D1 — composition 组独立渲染目标

> 复核基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；合并到 `codex/engine-refactor-program` 时重新核对所列 owner。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

composition 子层先在组私有的逻辑 target 内按作者相对顺序完成各自 material/effect，再在组的作者合成位置向父 target 输出一次。非成员不进入组源，成员不重复直接绘制到主帧。子层是否连续、效果数量、样本 ID 均不决定算法。跨 compilation/rendering/resources、触碰 graph/target/compositor 唯一权威，故必须先设计。

## 当前事实与证据

- `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayerSourceRoute.swift:87` 要求完整子树是作者顺序的首个封闭前缀；`:107` 拒绝带 effect/dependency 的子层；`:139` 说明当前先画主 target 再捕获的局限。
- `MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapabilityAdmission.swift:463` 还拒绝子树捕获与非空 dependency ownership 组合；不能只删除其中一个 guard。
- `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetPlan+Extent.swift:16` 已拥有 target extent/format/clear；`SceneGraphRenderTargetLease+Publication.swift:54` 已拥有发布身份与颜色校验。
- 交接给出的 3226487183 层 21/24/32/35、每层 7 effects 是待复现输入；本基线不存在所引 `docs/history/scene/new-sample-gap-analysis.md`，本设计没有运行该样本。

## owner

Compilation 的现役 authored render planner 负责组成员、拓扑、顺序、读写边；Rendering/Targets 的既有 pool/lease 负责分配、generation、回收；effect executor 负责组内 pass；`SceneImageLayerCompositor` 负责唯一最终合成。`SceneCompositionRenderTarget` / `compositionGroupRenderTarget` 只是可能的命名，不授权新增 registry 或第二 compositor。

## 方案设计与选型

选择 **现役 graph 内嵌套 target scope**。扩大主 framebuffer 捕获会夹入非成员，按样本重排无法保持作者语义，另建 renderer 会复制 owner，均不采用。

1. prepare 时从 parent/child identity 得到组成员与作者相对顺序；组在父序列中的位置沿现役 authored order，组内只过滤成员，不按层号排序。嵌套组由内向外准备。明确区分存储数组顺序与合成顺序。
2. 子层 effect 输出写入组 target，组 effect 以该 target 为 source；组 alpha/transform/clip 在对应边界施加一次。跨组引用成为显式依赖边；循环、未定义 feedback、同 target 读写 hazard 拒绝最小依赖闭包，不退回不安全的主帧捕获。
3. 第一阶段 extent 采用**父合成空间的 viewport**，携带逻辑坐标和缩放映射；不采用“最大子层尺寸”，因为旋转、偏移和 effect 外扩会被裁掉。作者明确的组裁剪单独表达。紧致 bounding box 仅在 effect 外扩范围和动态变换包络均可证明时作为后续优化；动态包络变化触发最小 invalidation，不能逐帧重建整图。
4. target 格式继承 [D2](hdr-tonemap-edr-design.md) 的颜色合同；data target 保持作者格式。大小、字节数与嵌套存活峰值进入既有预算。默认透明 clear；显式 history/preserve 才跨帧保留。
5. lease 按 scene generation、surface、logical group、extent、format 和 publication version 隔离。兼容 storage 可复用，但上一 submission 的 GPU 使用及 history pin 未释放前不得覆写。resize/reload 建候选 allocation，提交后撤销旧 generation；teardown 禁止新提交，等待既有 completion 后回收。
6. 同 buffer 内消费者可依既有编码顺序读取候选输出；跨帧可用性沿现役 completion/publication 协议，不把 encode success 当作 completed。组 capture 不额外 present。

## fallback / route

新组路径按完整语义 profile `prefer-generic` 接入，单次只选一个输出 owner。组内普通 effect 失败保留该 effect 输入；组基础捕获失败保留父级 previous-current，不能把尚未合成的成员泄漏到主帧。已有旧路仅在旧 admission 真正成立时回退；非连续/带 effect 的输入不能回落该路。身份、预算、hazard 失败硬拒绝最小 unsafe group。通过正交门后转 `generic-only` 并删旧 subtree 形状路。

## 纠正门

- 自有 fixture：三个子层与两个非成员交错，每子层多 effect；将无关层插入任意位置，组输出不变、无关层顺序不变。嵌套组、半透明组、旋转越界和 effect 外扩均检查 ROI，不能仅验非黑。
- 反例：成员循环、跨组 feedback、extent 溢出、allocation/encoder/GPU 失败、resize 后迟到 completion；旧 publication 不可冒充新 generation，失败组不污染父帧。
- 记录准备次数、实际 App/输入身份、每组 source→effect→publication→terminal compositor→next-frame；普通帧不得新增解析或建图。
- 先定向行为/Metal 门，再 Debug checkpoint 和隔离代表内容；官方固定输入对照前预登记位置/alpha/颜色 ROI 容差。组在外层作者顺序的位置若与官方黑盒不符，修订 order lowering，不能从第三方推定 parity。

## 退役条件

组路径完成上述门、旧 capture 分支和结构预算同批收缩，稳定架构接管 target scope 合同后归档。仅真实样本能打开不足以退役。
