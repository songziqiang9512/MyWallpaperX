# Scene 当前验证范围

<!-- document-role: current-state -->

<a id="scope"></a>
## 冻结身份

2026-11-03全量测量基线为`1b0dd628ce0b6778acf9bef51fd1bcba45ac2d33`及显式DEBUG测量改动。全库App executable SHA-256为`5fce05dc6a71edabe9445d724912472f9d39d10adbca6f78dc2aafa14ec1727f`；Release配置加DEBUG、Swift `-O`/C `-Os`、single-file，Developer ID Team `H9QWU9XN8R`、无时间戳，arm64/macOS27.2/Xcode27.2。它不是正式Release性能配置。

42产品与31采集源码及原字节见`.artifacts/scene-goal-full-sample-retest-20261103/`的`frozen-product-sources.zip`、`build-source-freeze-v2.json`、`full-runtime-plan.json`。片头子集及关闭观测的构建/运行身份由同目录收据维护；后处理不改原报告。

当前定向复验基于`c6a7ab4e5ec991ec60adb1e6b2ef1bffec7a09f2`及十个产品路径的composite准备改动，App SHA为`9e51b29088850b3496a538d64ee2766d8d2c2f9d1b16c196e58b34fd0b1d6c9b`。签名Debug/优化DEBUG构建源稳定；`.artifacts/scene-goal-blur-owner-20261103/`保冻结源码摘要、构建/输入身份、自有图像素和原生结果。定向复验不代表新App全库重跑。

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
| 快照容量 | 原全局实际计费下55项原生门通过，含BGRA100MB/HDR200MB、满额cached复用、新尺寸拒绝、显式限额、双owner回滚及在途释放。5000×5000 blend31中心与64×64正控同为BGRA(72,48,48,255)，外部背景保持。3087231311同三输入摘要的365层copy/blend/draw及GPU完成，2808874251折射与3471294034邻例有界复验；脚底logo同相位像素未资格。收据见`.artifacts/scene-goal-snapshot-capacity-20261103/`。 |
| 标量phase数据输入 | 20项相关原生方法通过，含5组两帧Metal权重像素、改名及颜色/volume反例。2900431360同三输入摘要的五个effect实际按noise/normal绑定slot2，进入原材质draw、后续读取及layer tail；父App仅copy。3612795410标准phase与2999344788自定义资产的4条waterflow输入继续绘制，后者原bokeh producer失败仍在。四次捕获均匹配request/CB/Surface/GPU与sealed drawable；不授逐资产终端像素、完整动画或官方parity。原始资料见`.artifacts/scene-evidence/runs/scalar-data-input-20261103/`。 |
| 双输入composite执行 | 六个同输入样本2879793348、3632522893、3725148661、3747595588、3750312644、3830727231的目标effect均在终端同帧执行4个真实material节点，输入及next-material/ordinary/group消费、layer tail和GPU完成匹配；不再仅copy。3471294034与已恢复scalar输入的2900431360无新增拒绝，383的882混合子树仍开放。8次捕获逐项匹配request/CB/Surface/sealed texture。自有2/5pass改名图、独立scale/gain和热显隐有实际Metal像素；5pass垂直ROI按cover/UV几何在同4张PNG离线校正后断言通过，shader/参数/期望未改，不计新GPU运行。13项相关原生方法通过，含PMA/straight、alpha/HDR、错误binding/purpose及准备取消反例。原始作者回执见`.artifacts/scene-evidence/runs/generic-composite-admission-20261103/`。 |
| 测量改动验证 | 粒子146项中136通过、10项因私有运行缓存缺失跳过；18项真实Metal邻门、62项后处理/collector、20项保留工具及Release诊断排除门通过。成本修正后三个真实邻例capture/GPU排空与既有失败一致；关闭观测的实际运行无新增两类载荷。独立审查无未闭实现finding。 |

<a id="limits"></a>
## 未取得的资格

本批为direct-host诊断与有界静帧，不覆盖普通App选择、client/daemon IPC、物理多屏、macOS26最低版本、受控音频/媒体/全部pointer或属性分支、连续长稳、完整周期、优化性能/能耗、正式发行或官方同输入像素一致性。资源/组件未观察或无法精确归因的阶段保unknown；主画面成立不关闭局部能力缺口。

能力见[索引](README.md#overview)，测量方法见[开发工作流](../development/development-workflow.md#corpus-runtime-measurement)，性能资格见[性能卡](../roadmap/performance-convergence-card.md)。
