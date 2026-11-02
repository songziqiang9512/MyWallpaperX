# 当前拓扑与活动组件生命周期后验

> **历史证据 — 非现役入口**

<!-- document-role: historical-evidence -->

> 固定 2026-11-02/03 批次。目标归[重构设计](../roadmap/engine-refactor-program.md)，当前状态归[运行证据](../capabilities/runtime-evidence-current.md)，未闭职责归[唯一队列](../roadmap/scene-open-breakpoint-queue.md#51-顶层设计已裁决的代码职责重构)。

<a id="sprite-timeline-retirement"></a>
## Sprite 与 Timeline 活动状态退休

Session 在原 Surface 执行阶段一次采样共享 Sprite 时间，前置 VM snapshot 与 commit 接纳 texture commands 的 nextFrame 顺序不变。提交销毁后，TextureAnimation/Timeline 原 runtime 消费本次新增销毁成员，整理活动 bindings、indices、owner 映射和 pending observations；保作者 Program/named catalog 的稳定索引、幸存播放 anchor、hidden 和跨 owner 控制。不在后续出生/排序时重放累计死集。

View 在 Surface 下一次采用 committed topology 时退休 Sprite 实例与输出；暂停重绘继续持有原冻结帧资源及 UV。原装配入口在构造前排除 committed 删除成员，共享 source/健康 peer 保留；MPS completion 持有在途 playback 和 destination reservation 至 GPU 完成，未提交仍走原 cancel/rollback。QuickJS TextureAnimation getter 和保留的方法句柄在原入口拒绝同 owner 已 staged destroy 的使用，保 destroy 前命令，不层层新增 runtime guard。

12 个产品文件增 205、删 24 行，净增 181，含已有 DEBUG runner 的真实重建探针及按需 snapshot；7 个测试文件增 508、删 38。无新产品文件、clock、cache、registry、状态镜像或退休 manager。运行时新增代码服务活动状态退出；DEBUG 观察不进入非观察普通帧，不以数量变化声明性能收益。

### 身份

| 身份 | 固定值 |
|---|---|
| 直接前置材质批 | `c61ad5701`，本批实现和冻结快照源自其 M1 前置，产品路径不重叠 |
| 本批产品 patch SHA-256 | `c7bf494f4efeffcdb993da7da71b91575963b29ae04b620cbcaa993f1c227d10` |
| 联合签名 App | `5e41db87ff8fb4a26bfdb4e52570fe9675caf2b82ee4c1dbf0c8c6140a96e5dd`；同时含 M2，arm64 Debug `-O`，Team `H9QWU9XN8R`，严格验签 |
| 本机 provenance | `.artifacts/scene-architecture-continuation-20261102/` 的 `topology-*`、版本化 source freeze、原失败及 `material-frame-topology-*` 构建身份；载荷可用性按产物保留规则 |

### 验证

| 责任 | 真实结果与范围 |
|---|---|
| 动画 runtime | texture-animation、Timeline、named Timeline、真实 QuickJS 与 layer identity 门分别通过。覆盖同源/异源、先命令再销毁、旧句柄 stale、discard、hidden、跨 owner、Combined 共享 state、camera origin/zoom 双 lane 及幸存 owner 精确 clock |
| MPS 与事务 | BC uploader 使用产品 SourceUpdateTransaction 的 arm/didSubmit/cancel，保实际 Metal 输出与取消恢复；不是用自写事务替身声明原生命周期 |
| 帧/提交 | source-update transaction 与 Surface submission 最近门通过，原 GPU submit/commit 语义保留 |
| 暂停冻结帧 | 实际双 Surface App：存活 owner 在 frame0 销毁可见 Sprite，所有 Surface 先准备该帧再 commit；暂停后两次 resize 重绘仍命中原 magenta ROI，cyan UV 反例不命中。单次 VM cadence、frame0 可见/hidden 和实际退休均有断言，最终 gpuDrained=true |
| 同 Session 重建 | 实际 Host.applyDisplayConfiguration 以原 display ID、仅自有窗口几何变化进入 Session rebuild。前后 request/session 不变；两屏 window IDs 全更换；Sprite ID 各只剩 `[6]`；暂停前后 sceneTime 精确相同、driver inactive，恢复后 driver active 且时间推进，cyan peer ROI 保留而 magenta victim 不复活，最终 GPU 排空 |
| 相邻画面 | 联合 App 的半透明 named/三候选局部失败及两份不变原包在 M2 记录各自通过；这些身份不拆成虚构的独立批次 App |

原生夹具验证 Sprite/MPS 与普通合成输出，不以 source-material 的原 reachability 告警声称该 shader 组合已经通过 resolved 材质。两 Surface 为显式 DEBUG 载体，不能外推物理多屏或系统显示配置变化。

### 首失败及资格纠正

- QuickJS 首门证明同 owner staged destroy 后旧 TextureAnimation 方法仍可访问，现沿已有 journal 拒绝；同样保 discard 后恢复及 destroy 前命令。
- Timeline 旧载体缺合法 orthogonal canvas，camera target 未构造；补真实作者输入，不改产品去接受无来源 target。另两个旧相机硬编码值不符合其实际 30fps/180帧 owner clock，改用独立真实 playback 的 stop/seek frame150/paused 与 survivor 测试，比较完整 origin/zoom，不复制曲线算法或放宽误差。Swift 复合表达式的 typecheck 超时仅拆为明确 Bool，原值不变。
- 冻结 Sprite 原用 Boolean owner 自毁，现有语义当帧强制 visibility=false，因此没有待保留画面；改存活 owner 销毁目标并核当帧真实可见，原 magenta/UV 门槛不变。常量 color 改为入口接受的向量字符串；原失败日志和输入均保留。

相机 current topology 的候选/顺序及 preVM 消费、其余组件和普通产品 daemon 完整链继续按现役设计，不由本批关闭。未认领全语料、长期运行、性能/能耗、官方 parity 或正式 Release。


<a id="particle-retirement"></a>
## authored粒子活动实例退休

2026-11-03固定边界：Surface实际采用committed topology时，原PlaybackState和Runtime退出已销毁root/child、活动模拟及未来batch；重建装配先排除死root。可复用定义、child模板、健康peer与hidden实例保留。GPU pipeline只在该Surface实际采用时撤对应buffer索引，原completion强持已编码instance buffer至终结，未提交沿原cancel退出；不新增退休manager或每帧墓碑检查。

8产品文件净增26行，服务真实实例退出及GPU使用期；无新产品文件、clock、registry或cache。测试保原输入/失败邻例，并以真实实现核root/child退出、健康peer复用与冻结输出，不以代码体量或计数下降认领FPS/能耗收益。

| 已执行门 | 固定结果与边界 |
|---|---|
| Runtime | 61项选择中已执行部分通过，10个原有跳过保留；核销毁后不advance/不产batch、同源peer/RNG及hidden正控 |
| commit事务 | 运行原Session commit方法，平台边界仅记录；核root/child退休，不以该载体代替App |
| 真实GPU | ParticleRendering原门通过，弱引用证root/child buffer在GPU pending时仍活、完成后释放，健康peer保复用，未提交cancel原样释放 |
| 同输入旧/新App | 对照`a993632220c3b7628fe21ff0b0872e9771411a87e11df4406d91d1f6cdc81a47`与联合`ecc1900dd8fdc24d6678d1e54ef0786cf7491271513be109887be6908e2bcab5`；旧版两臂均保死root/child，新版两臂通过，同request/session、真Host重建后实例未复活、peer/ROI和stop/GPU drain保持 |

held臂从paused开始，frame 0销毁，只证明dormant child模板及冻结root输出；resize后仍有root像素，恢复和重建后仅保活peer。缺drawable臂仅故障末Surface的90帧，frame 74销毁前先取得双Surface至少四条非空child census，保健康peer frame 0完成、故障frame 74在retirement前及其后恢复首帧GPU完成。既有日志不直接观测健康peer frame 74 completion，不从源码顺序补写此结论。

最终测试输入冻结为`114913cf347bccfba9d6262a989e3833340ed06a2c49464d8395ca493e6d31d2`：原7秒duration、5秒候选门及60秒进程时限保持。held的resize 0.5秒、idempotent pause 1.5秒、rebuild 2.5秒及3.5秒resume分开；原同时动作导致待readback正确以teardown取消，不能记成产品失败。两步runner的accepted=false不否定实际pause/timer切换，门仍核true→false及inactive→active。原20尺寸正控在旧/新resize均仅36100红像素、低于新门1%；仅该退休fixture两侧改24尺寸，原阈值和普通fixture不变。

本机provenance归`.artifacts/scene-architecture-continuation-20261102/`的`particle-retirement-*`及`particle-text-daemon-qualification-results.json`；保原失败与输入资格纠正，不把销毁前未出生child写成活动child证据。App包含其他独立批次，不宣称单独Particle构建、完整语料、物理多屏或性能结项。


<a id="text-producer-retirement"></a>
## authored文字活动producer退休

固定2026-11-03：原pending帧输入携带实际采用topology的destroyed IDs，任一Surface成功提交后交唯一Text Store退休活动producer、raster及迟到任务发布权；全未提交和held分支不提前退休。prepared clone模板、source property输入和已冻结/在途快照保原寿命，FrameLayerTextureAssembly只装配当前文字成员。没有新CPU commit、worker、退休owner或generation镜像；5产品文件净增7行。

真实DynamicTextTextureStore门核queued/inflight销毁、删除后热改caption不再raster、clone及hidden正控；PausedFrameRecovery运行原采用方法，覆盖全失败、部分成功和冻结输入。联合App `4736a8b890528fe4fc6b7f7620a70435eaf9bd0c5b5f271d7f6020ded51dd845`的paused-text原生门通过，包含其它独立批，不称单独文字App。后续当前代码的prepared_text_clones、frame_texture_retirement及graph_texture_publication已通过，保真实clone与旧Snapshot/GPU使用期。

保留source模板不等于保留活动producer；隐藏和仍有消费者不当作销毁。代码与输入资格及原始日志见`.artifacts/scene-architecture-continuation-20261102/`的`text-producer-retirement-*`、`particle-text-daemon-qualification-results.json`、`live-input-text-qualification-v2-results.json`及`final-neighbor-*`。以上不外推任意字体/文字特效保真、全语料或性能收益。


<a id="system-provider-absence"></a>
## system provider清空的长期引用退出

固定2026-11-03：FrameTextureRegistry在accepted absent时，将system provider与原materialUserProperty同样移出committed/prior/persistent长期publication；原pending/discard保基线，已冻结或在途GPU资源沿原持有。产品仅原Registry净增3行，无第二资源owner、LRU或订阅机制。

同一新测试在旧Registry真实执行，12个clear/完成后的弱引用事实失败；实际Media Store clear反例亦失败，其他资格不变。新Registry全门与真实Store门通过，覆盖六purpose、accepted reset、discard/撤回、inflight及完成后释放。Store夹具使用原Inbox.clear入口，不把接受非空Data的publish错写为nil。真实SystemMedia IPC及共享Service另通过，但本段只关闭纹理publication退休，不冒充最后订阅退出或物理切歌验证。

provenance在`.artifacts/scene-architecture-continuation-20261102/`的`system-provider-absence-*`、`system-media-clear-old-v2`及`live-media-retirement-v3-*`，旧强持和新释放均来自实际实现；不以nil查找结果、RSS下降或日志沉默代替弱引用/使用期证明。


<a id="product-daemon-control-chain"></a>
## 实际产品入口的daemon控制链

固定2026-11-03：扩原Startup runner与既有DEBUG观察，选择实际经过requestDiagnosticPlayback→获取服务setAsWallpaper→产品通知/WallpaperManager→SceneDaemonClient→daemon/Host；不以直接Multiplexer.load代替。三处产品源改动仅承接本轮观察/既有属性入口，未增加控制owner、IPC或正常播放许可。

完整产品原生门在专用Debug.Startup签名身份`03f54235fb76fab2039bbce571d5c964f9d6229cc0099813f7bc6570102e103b`通过：首呈现和parent-finalized；同request/execution/PID的typed alpha热改及像素回执；暂停两次捕获冻结、恢复推进；同入口切B、新request/execution及同daemon；A实际launchResourcesReleased；产品stop、GPU drain、shutdown completion和精确子进程退出。严格验签，私有HOME/CFFIXED、Startup token/standard defaults、Steam suite和工作坊副本隔离，生产偏好保持不变。

首个brightness字段并非该solid真实消费者，原ACK=false是正确拒绝；夹具改用确有消费者的alpha，仍保0.15→0.85、原ROI/身份/退出门。startup_cross_runtime真实门及DEBUG/Release投递边界另通过。它证明这次冻结产品入口链，不等于普通UI点击、物理多屏、长期稳定或所有跨引擎组合；后续联合源码回验另登记。

本机provenance在`.artifacts/scene-architecture-continuation-20261102/`的`product-daemon-*`、`phase1-particle-text-daemon-startup-*`与`particle-text-daemon-qualification-results.json`。direct-client退出的另一调试链修复独立记录，不并入此产品链结果。


<a id="live-system-input-retirement"></a>
## Audio、Media及Cursor的活动需求退出

固定2026-11-03：准备事实记录真实material/source consumer与共享prototype/alias归属；原Session在committed退休、VM永久禁用/恢复等实际成员变化边界更新一次需求。Audio用真实脚本/Sound/粒子及prepared shader消费者，Media沿原lease acquire/release，Pointer只在活动owner集合变化时装卸原monitors。稳定帧不重扫variants/全图，不增加订阅owner；hidden、dormant、paused和bad-return不冒充销毁，活alias保需求。

AudioDemand、真实VM cursor/audio、Sound播放命令、SwitchEndpoint、SystemMedia IPC及共享Service实际门通过。IPC的新独立client先执行过订阅，因此旧绝对subscribeCount=1失效；现相对原计数验证同一demand只增一次，所有撤销/peer/晚ACK断言保留。Cursor用真实owner对象身份而非已合并的旧控制label，String通知沿原ValueRuntime回domain，不另存镜像。

四臂direct-client→daemon→Session原生门在联合App `ecc1900dd8fdc24d6678d1e54ef0786cf7491271513be109887be6908e2bcab5`通过：destroy与exception撤最后audio需求及实际NSEvent monitor；hidden peer与bad-return保需求和tokens至结束；同request/session/PID、真实呈现/统计、正常退出和精确子进程排空、冻结App/source/input及生产偏好指纹保持。用silence fixture，不证明物理音频采集；DEBUG media lease关闭，Media native撤订阅未测，不把IPC/Service层叠成完整系统切歌证据。

direct-client runner先等真实shutdown completion再terminate，退原固定0.5秒猜测；AppDelegate的direct模式退出与启动保持同一隔离判定，不误入普通产品保存。首轮原结束链超时、下一轮偏好指纹差异均保失败记录，修正后四臂一致；早期指纹差异没有具体键快照，不据此声称恢复历史偏好。进程证据保活动期实际command集合，避免临终zombie显示名覆盖已核App身份；cleanup仍按原真实进程核验。

本机provenance为`.artifacts/scene-architecture-continuation-20261102/`的`live-system-input-*`、`live-input-*`、`live-media-retirement-v3-*`和`root-live-input-*`。它关闭本次活动需求与隔离退出链，不认领整体能耗、所有输入API、普通UI交互或长期稳定。
