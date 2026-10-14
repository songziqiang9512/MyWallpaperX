<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。稳定合同归[粒子M14](../capabilities/particle-component-coverage.md#m14-sprite-空间相机与逐层深度)，剩余工作归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# Sprite 世界空间、相机与深度（2026-10-11）

## 修复与边界

3248220186 原包三个可见普通 Sprite 因 world + depth/cull 组合被拒，主体黑屏。现有 Metal pipeline 已有对应状态，问题在 compiler 准入及 native Scene 相机消费：General perspective bit 不能替代 Scene 默认相机。只扩现准备期 profile，沿原 CameraFrame → uniforms → MetalPipeline → compositor 修正 model Y、billboard/local basis、UV与剔除一致性；没有增加 renderer、资源池、相机、clock 或输出 owner。

先行设计写入现粒子合同后实施，快照留证据根；完成后撤掉临时 design 登记，现合同拥有稳定结果。独立审查发现第一候选按单一 isSprite 标记扩大了无depth的复杂 profile 坐标行为，已移除该 DrawBatch 字段及 root/child 两处推导。最终由唯一 compiler 的同一已验证 profile 发布 typed usesSceneCamera；未知、复杂、多renderer、REFRACT 等无depth旧行为保持。最终四产品 diff SHA256 `b98eb9db752d7b5a5d7efdbe9bccbc795437af80a581c0238afec44ae3218008`，基线 `d609f128785524c841e97ab0ca47db4077a174d4`；主工作区三份 U06 编译在途文件未纳入。

只覆盖 single default/screen-facing Sprite、已知 renderer world bit、普通 genericparticle、现有 blend/static overbright。depth 仍逐层 clear=1/lessEqual，非 Scene 共享遮挡。其他 native geometry、Position oscillation 等辅助方向域及跨层透明排序未由本片证明。目标的两个球层仍有 vortex/audio/control-point 等已知 bounded/unsupported 诊断，不把恢复几何记作模拟行为全部对齐。

## 验证与画面

- 有效旧基线红门使用 git show 固定产品依赖与58组 author profile，5 tests产生64个失败子例（36准入、12 native默认深度、8剔除、8纹理方向），0 error/skip；初次混合身份的试跑无效，不作为基线。
- 候选 assets/rendering 45 tests、0 skip通过，包含83组 loader profile、8组实际 CameraFrame uniforms→Metal 的 camera×space反例，覆盖独立test/write、near/far、正反面及非对称纹理。相机责任从旧超长测试窄提取为6门，共用同一编译与GPU读回；提取后仍45项、0 skip，全部JSON读回与提取前一致。新文件均低于1000行；旧rendering测试由HEAD的2999降至2699行，剩余存量超长债务未在本片全面重构。
- 相机18项、继承视差/粒子affine 14项通过；runtime/主帧shadow/snapshot共65项完成，其中55通过、10因缺少既有隔离真实样本缓存而跳过。Debug build、结构、设计、Scene防御及产品代码行数门通过。这里没有全库或Release验收。
- 签名Debug App executable SHA256 `1a91ec4035b245a435b7d87f598734f2f5a7ce59f60516c3ce07f23b297fc093`，debug dylib `e574bbe9256f233e97f64390f4a128100984fb30da477994fb026153fc3b528c`，CDHash `4006c50516d2c411d66be72332741bd9213adb94`。benchmark在隔离副本运行两原包，签名前后核验通过；不是普通App选择→桌面入口或系统音源验收。

| 原包 | 解锁后实际结果 | 未关闭项 |
|---|---|---|
| 3248220186 | 三visible层2157/14/72均加载，不再unsupportedRenderState；14/72持续非空，画面由黑变蓝紫粒子球。测量窗299 GPU completion / 298 presentation / 0 GPU失败，正常排空exit0 | 整包benchmark仍FAIL：101#179 GodRays material-variant-envelope-frontend导致effect失败与局部passthrough两条报告；第三条utility不足独立来自工具用prepared计划2（101/265）对实际成功1（101），265默认hidden/dormant且不在execution expected，不能算GodRays后果或第二个视觉故障。工具计数口径待修。光束缺失、运动形态、密度/大小/亮度与官方差异仍需修；不能称2157已实际发射。 |
| 3792817546 | 原screen深度粒子127持续出粒子；298 GPU completion / 297 presentation / 0 GPU失败，benchmark PASS，正常排空exit0 | 仅此profile及本次隔离窗口证据，不证明全交互、长稳或时钟布局。 |

两个约5秒预热后测量窗（均不满足runner稳态资格）的present p95均16.667ms，仅说明本次连续呈现，不构成性能优化结论。第一轮锁屏只能取得GPU与截图，present=0；后续用户解锁再跑取得上表回执，不改写前轮失败。对照用户官方 `截屏2026-10-11 14.51.37.png`：粒子球应存在，仍缺放射光束，形态/强度有差异；不同viewport、音源、时刻不足以逐像素比较。没有消费私有实现表达。

## 收据、剩余方向与产物

本批准入/相机/深度组合最小结果已落入真实运行链；适用相同作者profile的通用能力，但本次只证明一个新增受益原包。3695791724可作后继world/perspective camera回归，旧版本已实际encoded，不能算本批新增准入受益；U02几份光束为旧普通flags0/depth disabled，不可借本批关闭。下一方向优先共享effect输入/编译首错，GodRays及multistage_wave按各自实际profile查原owner；不能因名字相同重写一整族。

证据根为 `.artifacts/tmp/particle-world-depth-20261011`：源码/App/样本身份、最终report/log、必要截图、红绿与独审收据。真实样本原件只读；runner已清理staged App/HOME，源副本和重复shader/截图在提取后清理。只保留必要压缩原始证据和最终截图。连续迭代复用 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData` 一份缓存。收尾只读复核上一N02的VM已进入suspended；本批未强制重置或操作其壁纸会话。已将原始非PNG结果逐文件SHA复核后压缩，保留两张最终原始PNG及注明来源SHA的精简report；重复截图、原包副本与首次输出已清理。最小提取28,864,948字节低于单包32 MiB，仍被全局1 GiB预算拒绝，prune无可清条目；未提高预算或删除未知证据，约30 MiB必要证据暂留原根。

## 后继：粒子排序成本短筛（2026-10-14）

[三臂局部对照](../../../.artifacts/tmp/particle-order-screen-20261014/paired-summary.json)比较现索引排序、直接稳定排序完整实例、仅有限且已排序时跳过索引排序；三组交替配对显示直接排序在逆序/交错输入回退，ordered候选只在已排序输入有局部收益（16384个有序透明粒子配对中位下降34.4971%）。这是dt0重建owner和完整实例比较，不是实际整帧或稳态收益；原NaN比较器回退未改，不认领非有限深度语义修复。

沿[冻结条件](../../../.artifacts/tmp/particle-order-screen-20261014/proof/app-screen-spec.json)，App `86b320df…`/候选`5813ba61…`分别运行真实304、3024×1964、60FPS、30秒预热后的约64.5秒测量窗，静音且关闭execution observations。[单对结果](../../../.artifacts/tmp/particle-order-screen-20261014/proof/app-screen-result.json)为整进程CPU时间率816.521→834.294ms/s（上升2.1767%），particle advance p50同为1.246ms；GPU p50为10.048→10.540ms，单对不作归因或验收。两份报告均保原`particle loading incomplete` FAIL。

未达到整体CPU继续门，停止扩测并撤回ordered产品候选，恢复源码SHA `b48c83309824dd7a57d6f62b55c768287e3b21b761ac567f6fa8afd5b44750cc`，保[撤回patch](../../../.artifacts/tmp/particle-order-screen-20261014/proof/rejected-ordered.patch)与原始证据。不以局部sorted收益认领用户可见改善，也不关闭粒子相机/透明排序或整体性能专项；当前下一批归性能卡。
