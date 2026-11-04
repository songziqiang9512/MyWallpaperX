# Scene 当前验证范围

<!-- document-role: current-state -->

<a id="scope"></a>
## 冻结身份

2026-11-03全量测量基线为`1b0dd628ce0b6778acf9bef51fd1bcba45ac2d33`及显式DEBUG测量改动。全库App executable SHA-256为`5fce05dc6a71edabe9445d724912472f9d39d10adbca6f78dc2aafa14ec1727f`；Release配置加DEBUG、Swift `-O`/C `-Os`、single-file，Developer ID Team `H9QWU9XN8R`、无时间戳，arm64/macOS27.2/Xcode27.2。它不是正式Release性能配置。

42产品与31采集源码及原字节见`.artifacts/scene-goal-full-sample-retest-20261103/`的`frozen-product-sources.zip`、`build-source-freeze-v2.json`、`full-runtime-plan.json`。片头子集及关闭观测的构建/运行身份由同目录收据维护；后处理不改原报告。

最近粒子材质定向复验以`6743d8b0cfcf3fb216c6afd4c17a08ffd0c5f3e5`及2个Swift产品路径为输入。签名Debug的exec SHA为`391bf7034030a4827ae3a56e823804b17de53cd7a430cce1d1de9a7af14d2dae`、dylib为`dc2b5ae4e263233b4e425e006baf602015f94fdb8fec7fb3f4111d8e0ade7860`；实际代码在dylib中，不能只核stub。源码、构建前后身份及原字节在`.artifacts/scene-goal-rope-a2c-20261104/`。前一粒子子树App身份由`.artifacts/scene-goal-subtree-source-20261104/`保留。两个Debug版本均为`-Onone`、DEBUG，不能与优化基线作性能比较。各能力保自身App和输入身份，不作最终App全库重跑。

Named输入定向复验基于`961dd50c8e1872ff224f3224aff21d03b3afaab4`及43个Swift产品路径。签名Debug的exec SHA为`b6c3c4091727fef71756d67ba1ab91192daf8c2094761e14da3dd6f9c01bd0d1`、dylib为`18d3d5eb8a692d945dfb53d9c27d6c5b7a5cb16547ce7221b24f92a8de974338`，metallib为`80b49e42259c9bf4bbe5273d8fefe51013f5e152b66da431b85417e0dbb3b1a7`。构建前后43源一致，原字节、构建收据及有界原生验证保在`.artifacts/scene-goal-named-inputs-20261104/`；同为`-Onone`/DEBUG，只授本专项资格。

