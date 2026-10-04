<!-- document-role: active-plan -->
<!-- retirementCondition: 获批composition采集profile完成并移交稳定架构；剩余passthrough/变换裁切有明确后继且无无依据source分派后归档。 -->

# D1 — composition 采集范围、source 与目标生命周期

> 状态：2026-10-04 普通 composition 的 parent 分组、根位置与 copybackground 已经有界官方黑盒裁决并完成实施验收；结果见[执行记录](../../history/d1-composition-authored-order-implementation-2026-10-04.md)。passthrough、特殊变换/裁切及完整官方 parity 未开放。开发顺序只由[兼容路线](../scene-compatibility-roadmap.md)维护。

## 目标合同与判据

恢复作者 composition 的真实输入、效果与最终输出，沿现有 authored → prepared graph/resources → typed frame source → Metal → 唯一 compositor 执行。父子成员、作者根位置与背景模式按已证 profile 决定；素材名、样本、截图和旧实现不能决定视觉算法。跨 compilation/rendering/resource、唯一输出 owner、结构家族与作者语义命中顶层设计门。

## 2026-10-04 有界行为裁决与实施

**已有裁决。** 官方 2.8.42 自有黑盒覆盖 parent child、根前后位置、非 child 前后移动、copybackground 三态与空组，具体结果和身份见上方执行记录。成员随 parent 分组，根按作者位置合成；copybackground 缺省/true 采集当时 enclosing 背景，false 透明。不得恢复 prefix 或末后代触发的旧推断。

**现役链路。** SourceRoute/RuntimePlanner 在 descriptor/topology revision 准备成员和唯一执行顺序，graph preparation 与 encode 共用；组纹理由原 pool 预留/pin，真正写入时才复制 enclosing 背景或 clear，嵌套组仍只合成一次。普通帧不重建 parent 闭包；资源/generation/hazard/completion 延续原裁决，局部效果失败不增加第二套 registry/history/compositor。多 sibling/嵌套属项目一致性推广，尚非官方逐项对照。

## 组合层实时显隐实施决定（2026-10-04）

真实326的时钟与分组开关被热更新准入拒绝，而同场景月亮开关可接受；产品可回退重载，这不是整样本无法显隐的证明。本批使已有合法固定分组在同一窗口内切换，避免为可见性变化重建场景。复用 SourceRoute 对普通 composition 成员的裁决，原 visibility 准入/准备闭包覆盖合法 composition 祖先及后代；无环、唯一身份、父子索引一致仍必需，passthrough、依赖型组与未支持成员仍保留原边界。无子层的背景采集 composition 同样沿既有 source route 准备，不因嵌套而遗漏。初始隐藏的子图、图片及文字进入既有 launch preparation，已准备组保留 capture 计划；无 effect 组仅保留顺序，实际分配、编码和输出仍由当前 typed visibility 集决定。drawable 可读用途在启动时涵盖潜在高级混合层，不能用初始隐藏撤销后续采样所需能力。不新增树、时钟或 compositor owner，不在普通帧重建闭包。

验收包含初始隐藏→显示→隐藏→恢复、嵌套组、子层自身 false、子 effect/文字、健康邻层与静态显隐像素对照，以及畸形层级反例、Debug build 和真实326同输入开关。普通视觉资源失败继续局部降级；非法结构拒绝目标，整键原子准入不拆分。完成此固定分组闭环即收口，不借机扩大 passthrough、变换裁切或官方 parity；启动准备可能增加，实际热更新是否避免重载及画面是否恢复分别验证。

## 现有资源合同与历史依据

资源/source 窄片已经独立实施：compositionGroup key/分配一致，exact extent，source 在 graph preparation 前预留并 pin，准备、写入、采样是同一有效 generation 的纹理。GPU completion/cancel 释放、resize 在飞占用、无历史的透明初始化和同帧保留由[架构§3.3](../../architecture/runtime-architecture.md#33-保留事务安全不扩大视觉失败半径)接管。本次改变输入内容与顺序，不重建资源系统。旧反例、首次错源与实际 App 修复见[执行记录](../../history/d1-composition-source-implementation-2026-10-02.md)。

[首轮成员实验](../../history/d1-composition-membership-attempt-2026-10-02.md)未获得有效效果启闭正控制，不能裁决成员；本轮有效控制补上这一缺口。[经审查的中性合同](../../history/d1-composition-neutral-contract-2026-10-02.md)提供字段存在性、source/target 与生命周期候选，不作为官方语义或代码来源。官方[RGB composition 说明](https://docs.wallpaperengine.io/en/scene/rgb/introduction.html#extra-notes-on-composition-layers)支持采集先前场景内容的方向，具体父子/flag由本轮自有黑盒区分。

## 尚未证明与退役

本轮官方直接覆盖单个 parent child、根前后数组位置、一个非 child 前后移动、copybackground 三态和空 child 组；没有证明所有 transform/clip、passthrough、alpha 混合或动态 topology 与官方等价。used-input 完整哈希属于运行后 guest 收据，不能回填成事前全输入冻结；Scene/fragment 和窗口身份在实际捕获时登记。私有资源仅由官方客户端正常加载，不读取实现表达；自写片段与项目算法独立。

有界实现、真实正反例及独审完成后，将稳定输入/顺序/失败合同交回架构，结果只保存在运行证据。剩余模式保留明确 unknown 和可证伪后继，不能从局部 PASS 宣称 Scene 全兼容，也不能永久保留已证错误的 prefix/末后代 route。
