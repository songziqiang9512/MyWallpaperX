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

新增或修改任何播放能力时，先按[逐对象生命周期与落代码合同](../design/runtime-architecture.md#8-scene-播放生命周期与落代码合同)确定装载、准备、帧更新、合成及释放 owner；只在当前批次说明中填写其输入、consumer、失效与反例，不另建重复设计文档。

## 模型自主性

模型可以自由重组类型、删除无 owner 的机制、改变验证顺序、选择 fixture 或更换实现方案，只要保持：

- 目标合同不被错误现状改写；
- 失败半径保持在最小安全单元；
- 产品始终只有一个输出决策；
- 新路径没有扩大普通帧成本；
- 结论不超过实际证据。

开始实现前只需回答四件事：要恢复的用户结果、共享链的第一个错误 identity/state/resource/output、当前 owner/fallback、能够证明结果的最小正反证据。答不出来时，先建立能区分候选原因的 observable，不要增加抽象层。

## 效率与验证

先确定任务属于工程成本还是作者行为，再进入对应路线；紧急可见回归按最早失败的公共职责处理，不被阶段编号阻塞。涉及两条路线时只选一个主结果、一个 owner 和一组验收，避免重复立项。

日常门使用 `python3.12 -B script/verify_scene_change.py --phase inner --base HEAD --path <owned-path>` 先查看选择，确认范围后加 `--run`；checkpoint 的纯构建入口是 `script/run_checkpoint_build.sh`。`script/build_and_run.sh` 会先停止正在运行的 App，不作为只构建或只读检查入口。纯路径移动仍需构建与源集合验证，但不应借机改播放算法。

正确画面和布局优先于能力数量，首帧和稳定帧时间优先于诊断便利。验证规模服从失败半径：最近的可执行单元 → 定向纵向切片 → 隔离真实内容 → fixed/full、长稳和发布。全量 corpus、完整链接扫描、截图流水、详细 observation、性能诊断和官方对照都属于按风险启用的证据环，不是普通编码前置。

性能结论必须区分首帧、CPU/pre-encode、GPU、提交/完成和 next-frame。消融一次只移除一种常驻成本，用相同输入和环境比较，至少重复三次；只有正确性、失败边界和性能同时没有退化，才保留优化。两次实验没有改变首断点或没有减少工作量，就换共享断点。

`observe-only`、`prefer-generic`、`generic-only` 和 `disable-generic` 只是有退出条件的迁移状态。不得静默双执行、永久保留 DEBUG 开关、永久依赖 fallback 或用 route 数、compile success、recognized、非黑画面、matrix PASS、单样本通过宣称兼容完成。

结构成本与功能同受治理：形状 analyzer/matcher、请求包装层、protocol、registry 与专用 fallback 家族由 `script/scene_source_layout.json` 的 ratchet 冻结现值，增长要在批次描述中写明 owner、理由与退役条件后显式改基线，收缩随对应卡关闭同批下降。每逢兼容阶段收口或重构卡关闭时重做一次结构普查（家族计数、死引用、双 owner、重复推导），结果登记进重构计划的对应卡，不另建普查文档体系。

审查结论绑定行为证据：审查输入必须包含跨批次性质清单（同类 identity、lifecycle、失败半径问题在其他卡是否同样成立）和至少一个可执行反例（伪造时钟、会话或 stale generation 注入）；形状断言全绿、编译通过或路线计数不能单独作为接受理由。

治理脚手架自身遵守同一规则：route/profile/authority/ratchet 与诊断机制在达成终态后进入退役清单；迁移完成后不保留空转的门、台账或 DEBUG 开关，防止治理成为新的常驻成本。

## 事实和文档

- 最终怎样：[`runtime-architecture.md`](../design/runtime-architecture.md)；
- 工程成本、架构与减重顺序：[重构计划](../engine-refactor-program.md)；
- 作者行为、能力与可见验收顺序：[兼容路线](../scene-compatibility-roadmap.md)，具体开放问题只看派生队列；
- 现在能什么：[`semantics/coverage-ledger.md`](../semantics/coverage-ledger.md)及专项表；
- 实际发生什么：[`semantics/runtime-evidence-current.md`](../semantics/runtime-evidence-current.md)。

资料的热/冷分层、官方参考与代码的边界、长流水账的读取范围见[`语义手册`](../semantics/README.md)。同一事实只保留一个权威解释。历史、研究取证、原始报告和本机缓存按需读取，不进入普通实现上下文。无决定性证据时停止写文档，回到代码和共享运行断点。