独立 named 来源定向复验基于`6f9cb0d672c7f405de9c93e5ce5f3e4c0499bae3`及3个Swift产品路径。签名Debug的exec SHA为`bb2ee8f1c7de703c6e080f10b2ab52daf23467d97b6cb70713b78b569931f37a`、dylib为`94132f24066ab28f418b1be5631fd20adbc8bb27bdc30985ec62e986d1da683e`；metallib与上述named专项相同。构建前后源码一致，原字节、两次实际失败与修正及运行收据保在`.artifacts/scene-goal-source-schedule-20261104/`；`-Onone`/DEBUG，不授优化性能资格。

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
| Prepared named与可见贡献 | 23组实际Metal向量涵盖同effect/跨effect/跨pass、同provider多槽、改名、换源、metadata-only Resolution、同帧背景与局部缺失；same-layer四readiness及mixed/optional反例保留。签名App有13次真实调用、26张PNG，A0/B0、slot重接与资源改名、同源不同UV、缺失健康后继、双向显隐、hidden/visible childless utility provider、半alpha与坏缓存控制均达预登记ROI。missing原日志误要求旁路操作成功绑定，修正后以同App/输入/PNG字节重放，未伪称新GPU运行。普通帧prepare一次、晚失供货严格子集、history/pin与foreign resource由实际Coordinator门验证，executor stub只授协议/状态；rotation/translation非零元数据、完整动画与性能未资格。 |
| 作者named链 | 9作者4秒子集同census三输入摘要，两个既有邻例保持PASS，整体原报告3 PASS/6 CHECK。350/69 e0/e1由copy恢复成真实材质，分别采91/1030 publication并经e2进入tail；375/319实际采309与slot7 mask，输出经group到main；280/19 e0五个material及后续e1…e5、tail成立。3个before与9个after均核原JSON、request/CB/Surface/sealed source/GPU，无截断。350隐藏1030的身份误报以独立admitted namespace修reader并对原字节重后处理：9/9期望分母未变、其余8图指标逐字段不变，真实opacity/Puppet/source/activation失败仍保。缺图、逐资产终端贡献及官方parity不由这些链授予；当前首断点见问题队列。 |
| 独立 named 来源 | 38项真实依赖计划方法、10项native owner方法通过；后者含7组image/solid straight与PMA输入、真实透明清空、同epoch复用、跨epoch重清和资源/预算反例。局部4×2预约与主8×4捕获先实际误拒，修正后只消费原target；native几何为被动夹具，生产组变换由App另证。5个App控制/10张PNG全部达严格ROI：前/后置、ID/资源/槽位改名、无效果透明来源、半alpha纹理/tint、缺child与真实decode-failed来源及健康后继。半alpha solid从实测(48,8,215)恢复为预登记(24,4,203)，opaque邻区不变；来源均无Program事务，失败原图/输入保留。5作者同三输入摘要的4秒复验为4 PASS/2972071249既有CHECK；355/411以220² PMA raw publication供1111e0真实slot1材质，再经roundedmask/tail/main；308/259以32² PMA同publication供430e0/e2真实slot1材质，再经426组source/opacity到main。430e1实际visibility-disabled copy，CPU encoded-output不作该段shader执行证明。295/377邻例保持，377保既有source瞬态与同层恢复；297前缀取时、默认父alpha下的逐资产可见贡献、完整动画及parity未资格。 |
| 视觉粗筛 | 633张全部实际查看：539未见明显粗筛异常、14视觉疑点、35需时间/输入、45参考不足；另开40张原图复核。作者preview仅方向性，无视觉PASS或官方parity。 |
| 长窗与过场 | 稀疏3766387484在模拟约9.995秒接纳出生，所选帧root/child各2；两个雷电profile仍因周期上限拒绝。10个片头样本补至Ready+约15秒，实际看到标识退场或主体变化。3764725758/3830665420的第二轮仍未资格。 |
| 失败与恢复 | 原CHECK、精确拒绝、pre-Ready失败与后续成功均保留；首次3780119725 stop附近31条ledger失败，22秒/10秒复验未复现，不删原失败。当前首因与有价值个案归[开放队列](../roadmap/scene-open-breakpoint-queue.md)。 |
| 快照容量 | 原全局实际计费下55项原生门通过，含BGRA100MB/HDR200MB、满额cached复用、新尺寸拒绝、显式限额、双owner回滚及在途释放。5000×5000 blend31中心与64×64正控同为BGRA(72,48,48,255)，外部背景保持。3087231311同三输入摘要的365层copy/blend/draw及GPU完成，2808874251折射与3471294034邻例有界复验；脚底logo同相位像素未资格。收据见`.artifacts/scene-goal-snapshot-capacity-20261103/`。 |
| 标量phase数据输入 | 20项相关原生方法通过，含5组两帧Metal权重像素、改名及颜色/volume反例。2900431360同三输入摘要的五个effect实际按noise/normal绑定slot2，进入原材质draw、后续读取及layer tail；父App仅copy。3612795410标准phase与2999344788自定义资产的4条waterflow输入继续绘制，后者原bokeh producer失败仍在。四次捕获均匹配request/CB/Surface/GPU与sealed drawable；不授逐资产终端像素、完整动画或官方parity。原始资料见`.artifacts/scene-evidence/runs/scalar-data-input-20261103/`。 |
| Intrinsic共同形状 | Windows HLSL4编译/反汇编9组数值资格；150相关方法分阶段149通过、1个独立314夹具缺失跳过。21组双backend两帧共84个float4，6组uniform A/B/A共72个float4。3042660491/127e0与3746066933/17e1各有1个目标material节点及slot0/1/2实际绑定、GPU完成；304经ordinary/tail消费输出，374的terminal replay复用Program实槽直写drawable；3471294034/3589819394邻例保持。八张捕获同request/CB/Surface/seal，输入三摘要一致。作者报告在`.artifacts/scene-evidence/runs/intrinsic-width-before-20261104/`与`intrinsic-width-20261104/`。逐纹理sample/可见贡献、固定随机时序、官方parity与性能未资格。 |
| 双输入composite执行 | 同输入的2879793348、3632522893、3725148661、3747595588、3750312644、3830727231目标effect各有4个真实material节点、next-material/ordinary/group消费及layer tail；capture逐项匹配request/CB/Surface/sealed texture/GPU。2/5pass改名图、独立采样/gain、显隐恢复及健康邻层有实际像素。广域10作者为9 PASS/2999344788既存CHECK：仅89e0 #91缺producer，两个waterflow节点的4个flow/phase输入仍draw；不授每个资产最终像素贡献。收据见`.artifacts/scene-evidence/runs/typed-color-boundary-20261103/`。 |
| 普通颜色与真实角色 | 61个不同相关原生方法在冻结阶段及定向修复中取得通过，含PMA/straight、alpha/HDR、raw data、有序signal/underlay、passthrough、错误角色/绑定及缓存冷热读写；各日志保实际失败与修复边界，不是一次61项运行。18项离线工具门含加权/别名passthrough与canonical metadata。广域9个App用例通过；36df84…版本补3个受影响用例，动态tint同输入从旧copy恢复为64→128→关闭恢复，健康邻层、window/Surface/session保持。该版本的2900431360、3471294034、3589819394三例均Ready、精确capture/GPU完成且无新增拒绝，收据见`typed-color-final-role-20261104/`；不作完整动画、优化性能或官方parity资格。 |
| Composition成员与source-free quad | 现有成员/显隐门60项及显式GPU补测通过；原生prepared uniform查询4项及Finalizer相邻3项通过，含缺省/0/1/无关combo、真实slot0/3 graph输入及未准备反例。组source分配、nearest membership、parent闭包与作者顺序保留。6个成员改造App用例通过，04d12…版本另补同字节quad与改名链两例：非均匀缩放、父容器隐藏、健康peer与局部224×112画布有预登记像素；quad原后置许可拒绝也保留。该版本4作者同三输入摘要与精确capture/GPU完成，3529515784/175的3个材质节点、3825183869/187的1节点均有组source、后续读取与terminal tail，3471294034健康。逐资产/字符最终贡献、父alpha继承和完整动画仍未资格；作者证据见`container-source-20261104/`。 |
| 粒子composition source | 3465215190/2481、3781757083/133、3806222046/454、3809609151/42、3830727231/882所选帧均有1个source capture、合计20个实际material节点及各1个tail；粒子写入对应group target，其token等于source输入，末材质输出=tail/group输入，最后group进入sealed主画面。383保viewport source与938→93→882嵌套target；3042623710、3529515784邻例保持。七次capture逐一匹配request/CB/Surface/seal/GPU、原始JSON与输入三摘要。109项入口/准入方法、45项production粒子门通过；后者含64组vertex、16组depth/clip、48组REFRACT物理尺寸/零控制。受控父级蓝反相把紫粒子变红，宽窄画布折射读回一致；五个App方法分阶段通过，含粒子组关闭→开启→关闭的白→灰→白、资源改名与missing shader保源/peer。missing enable拒绝，重复关闭为合法空操作；窗口/Surface不重建。证据在`particle-subtree-before-20261104/`、`particle-subtree-20261104/`及上述任务目录。逐实例最终贡献、任意projective组、官方amount单位与优化性能未资格。 |
| 粒子材质与几何分离 | 13项CPU、13项Metal、67项相机/折射/普通绘制及38项测量工具方法通过；实际Runtime含24组几何与40组depth输入、零alpha不遮挡、镜像剔除、readonly/write次序、缺PSO健康peer及低RGB的overbright65。原作者3807668787/958从材质拒绝进入活动A2C Rope，五个缩导出活动相位编码126/224/224/252/238段并GPU完成；另次3024×1964原图仅在两个端点见弱色信号，完整轨迹视觉仍未资格。3788897599的mouse=true变体中568父Rope及child0 red_fire实际绘制，固定ROI见联合变化；无逐child像素归因，其他project/纹理缺口仍独立。3745828537默认Sprite A2C邻例与三作者4秒复验保持。41个原作者及14个私有控制capture均匹配原始JSON/request/CB/Surface/seal/extent/GPU，无观测截断；各次相位未锁定随机性。缩导出活动before/after证据在`particle-raster-pointer-before-20261104/`与`particle-raster-pointer-20261104/`，原尺寸与alpha1/0诊断控制由本任务收据区分；私有改alpha不能充当原作者恢复。sampleCount1硬件mask已测，不证明官方coverage/LOD、物理鼠标、完整动画或性能。 |
| 粒子通用剔除 | 64个不同相关原生方法分阶段通过；117个真实AssetGraph profile、18组正交/透视与signed local/fixed/world-size/trail几何、72份四lane BGRA覆盖一致。精确面积100/74；8×8非零normal、source UV、alpha只乘一次与后继显式noCull健康绘制通过；原normal格式、R8、depth/snapshot/clip邻门保留。作者before/after三输入摘要相同，最终3 PASS/3566323704既有normal空槽CHECK；3042623710/330保持作者normal，由不可用恢复到所选帧1实例的色纹理、当前背景复制/绘制及同Surface/CB/sealed target/GPU完成。该作者normal省略，slot1色纹理别名仅ABI绑定，flat分支不采样它；作者记录绑定/绘制/终端链，逐纹理像素贡献仍未资格；非零法线、UV与覆盖像素由独立GPU门证明。证据见`refraction-cull-20261104/`，初次夹具失败、修正与当前读回身份由任务收据保留。 |
| 测量改动验证 | 粒子146项中136通过、10项因私有运行缓存缺失跳过；18项真实Metal邻门、62项后处理/collector、20项保留工具及Release诊断排除门通过。成本修正后三个真实邻例capture/GPU排空与既有失败一致；关闭观测的实际运行无新增两类载荷。独立审查无未闭实现finding。 |

<a id="limits"></a>
## 未取得的资格

本批为direct-host诊断与有界静帧，不覆盖普通App选择、client/daemon IPC、物理多屏、macOS26最低版本、受控音频/媒体/全部pointer或属性分支、连续长稳、完整周期、优化性能/能耗、正式发行或官方同输入像素一致性。资源/组件未观察或无法精确归因的阶段保unknown；主画面成立不关闭局部能力缺口。

能力见[索引](README.md#overview)，测量方法见[开发工作流](../development/development-workflow.md#corpus-runtime-measurement)，性能资格见[性能卡](../roadmap/performance-convergence-card.md)。
