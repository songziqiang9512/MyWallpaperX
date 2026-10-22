<!-- document-role: stable-contract -->

# Scene 工程宪章

> 北极星：让真实 authored Scene 输入沿一条共享主链，以稳定的帧时间得到正确画面。每次工作都应减少首断点、减少常驻成本，或闭合一个可见合同。

本文只定义目标、边界和评价方式，不规定模型必须采用的步骤、命令、文件模板或任务拆分。实现者应根据当前代码、运行证据和风险自行选择最快的验证路径，并在结果中说明关键判断。

## 主链

```text
authored data → loss-preserving IR → prepared Program/graph/resources
              → typed frame update → Metal encode → unique compositor/output
```

准备结果不限定为纹理。统一主链消费五个有限产品类别：`TextureProduct`、`GeometryProduct`、`SimulationProduct`、`ProviderProduct` 或 `GraphProduct`。类别用于划定 owner、输入和失败边界，不要求一个公共 Swift enum/protocol；不要为了命名类别增加空 wrapper、重复 registry 或跨领域大接口。具体产品共享 identity、时钟、资源 generation、target/publication/completion、rollback 和唯一 compositor。新 profile 必须由 authored 语义和静态预算定义，明确失败半径、fallback 退役条件及实现无关正反证据，禁止按 sample/layer/path/hash 选择算法。

几何产品的采样资源与最终层输出必须分开：纹理/effect graph 在资源自身坐标中完成，graph-final 纹理随后由 GeometryProduct 以 live world MVP 采样并直接写入唯一 compositor target。没有携带 geometry、placement、generation 和 completion 的普通纹理不能发布为已组合几何层源；遇到跨产品依赖缺少这种 typed publication 时，在计划编译阶段局部拒绝，不能恢复 coverage 压平纹理或新增第二套 capture/compositor。

身份、作者顺序、frame state、property/provider、resource/target/publication、Program/graph 生命周期和最终 output 各只有一个产品 owner。新代码必须接入这些 owner，或直接消除重复 owner；不得建立第二套 registry、clock、property tree、graph、compositor 或按样本选择视觉算法。

解析、shader/reflection、ABI/target 检查、graph lowering、pipeline preparation 和静态索引属于 load、generation 或明确 invalidation。普通帧只消费准备结果、更新 typed state、检查必要的 generation/epoch/target/publication/completion 并执行。任何只服务报告、hash、route 统计、census 或未来扩展的机制不能成为播放前置。

