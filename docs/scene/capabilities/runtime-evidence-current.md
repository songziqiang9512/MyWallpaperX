# Scene 当前验证范围

<!-- document-role: current-state -->

<a id="scope"></a>
## 冻结身份

2026-11-03全量测量基线为`1b0dd628ce0b6778acf9bef51fd1bcba45ac2d33`及显式DEBUG测量改动。全库App executable SHA-256为`5fce05dc6a71edabe9445d724912472f9d39d10adbca6f78dc2aafa14ec1727f`；Release配置加DEBUG、Swift `-O`/C `-Os`、single-file，Developer ID Team `H9QWU9XN8R`、无时间戳，arm64/macOS27.2/Xcode27.2。它不是正式Release性能配置。

42产品与31采集源码、构建收据及原字节见`.artifacts/scene-goal-full-sample-retest-20261103/`的`frozen-product-sources.zip`、`build-source-freeze-v2.json`、`full-runtime-plan.json`。片头子集另有采集源码收据；后处理更正不重写原报告。观察成本修正后的App SHA为`51164968353e0b0eefaf08c44cf8d8e30fdbe954615e5ae5244ab2101002a4ea`，同目录`build-source-freeze-v3.json`及两份`*-build-optout-final-inputs.json`保签名Debug/优化DEBUG构建前后42源一致。

<a id="coverage"></a>
## 全库运行与逐项阶段

原始报告、日志和PNG在`.artifacts/scene-evidence/runs/full-corpus-20261103/`；未闭个案另由`full-corpus-open-20261103/`保护。上述任务目录的`sample-results.md/json`提供635项索引及实际PNG/log入口，`full-archive.json.gz`保全部attempt/逐声明阶段，`corpus/snapshot.json.gz`保观察分母。

| 范围 | 实际结果与边界 |
|---|---|
| 全库输入 | 635目录，633合法Scene实际运行、project/package/tree摘要与census一致；3736952187/3763323436缺project.json，入口退出且保分母。未改作者原件。 |
| 默认窗口 | 4个隔离worker；Ready后观察4秒，约第3秒读回。633/633取得Ready、非黑PNG及GPU排空，无超时。初次基础600通过/33 CHECK保原值，不能作缺陷数或支持率。 |
| 真正捕获 | 633个初次事件同request/CB/Surface、GPU completed、sealed drawable token及源尺寸逐一匹配；后续17次定时/片头/stop补测同样匹配。PNG只缩导出至最长1280，源渲染3024×1964。 |
| 消费记录 | 初次63,561合成行、118,761组件首事实，解析失败与观测截断均0。记录Program实槽、普通/geometry/model/group、粒子batch、复制/导出与tail，bind、attachment-read、GPU及终端阶段独立。 |
| 全量索引 | 263,724声明中51,786是包库存及其派生项，211,938有作者consumer关系；不能将整个集合当活动执行分母。38,963个consumer纹理声明有7,732项实际绑定/GPU阶段证据，31,231项关联或触发阶段未知；原effect有42项fallback，copy完成不作原operation执行。逐实例及最终像素贡献均未取得通用资格。 |
| 视觉粗筛 | 633张全部实际查看：539未见明显粗筛异常、14视觉疑点、35需时间/输入、45参考不足；另开40张原图复核。作者preview仅方向性，无视觉PASS或官方parity。 |
| 长窗与过场 | 稀疏3766387484在模拟约9.995秒接纳出生，所选帧root/child各2；两个雷电profile仍因周期上限拒绝。10个片头样本补至Ready+约15秒，实际看到标识退场或主体变化。3764725758/3830665420的第二轮仍未资格。 |
| 失败与恢复 | 原CHECK、精确拒绝、pre-Ready失败与后续成功均保留；首次3780119725 stop附近31条ledger失败，22秒/10秒复验未复现，不删原失败。当前首因与有价值个案归[开放队列](../roadmap/scene-open-breakpoint-queue.md)。 |
| 测量改动验证 | 粒子146项中136通过、10项因私有运行缓存缺失跳过；18项真实Metal邻门、62项后处理/collector、20项保留工具及Release诊断排除门通过。成本修正后三个真实邻例capture/GPU排空与既有失败一致；关闭观测的实际运行无新增两类载荷。独立审查无未闭实现finding。 |

<a id="limits"></a>
## 未取得的资格

本批为direct-host诊断与有界静帧，不覆盖普通App选择、client/daemon IPC、物理多屏、macOS26最低版本、受控音频/媒体/全部pointer或属性分支、连续长稳、完整周期、优化性能/能耗、正式发行或官方同输入像素一致性。资源/组件未观察或无法精确归因的阶段保unknown；主画面成立不关闭局部能力缺口。

能力见[索引](README.md#overview)，测量方法见[开发工作流](../development/development-workflow.md#corpus-runtime-measurement)，性能资格见[性能卡](../roadmap/performance-convergence-card.md)。
