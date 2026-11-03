# Scene 当前验证范围

<!-- document-role: current-state -->

<a id="scope"></a>
## 冻结身份

2026-11-03全量测量基线为`1b0dd628ce0b6778acf9bef51fd1bcba45ac2d33`及显式DEBUG测量改动。全库App executable SHA-256为`5fce05dc6a71edabe9445d724912472f9d39d10adbca6f78dc2aafa14ec1727f`；Release配置加DEBUG、Swift `-O`/C `-Os`、single-file，Developer ID Team `H9QWU9XN8R`、无时间戳，arm64/macOS27.2/Xcode27.2。它不是正式Release性能配置。

42产品与31采集源码及原字节见`.artifacts/scene-goal-full-sample-retest-20261103/`的`frozen-product-sources.zip`、`build-source-freeze-v2.json`、`full-runtime-plan.json`。片头子集及关闭观测的构建/运行身份由同目录收据维护；后处理不改原报告。

当前定向复验基于`e23f4dc65b004b8eb4a77bd604e5510d0ad1a1bc`及4个Swift产品路径，最终App SHA为`b15f65c203a4afa238beb8e6f4400c7ca5843e662f2c89064f73495b2f175ce3`。签名Debug/优化DEBUG构建的产品摘要前后一致；`.artifacts/scene-goal-intrinsic-vector-width-20261104/`保源码、构建、输入与分阶段数值资格。各能力保自身App和输入身份，不作最终App全库重跑。

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
| Intrinsic共同形状 | Windows HLSL4编译/反汇编9组数值资格；150相关方法分阶段149通过、1个独立314夹具缺失跳过。21组双backend两帧共84个float4，6组uniform A/B/A共72个float4。3042660491/127e0与3746066933/17e1各有1个目标material节点及slot0/1/2实际绑定、GPU完成；304经ordinary/tail消费输出，374的terminal replay复用Program实槽直写drawable；3471294034/3589819394邻例保持。八张捕获同request/CB/Surface/seal，输入三摘要一致。作者报告在`.artifacts/scene-evidence/runs/intrinsic-width-before-20261104/`与`intrinsic-width-20261104/`。逐纹理sample/可见贡献、固定随机时序、官方parity与性能未资格。 |
| 双输入composite执行 | 同输入的2879793348、3632522893、3725148661、3747595588、3750312644、3830727231目标effect各有4个真实material节点、next-material/ordinary/group消费及layer tail；capture逐项匹配request/CB/Surface/sealed texture/GPU。2/5pass改名图、独立采样/gain、显隐恢复及健康邻层有实际像素。383的882混合子树仍开放。广域10作者为9 PASS/2999344788既存CHECK：仅89e0 #91缺producer，两个waterflow节点的4个flow/phase输入仍draw；不授每个资产最终像素贡献。收据见`.artifacts/scene-evidence/runs/typed-color-boundary-20261103/`。 |
| 普通颜色与真实角色 | 61个不同相关原生方法在冻结阶段及定向修复中取得通过，含PMA/straight、alpha/HDR、raw data、有序signal/underlay、passthrough、错误角色/绑定及缓存冷热读写；各日志保实际失败与修复边界，不是一次61项运行。18项离线工具门含加权/别名passthrough与canonical metadata。广域9个App用例通过；36df84…版本补3个受影响用例，动态tint同输入从旧copy恢复为64→128→关闭恢复，健康邻层、window/Surface/session保持。该版本的2900431360、3471294034、3589819394三例均Ready、精确capture/GPU完成且无新增拒绝，收据见`typed-color-final-role-20261104/`；不作完整动画、优化性能或官方parity资格。 |
| Composition成员与source-free quad | 现有成员/显隐门60项及显式GPU补测通过；原生prepared uniform查询4项及Finalizer相邻3项通过，含缺省/0/1/无关combo、真实slot0/3 graph输入及未准备反例。组source分配、nearest membership、parent闭包与作者顺序保留。6个成员改造App用例通过，04d12…版本另补同字节quad与改名链两例：非均匀缩放、父容器隐藏、健康peer与局部224×112画布有预登记像素；quad原后置许可拒绝也保留。该版本4作者同三输入摘要与精确capture/GPU完成，3529515784/175的3个材质节点、3825183869/187的1节点均有组source、后续读取与terminal tail，3471294034健康、3465215190粒子投影缺口保留。逐资产/字符最终贡献、父alpha继承和完整动画仍未资格；作者证据见`container-source-20261104/`。 |
| 粒子通用剔除 | 64个不同相关原生方法分阶段通过；117个真实AssetGraph profile、18组正交/透视与signed local/fixed/world-size/trail几何、72份四lane BGRA覆盖一致。精确面积100/74；8×8非零normal、source UV、alpha只乘一次与后继显式noCull健康绘制通过；原normal格式、R8、depth/snapshot/clip邻门保留。作者before/after三输入摘要相同，最终3 PASS/3566323704既有normal空槽CHECK；3042623710/330保持作者normal，由不可用恢复到所选帧1实例的色纹理、当前背景复制/绘制及同Surface/CB/sealed target/GPU完成。该作者normal省略，slot1色纹理别名仅ABI绑定，flat分支不采样它；作者记录绑定/绘制/终端链，逐纹理像素贡献仍未资格；非零法线、UV与覆盖像素由独立GPU门证明。证据见`refraction-cull-20261104/`，初次夹具失败、修正与当前读回身份由任务收据保留。 |
| 测量改动验证 | 粒子146项中136通过、10项因私有运行缓存缺失跳过；18项真实Metal邻门、62项后处理/collector、20项保留工具及Release诊断排除门通过。成本修正后三个真实邻例capture/GPU排空与既有失败一致；关闭观测的实际运行无新增两类载荷。独立审查无未闭实现finding。 |

<a id="limits"></a>
## 未取得的资格

本批为direct-host诊断与有界静帧，不覆盖普通App选择、client/daemon IPC、物理多屏、macOS26最低版本、受控音频/媒体/全部pointer或属性分支、连续长稳、完整周期、优化性能/能耗、正式发行或官方同输入像素一致性。资源/组件未观察或无法精确归因的阶段保unknown；主画面成立不关闭局部能力缺口。

能力见[索引](README.md#overview)，测量方法见[开发工作流](../development/development-workflow.md#corpus-runtime-measurement)，性能资格见[性能卡](../roadmap/performance-convergence-card.md)。
