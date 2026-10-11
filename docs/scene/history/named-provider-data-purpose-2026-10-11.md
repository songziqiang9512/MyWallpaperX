<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。职责归[运行架构](../architecture/runtime-architecture.md)，余项与顺序归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。
# 命名数据纹理的材质用途（2026-10-11）

基线059c580a（隔离树等价237925a3）。3708363772的hidden solid804已发布64×1 data，但image705/effect560把slot1列为PMA颜色边界，finalizer拒绝并透传。作者仅指定一个外层named输入，无默认纹理或graph alias；不是缺少另一套频谱算法。

沿原selectedTexturePurposes → launch envelope → frame key → artifact准备color/data变体。只扩已证明外层、单一候选、regular primary named且无default/graph alias的槽；同层、无context、多候选和旧mixed优先级不改。frame经现有完整publication验证后选预编译key，data四通道保持，颜色转换仍由原ABI负责。条件关闭的槽按readinessMask移出用途key，避免缺席输入选不到inactive Program。没有新增资源、编译器或合成owner，也没有绕过颜色守卫。

## 实际结果及边界

同一最终Debug App分别运行原包的隔离副本，静音和受控PCM均exit0并完成GPU排空。首帧和后帧705/560均materialNodes=1、rejectedNodes=0、GPU completed、compositorConsumed=true，dependencyProviders=804。PCM截图中封面下沿白色起伏及底部频谱曲线出现；静音截图无起伏。PCM经过现有capture-service处理与SceneAudioSpectrumInbox，但不是系统音频tap或真实播放器验收。

原包SHA `be9f6bc7c3a4c55443fc54f3ab009ab2f68850d98f0ddbe0b61061bbebe06248`。App主程序SHA `65ba569212b55e6d073ce88caa1eed6b4075a4781ff4b8ce1ec8ec900c1e0989`，dylib `42b8facb5d923a6befcc9fc25534899e84d07376e25c3dd7c26e0e617cd8dd05`。内部Host运行不代表普通桌面入口、系统音源、长期稳定或官方parity；官方截图是静音状态且viewport不同。封面边缘叠影、221.visibility准备期invalidSource仍开放，不把两条目标链闭合写成整样本100%。

9项颜色ABI测试通过：真实launch/finalizer/Program纹理及uniform上传、两条既有编译路线的Metal读回，覆盖color一次转换、data四通道、用途切换缓存不重编译、pending/unavailable/absent/missing、ready恢复、默认来源与graph alias回退、self/无context及条件关闭。跨epoch由实际publication overlay拒绝；不为人为绕过owner构造的快照再加finalizer防线。同一早期harness配基线源时旧4项保持、新行为出现10个失败断言；不能将其扩大为后加所有反例均跑过基线。

补跑原finalizer 33项为30通过、3失败，门未全绿。将全部产品源固定为237925a3后重跑同3项仍失败；共享harness完整27字段结果与候选一致。四个旧positive布尔断言，以及straightAlbedo graph/self用途应拒绝的旧期待均未因本批改变；归因资料在`finalizer-comparison/comparison.json`。先核这些旧断言与现役颜色合同，不能直接改期望或归作本批回归。Debug构建、52项文档/结构测试及代码、依赖、防御、设计、文档门通过。

独立审查对最终8份产品与2份测试未发现P1/P2；代码/测试diff SHA `d4c097f77fcd301a20eb552cea34c83005a9f607a3256327f4b1c81ee1a9bb73`。本机证据在`.artifacts/tmp/named-data-purpose-20261011/`；测试收据在隔离树`.artifacts/tmp/regular-named-data-20261011/`。最终门、文档复审和清理结果由本批收据绑定。下一片优先复验2877855240六段Skew缺失尺寸合同，复用原纹理尺寸投影；不猜g_TextureReductionScale=1。

本批清理约623 MB样本副本/临时HOME及重复截图、生成shader；保留约14 MB必要证据与一份连续构建缓存。证据工具因既有总缓存预算已满拒绝晋升，未提高预算或删除未知材料，临时证据根暂留待后续治理。