新增或修改任何播放能力时，先按[逐对象生命周期与落代码合同](../architecture/runtime-architecture.md#8-scene-播放生命周期与落代码合同)确定装载、准备、帧更新、合成及释放 owner；是否先设计按[仓库设计判定](../../development/repository-workflow.md#设计判定与记录)执行；既有合同内的局部修复在当前批次说明输入、consumer、失效与反例，不另建重复设计。

## 模型自主性

模型可以自由重组类型、删除无 owner 的机制、改变验证顺序、选择 fixture 或更换实现方案，只要保持：

- 目标合同不被错误现状改写；
- 失败半径保持在最小安全单元；
- 产品始终只有一个输出决策；
- 新路径没有扩大普通帧成本；
- 结论不超过实际证据。

开始实现前至少明确四件事：要恢复的用户结果、共享链的第一个错误 identity/state/resource/output、当前 owner/fallback、能够证明结果的最小正反证据。答不出来时，先建立能区分候选原因的 observable，不要增加抽象层。

## 效率与验证

先确定任务属于工程成本还是作者行为，再进入对应路线；紧急可见回归按最早失败的公共职责处理，不被阶段编号阻塞。涉及两条路线时只选一个主结果、一个 owner 和一组验收，避免重复立项。

日常门使用 `python3.12 -B script/verify_scene_change.py --phase inner --base HEAD --path <owned-path>` 先查看选择，确认范围后加 `--run`；checkpoint 的纯构建入口是 `script/run_checkpoint_build.sh`。`script/build_and_run.sh` 会先停止正在运行的 App，不作为只构建或只读检查入口。纯路径移动仍需构建与源集合验证，但不应借机改播放算法。

正确画面和布局优先于能力数量，首帧和稳定帧时间优先于诊断便利。验证规模服从失败半径：最近的可执行单元 → 定向纵向切片 → 隔离真实内容 → fixed/full、长稳和发布。全量 corpus、完整链接扫描、截图流水、详细 observation、性能诊断和官方对照都属于按风险启用的证据环，不是普通编码前置。

桌面、媒体或最终 attachment 的回归必须覆盖无证据窗口参数的正常桌面 surface。`--mwx-debug-scene-evidence-dir` 会为截图关闭 framebuffer-only，调试入口也可能关闭真实系统媒体；注入 fixture 或可读截图目标的成功不能替代普通桌面加真实媒体的验收。采集应保留真实 surface 的提交进展及画面变化，不为观测方便改变目标资源权限。

性能比较固定Swift/C实际参数；Debug仅设Swift `-O`仍留C `-O0`。正式验收沿冻结WMO baseline及最终WMO candidate，Release runner命令及[短筛选/交互诊断profile](../../../script/scene_diagnostic_build.xcconfig)用法见该文件；后者不改Release默认、不加每批双套3B3C，升为正式对照须重建同配置B/C，不能新C配旧B。复用原build-input freeze、compile argv/response、签名staging/身份链。`DEBUG`含时钟/证据分支，正常Release播放另验；Debug checkpoint只证构建。分开首帧、CPU/pre-encode/GPU、提交/完成与next-frame；同条件三轮基线后一次消融一个成本，量CPU/elapsed、CPU/completed-frame、FPS、失败owner与每帧工作。ready须实际输出；收益近波动返回基线；正确性/失败/性能不退化才留。两次未改变首断点或减少工作量就换共享断点。

`observe-only`、`prefer-generic`、`generic-only` 和 `disable-generic` 只是有退出条件的迁移状态。不得静默双执行、永久保留 DEBUG 开关、永久依赖 fallback 或用 route 数、compile success、recognized、非黑画面、matrix PASS、单样本通过宣称兼容完成。

结构成本与功能同受治理：analyzer/matcher、请求包装、protocol、registry 与专用 fallback 家族由 `script/scene_source_layout.json` ratchet 冻结；零调用方入口、典范 helper 副本、identity/摘要吞错由 `script/check_scene_defense.py` 与 `script/scene_defense_baseline.json` 冻结。增长及 pattern/目标改动须说明 owner、理由、退役条件，以 `--accept-growth --reason` 逐项登记 `acknowledgedChanges`；保留该台账供 CI PR base、`event.before`、`HEAD^` 复核，仅 `--drop-unused-acknowledgements --base-ref <ref>` 按指定 ref 剪除。收缩随对应卡关闭同批 `--ratchet-baseline`。每批审逐项核对新增 guard、零消费者入口及 helper 副本；guard 须指名可违反它的产生者，否则删除；`script/check_scene_defense.py --audit` 实测须与锁定值对齐。审查输入还须有跨批次性质清单（同类 identity/lifecycle/失败半径在其他卡是否成立）及至少一个可执行反例（伪造时钟、会话或 stale generation）；形状断言、编译或路线计数不能单独证明接受。兼容阶段收口或重构卡关闭时普查家族、死引用、双 owner、重复推导，结果归重构卡，不另建文档体系。

治理脚手架自身遵守同一规则：route/profile/authority/ratchet 与诊断机制在达成终态后进入退役清单；迁移完成后不保留空转的门、台账或 DEBUG 开关，防止治理成为新的常驻成本。

<a id="compatibility-exceptions"></a>

## 兼容验收与例外登记

每批先命名修复的公共语义及输入到真实渲染的链路。新增规则要用变量改名、资源改名和等价表达式保持结果不变，再用相邻但语义不同的输入证明不会误命中。验收另选未参与实现选型或调参的真实样本，检查实际渲染；若复验失败后用它调整实现，它转为开发样本，须重新选择独立样本。profile、分支或路径命中不能代替画面结果。

路径/hash/固定源码形状例外集中登记：位置、必要性、范围、正反证据及替换条件；触达存量即补，不豁免样本派发禁令。资源身份/查找、缓存键、标准API名除外；未登记存量尚未全审。

| 例外与源码位置 | 必要性及证据 | 影响范围 | 变体与相邻反例 | 替换条件／当前状态 |
|---|---|---|---|---|
| 动态图片资源发现的源码形状限制：[ReferenceAnalysis](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptDynamicImageReferenceAnalysis.swift) | 准备期从直接路径/平面config literal收集有限依赖，避免帧内IO；不是视觉算法特判 | 四族owner已接同一Program需求及原材质消费者，见[公共准备](../history/shared-script-resource-preparation-2026-10-12.md)；helper/registered handle、任意嵌套表达式和module顶层创建仍受限 | 改名/等价表达、词法伪调用和未知请求局部失败经VM与实际四格像素验证；不声称完整JS解析 | 沿原Program补typed间接依赖与实际GPU正反验收后退除此限制；不得全目录预加载、按样本选择或另造运行时loader |
| 前级/模糊合成旧名称与有界形状：[GraphAdmission](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialPreviousBlurredCompositeGraphAdmission.swift)、[SourceAnalyzer](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderFrontend/SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.swift) | 名称不证明执行语义；本片已退役 definition/shader 名称门、scale 上限2与下界0.01。四 pass/两 quarter targets、combo/constant cohort及 source 有界形状仍服务现 owner 迁移证明 | 仅现 previous-blurred-composite owner，不按样本选择；非负有限采样量含零轴已准入，不把旧下界当官方范围 | 改名/等价及真实GPU已验，见[后验](../history/previous-blurred-composite-admission-2026-10-12.md#zero-axis-followup-20261019)；identity、wrong binding/state、不同 producer与Float溢出仍拒绝 | [准入合同](../capabilities/previous-blurred-composite-admission.md)；更宽typed Program正反验收后替换剩余形状，不复制算法 |
| 浮点取余形状 | 旧正则/专用判断限制同一运算 | 已退役；见[证据](../history/scalar-floating-remainder-2026-10-12.md) | 改名/等价/整数/副作用 | 共享词法/类型证明 |
## 事实和文档

- 最终怎样：[`runtime-architecture.md`](../architecture/runtime-architecture.md)；
- 工程边界与消融设计：[顶层设计](../roadmap/engine-refactor-program.md)；执行顺序与验收归[性能卡](../roadmap/performance-convergence-card.md)和[属性卡](../roadmap/properties-panel-card.md)；
- 作者行为、能力与可见验收顺序：[兼容路线](../roadmap/scene-compatibility-roadmap.md)，具体开放问题只看派生队列；
- 现在能什么：[`semantics/coverage-ledger.md`](../capabilities/coverage-ledger.md)及专项表；
- 实际发生什么：[`semantics/runtime-evidence-current.md`](../capabilities/runtime-evidence-current.md)。
- 全样本声明诊断、失败目录及总览/明细生成：[诊断与报告合同](corpus-diagnostic-workflow.md)；静态声明不代替实际播放裁决。

资料的热/冷分层、官方参考与代码的边界、长流水账的读取范围见[`语义手册`](../capabilities/README.md)。同一事实只保留一个权威解释。历史、研究取证、原始报告和本机缓存按需读取，不设为每批前置或要求隔离实现上下文。无决定性证据时停止写文档，回到代码和共享运行断点。
