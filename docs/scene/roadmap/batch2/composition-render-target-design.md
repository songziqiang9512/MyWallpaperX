<!-- document-role: active-plan -->
<!-- retirementCondition: 获批composition采集profile完成并移交稳定架构；剩余passthrough/变换裁切有明确后继且无无依据source分派后归档。 -->

# D1 — composition 采集范围、source 与目标生命周期

> 状态：2026-10-04 普通 composition 的 parent 分组、根位置与 copybackground 已经有界官方黑盒裁决并完成实施验收；结果见[执行记录](../../history/d1-composition-authored-order-implementation-2026-10-04.md)。passthrough、特殊变换/裁切及完整官方 parity 未开放。开发顺序只由[兼容路线](../scene-compatibility-roadmap.md)维护。

## 目标合同与判据

恢复作者 composition 的真实输入、效果与最终输出，沿现有 authored → prepared graph/resources → typed frame source → Metal → 唯一 compositor 执行。父子成员、作者根位置与背景模式按已证 profile 决定；素材名、样本、截图和旧实现不能决定视觉算法。跨 compilation/rendering/resource、唯一输出 owner、结构家族与作者语义命中顶层设计门。

## 2026-10-04 有界行为裁决与实施

**直接结果。** 固定 Wallpaper Engine 2.8.42 / wallpaper32 SHA256 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`，自有 256×256 正交场景、512×512 客户区，使用公开 shader 语法自写 RGB 反色且保留 alpha。无效果基线为蓝背景、黄 child、红非 child；同一 input 的 `copybackground` 省略/true 得到黄背景、蓝 child、青非 child，false 得到蓝背景、蓝 child、红非 child。把非 child 从根前移到根后、child 前，该层保持红，背景/child 不变。两次间隔约 0.2 秒的呈现截图与预登记 ROI 一致（不声称连续 GPU 帧），通道容差 4。独立的全屏控制确认 effect off 黄/on 蓝；parent 使数组根前或根后的 child 都进入根效果。原始父子图层坐标经局部 origin 补偿，世界位置相同。证据在本批隔离记录，收尾保存冻结身份与最终结果；错误 shader 构造及 intrinsic texture 尺寸不符的先导尝试不作语义证据。

**批准合同。** 普通 composition 的 parent 后代确为组内容；按作者根位置合成，成员在各自作者相对顺序下先完成，不能把根延后到最后后代的原数组位置。`copybackground` 缺省等于 true；true 在组开始时复制当时 enclosing pass 背景，false 从透明开始。child 关系不排除已显式纳入的背景，也不能使后方非 child 提前进入。parent 的世界变换/可见性仍归原 owner。原“parent 只决定变换”的候选及“缺省 false、所有组透明”的旧假设被反例排除；保留分组，撤掉无依据 prefix 优化与 parent-before-child 限制。

**实现与取舍。** 沿现有 SourceRoute/RuntimePlanner 准备一次确定的组成员与有效执行顺序；同一顺序同时用于 graph preparation 与实际 layer encode。不在普通帧重建 parent 闭包或另建 scheduler。组纹理仍由既有 pool 预留/pin，背景复制只在真正开始写入该组时发生，不能在帧准入阶段提前复制空主帧。copy/clear 后准备与实际采样使用同一 target；嵌套组复制自己的 enclosing pass，完成后只合成一次。拒绝只改缺省值或放开 guard：现有透明 clear 与末后代 trigger 会继续取错源/遮住后层。动态 topology 使用现役变更/缓存边界，不能把静态计划错误复用于改变后的关系。

**失败与退出。** source allocation/generation/hazard/command completion 继续由既有 pool/coordinator 裁决。局部 effect 失败保持安全组输入/父输出；不增加组 history、fallback registry 或第二 compositor。无 effect、空组、copybackground=false、子层 effect、嵌套、交错非 child、root 在 child 前后均进入相称反例；未知 passthrough 与特殊 transform/clip 不据此宣称支持。

**验收与停止。** 自有 parser→plan→GPU→最终 App 输出同时验证三色 ROI、同帧/后帧、组外健康层与 clear/resize/completion；Debug build、最近回归与独立只读审查通过后按职责提交。修前/修后截图证明背景由漏处理变为入效果、显式 true 由漏效果变为执行、后方非 child 不再被错误覆盖。此 profile 完成即停止扩展，未证模式另列后续，不以更多静态报告代替代码。多 sibling/嵌套是项目一致性推广及实施回归，不冒充本组官方逐项对照。

## 现有资源合同与历史依据

资源/source 窄片已经独立实施：compositionGroup key/分配一致，exact extent，source 在 graph preparation 前预留并 pin，准备、写入、采样是同一有效 generation 的纹理。GPU completion/cancel 释放、resize 在飞占用、无历史的透明初始化和同帧保留由[架构§3.3](../../architecture/runtime-architecture.md#33-保留事务安全不扩大视觉失败半径)接管。本次改变输入内容与顺序，不重建资源系统。旧反例、首次错源与实际 App 修复见[执行记录](../../history/d1-composition-source-implementation-2026-10-02.md)。

[首轮成员实验](../../history/d1-composition-membership-attempt-2026-10-02.md)未获得有效效果启闭正控制，不能裁决成员；本轮有效控制补上这一缺口。[经审查的中性合同](../../history/d1-composition-neutral-contract-2026-10-02.md)提供字段存在性、source/target 与生命周期候选，不作为官方语义或代码来源。官方[RGB composition 说明](https://docs.wallpaperengine.io/en/scene/rgb/introduction.html#extra-notes-on-composition-layers)支持采集先前场景内容的方向，具体父子/flag由本轮自有黑盒区分。

## 尚未证明与退役

本轮官方直接覆盖单个 parent child、根前后数组位置、一个非 child 前后移动、copybackground 三态和空 child 组；没有证明所有 transform/clip、passthrough、alpha 混合或动态 topology 与官方等价。used-input 完整哈希属于运行后 guest 收据，不能回填成事前全输入冻结；Scene/fragment 和窗口身份在实际捕获时登记。私有资源仅由官方客户端正常加载，不读取实现表达；自写片段与项目算法独立。

有界实现、真实正反例及独审完成后，将稳定输入/顺序/失败合同交回架构，结果只保存在运行证据。剩余模式保留明确 unknown 和可证伪后继，不能从局部 PASS 宣称 Scene 全兼容，也不能永久保留已证错误的 prefix/末后代 route。
