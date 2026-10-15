<!-- document-role: historical-evidence -->

# Static child Rope：变换消费与有界扩展

> **历史证据 — 非现役入口**。截止2026-10-16。当前合同归[粒子组件表](../capabilities/particle-component-coverage.md#static-child-rope-design)，执行选序归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。这是一片功能与逻辑修正，不计性能收益。

## 通用语义与准入

旧ChildTransform早已允许独立正Z，实际缺口是Rope builder未消费scale，以及每template最坏8,192段门拒绝合法静态长链。实现沿原准备、simulator、Rope Plan、instance buffer与compositor：node = 已有birthOrigin + scale × localPosition，width = scale.x × localSize；root默认identity，simulator状态不改。linear/spline共享同一Node，不复制细分、UV或join算法。

只扩depth-one static、无nested、无Movement-world operator；原正有限X=Y、三轴1/1024...1024、零angles仍有效，General-world birth origin只加一次。单system沿原Rope Plan 32,768段上限，static构造在原64-system/65,536-particle容量门通过后，按max(maxSegments−8,192,0)扣24,576扩展credit。旧profile零费用，失败不扣额，后继继续尝试；event/nested保旧门。相对旧保守容量包络最多多24,576段，不是同场景修前实际工作量差；新增system仍占原容量并参与作者顺序。

credit只在构造期局部存在，无每帧新allocator、解析或预算扫描。snapshot/restore与退休继续由原systems负责；Rope只取persistent topology，不重建render-only最终sample。取消/完成归还可复用GPU槽；scratch和buffer容量可保留至原owner释放，不能把零粒子或停止后的slot复用说成RAM归零。

## 原始样本与实际画面

只读原3665307769包SHA `e720c8e15967aab51f75f721d49785b5d654e405f090390ababa99e141e430eb`。369层的`particles/workshop/2674194633/getsuga_tenshou.json`引用declaration1/id9 `getsuga.json`，static、scale[1,1,2]、maxcount256、subdivision100，最坏25,755段。两个系统均Rope、General-world/perspective、CP0 follows pointer、Sphere rate32/flags2；Movement-world为false。独立red_fire音频child仍拒绝，不把整个树关闭。

原包/默认属性不改，隔离HOME、静音、同一签名Debug App。四个CP0移动点全部执行；唯一child template/system产生36粒子→909段、18粒子→303段，各有1 batch且bufferFailures=0，随后粒子/线段归零。layer369 GPU聚合61 submitted/60 completed frames、0 failed、122 encoded/120 completed batches，停止surfaces1→0且gpuDrained=true。909个160-byte实例payload为145,440B，仅说明该次几何输入，不是总驻留或额外GPU槽峰值。未测独立CPU/GPU/RAM增量。

原分辨率窗口02/03可见随轨迹移动的暗色细线，人物、背景与既有媒体面板仍在。父系统也是Rope，现有GPU统计按layer聚合，不能从暗线单独归属child颜色、宽度或遮挡；该边界及官方transform/UV/join仍保留。原包平面不能证明独立Z效果，非零Z由自有三维fixture覆盖。ready外部26.388s、原生startup25,669.557ms、总35.400s仅标运行身份，不比较启动收益。初次自有runner误传hover数组，未执行轨迹，已记前置条件无效收据；修成对象后只重跑该项，没有把无效运行记为产品失败。

未参与修法的3743305891原包实际窗口保人物/星体、日期时钟与频谱；ready外部5.595s、原生startup4,774.699ms、总13.702s、exit0、输入稳定、GPU排空。只作当前影响面的独立回归观察，原生面板、长稳切换、HDR与官方视觉parity未扩验。

## 验证与保留

五产品文件Debug build23.480s，4,278输入稳定，Developer ID deep/strict签名通过，之后产品无漂移并复用此构建。最近Rope 5项及Runtime 7项共12/12一次通过；测试审查发现自然退休覆盖不足，仅补新Runtime与最近Sprite退休两项，2/2通过、单harness编译21.470s。没有重跑全矩阵。

行为门用真实JSON/PNG/parser、Metal instance buffer及独立几何期望，覆盖重命名/等价输入、linear/spline/非零Z、size/origin一次、32,766+8,194恰好credit24,576、相邻8,195超1拒绝及后继8,192零费用、原particle容量先拒绝不扣额、双大候选局部失败、event/nested/world-movement/非法scale。有限duration/lifetime Rope在cadence1–3为2/6/2段，4–12的instances/systems/particles全0，均在teardown之前；初始snapshot重播的全生命周期和几何相同。未改GPU slot owner，取消沿用既有门；uploadsMatch只证明上传计数。产品与测试分别独立静态GO。

证据根`.artifacts/tmp/static-child-rope-20261016/`保冻结、build/运行计划、原失败前置条件、两次测试收据、白名单运行事实及必要原字节PNG。退出后清理本轮样本副本、HOME、shader cache与生成代码，压缩原始日志；全局evidence预算满，未重试promote或删除未知材料。连续缓存只保原`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`，Windows VM依用户要求保持运行。精确产物字节与最终Git身份见本地cleanup/commit收据。
