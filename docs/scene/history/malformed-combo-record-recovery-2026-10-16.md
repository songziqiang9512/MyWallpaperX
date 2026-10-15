<!-- document-role: historical-evidence -->
# 畸形 COMBO 记录局部恢复

> **历史证据 — 非现役入口**。截止：2026-10-16。稳定职责归[运行架构](../architecture/runtime-architecture.md#malformed-combo-record)，缓存归[变体缓存合同](../architecture/variant-analysis-cache-contract.md)，后继归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。本轮只恢复独立 COMBO 注释的记录局部失败，不计整样本、官方像素 parity 或性能专项完成。

## 通用语义与实现

3435573282 的新运行有 24 个模板首门拒绝：均 authoredSource、vertex/fragment 双阶段及一个 malformedAnnotation。三次有界临时探针只输出 typed identity/enum/count/Bool；共同定位到根 stage 的纯注释 COMBO，旧 outer-field 恢复证明不成立。未读取作者表达或坏 JSON 内容，所有探针源码均 exact 恢复后才写产品修复。

依既有合法中性来源记录，失败 metadata 不应整段拒绝 shader。现有 `SceneShaderMalformedMetadataAdmission` 对模板与 include/preprocessor 共用词法判断：扫描实际此前 block-comment 状态，仅丢弃无代码、行首 COMBO marker 的 JSON 解析失败记录。原 source、声明、诊断保留，不生成坏记录的 Annotation/default/options，不要求合法重复记录，不修非法 JSON。inline uniform/sampler、其他 marker、代码/directive 混排及结构/identity/预算失败仍拒绝；必需 producer/default 仍由原下游拒绝。旧重复签名、正则 sanitizing 与 outer-field 算法退出。frontend 49、VariantAnalysis v23、DemandAnalysis v6 同时退出旧 tier，record wire 不变。

## 真实结果与限制

有效 Developer ID Debug App 的 343 原包运行 PID 27688：正常退出、未超时、App drift=[]、GPU drained。原 24 目标中 21 个 exact layer/effect/node 从无执行变为 generic-only 实际执行，目标 effect 均有 succeeded/completed、material>0/rejected0 回执并进入后续合成。20 个恢复层末 effect 无拒绝且 compositorConsumed=true；3226 的末 effect3 仍以 material0/rejected1 透传，不能算完整效果恢复。407 的两目标和 529 的一目标仍无 target 执行，保持开放。

额前及耳侧原先缺失的细发丝实际出现，连续帧仍可见且位置变化；新增 named capture 沿原 provider 链消费。PNG 不是同模拟相位，不量化逐像素差，不把其余皮肤、衣摆或完整交互差异一并关闭。当前总 generic 材质执行由 25 到 89，是恢复更多作者工作，不是性能下降/提升的可比测量。

未参与修法的 3761619125 原包 PID 28745 正常退出、App drift=[]、GPU drained；78 个不同 generic 节点实际执行，115 个 effect 图包含原作者关闭透传。实际人物、飘带与背景可见，未发现本批相关缺失或 UI 遮挡；已有 37 个作者关闭与其他视觉余项仍保留。

模板 6、预处理器 3、持久缓存 4、finalizer 34 个测试通过。自有变体包括变量/资源改名、等价表达、大小写/CRLF、include/条件、无重复及合法邻居；反例保 inline、混排、其他 marker、未闭合源码、缺 include、缺 producer 和合法 metadata 冲突。缓存检查 fresh-reader 冷暖、旧 namespace/schema 只读 miss、损坏与摘要；旧 wire 只在测试副本显式重封套，产品不迁移旧缓存。防御面重复函数组 121→120 已收紧。

首轮修后 App 因 root 构建命令覆盖签名而变为 ad hoc，原 helper team 门拒绝，60 秒在准备期终止；该轮无运行资格，随后按仓库默认 Developer ID 重建，未改安全门。预处理器首轮新增测试误用 value 类型导致 harness 编译失败，修正 typed variantValue 后唯一复跑通过。有效 343/376 单轮总用时约 114.8/105.9 秒，包含全冷编译、采集与其他 CPU 验证争用，不作为可比启动或 CPU/GPU/RAM 收益；新增工作及冷启动成本留性能卡原专项追踪。

## 收据与保留

忽略根 `.artifacts/tmp/343-template-qualification-20261015/` 保留输入 SHA、冻结源码身份、探针 diff/退役、typed 安全投影、测试/签名及进程回执。`target-receipts.json` 的 terminal rows 包含未变的 407，恢复计数只取上述 21/20，不能把全表计为新增。必要原图为基线一张、修后两张和独立样本一张；清理去留以该根 `cleanup.json` 为准。真实媒体始终只读，当前有效 App 与唯一 DerivedData 延续后继批次，不发布或推送。
