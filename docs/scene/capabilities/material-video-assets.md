<!-- document-role: stable-contract -->

# 材质视频资产合同

本页视频入口与定位发布合同已实施；下方按可见性推导消费需求仍待实施。动态实例与实际消费者退休归[D4](../roadmap/batch2/script-component-api-design.md#prepared-dynamic-video)；切换呈现设计见下节。

本合同扩现役Scene视频owner的材质入口；能力与实际证据归[台账](coverage-ledger.md#current-overview)及[批次记录](../history/material-video-assets-2026-10-12.md)。

<a id="material-video-assets"></a>

**材质视频asset/fallback合同：** catalog不持播放器，视频声明的`preparedVideoColor`只承诺发布合法颜色帧，不冒充ready；实际decoded frame仍验证alpha/purpose/publication，未知或straight alpha局部拒绝。asset沿原SourceKey/device/session共享源，逻辑asset、source incarnation、epoch和generation各保identity；不虚构layerID，不进入layer脚本控制。原timing传入各surface bridge，同帧prepare去重，video由原registry跨屏统一commit，atlas仍逐屏commit/discard。fallback选择与solid采样都只接完整typed videoAsset，静态图片及其他provider原准入保持。selected still优先，empty/reset恢复作者视频并保Scene-clock相位；原全局pause/resume、rebuild重取、source换代及stop取消管同一source。现役材质入口按potential demand存续，尚无active-demand执行；本片不证明解码能耗优化、任意purpose或完整普通material组合。设计取舍与有界后验见[归档](../history/material-video-assets-2026-10-12.md)。

只接已准入的premultipliedColor需求；data/normal/flow及未知颜色表示不猜测。现video线明确linearClamp，不由未知TEX flag、文件名、路径或hash选择颜色/alpha/采样算法。普通帧不解析媒体声明，不建图或新播放器。SourceKey只界定资源身份；sample/layer/截图是回归身份，不能参与视觉派发。

<a id="video-position-publication"></a>
## 播放跳转与新帧发布

逻辑视频位置改变后，旧解码序列只能保last-ready，不标成目标位置的新generation。定位、后台推进与呈现提交分责，有界验收归[运行证据](runtime-evidence-current.md#video-position-publication-20261022)。

- **唯一职责：** Lifecycle管Scene clock/intent，原Source管同item、目标与UUID的单一定位状态。currentTime/stop、真实EOF与改变duration映射的loop切换要求定位；普通rate/play/恢复只重锚，不每帧seek。
- **事务边界：** 共享SceneClock与模拟已在呈现前推进，不因普通拒帧回滚。已启动Source的drop只撤计划/提交，不暂停、不恢复backend anchor/event/position旧快照；删除该回滚旧路径。仅首次start起点被拒时恢复原logical状态并重新定位，已确认EOF优先。命令使旧plan失效时，同index也重新准备。
- **方案与取舍：** 复用零容差异步seek完成屏障，再由下一prepare按最新Scene相位重锚和取图。completion只记backend完成，不改逻辑时钟、恢复播放或发布；失败继续last-ready。已证setRate后立即取图不够，不凭display-time容差筛帧，也不重建output/player。property priming原独立operation/seek/preroll/seed保持。
- **解码与发布：** copy已经acquire的像素不可用帧回滚撤销。原Source至多保一份未发布decoded payload；同source、相同有界目标可重用，按当前plan生成publication，成功commit才推进generation/last-ready。新定位、目标变化及stop清候选；不拿旧last-ready冒充新解码。priming seed保持独立，复用同Frame构造，缓存不另持播放器或输出owner。
- **覆盖与退出：** 同目标命令仍更新逻辑时钟；同item、在途或完成且backend尚未离开目标的相同定位可复用，避免重复命令在取图前重启seek。播放重锚成功即退出ready，暂停定位在首commit退出；6→2→6必须新token，不永久按数值去重。新目标/stop/退场使旧回调无效，缺item先保请求；拒帧不撤销真实定位。保负loop相位等待、非loop停止、generation仅commit与取消/late install；来源不ready局部保last-ready，不能整景失败。
- **观测与验收：** 旧字段`decodedItemTime`记录AVPlayer的display deadline，不保证源packet PTS，不用于定位资格或筛帧。首新真实像素、等价目标/覆盖seek、暂停/EOF、同index拒帧重试及原WebM/priming门覆盖行为；Debug和真实seek消费者、独立视频补画面。失败撤候选，不以正确性修复认整体性能收益。

<a id="video-switch-presentation"></a>
## 视频切换首帧衔接

**目标与触发。** 自动脚本、属性选择及动态视频重建共用原视频/合成链。上一正常提交呈现的普通视频来源已退出，而当前实际可见编码所需的新来源尚 pending 时，短暂保留上次显示结果；同 Source 换 layer ID、单纯增添 optional 视频、隐藏/离屏源及首次启动不触发。不配对排序位置、图层名、样本或资源路径，不将旧视频帧伪装为新来源 ready。

**唯一职责。** 沿原 Surface/PreparedFrame 保存最小上次呈现提交来源事实及一次等待截止点，来源使用现 Source incarnation，不能因每帧新 layer ID 或连续改选而续期。现初始就绪只按层visible筛选，尚不代表alpha或离屏资格；本片复用原quad `projectedGeometry` 裁剪及实际encoder的alpha，模型矩阵在原准备边界算一次并交encoder复用。只收直接mainPass、实际选择ordinary authored source的需求，原startup/group规则不改，未知group/named/effect依赖不猜扩，不另造可见性算法。原 GPU、Source、graph 与脚本事务照常提交，只暂缓唯一 `present(drawable)` 和相应可见通知，让系统保留上帧；不走 cancel/deferred 或启动 cohort 去冻结 VM、回滚媒体 clock。逐 surface prepare→submit、共享 provider 最终 commit、HDR/SDR及现失败回退保持。

**退出与成本。** 新帧 ready 即呈现；取消、永久 unavailable 或决策点的现 hostTime 上最多 250ms 到期立即退出等待，沿原局部降级。Scene 暂停时继续既有资源重试，不能因一次 GPU 提交睡死。只保有限来源/截止数据，不增视频 owner、时钟、全屏拷贝、history/FBO或淡入淡出算法；同源普通帧不反复启动等待，也不为此提前解码所有候选。

**验收。** 最近真实提交门覆盖 pending→ready、同源重建、仅增 optional、连续选源不续期、失败/到期/暂停重试及多屏提交/取消；测试真实 Source/PreparedFrame，不复制业务规则。原包自动时段与全部主题切换检查实际显示连续性，另用未参与修法的切换视频及原双视频/Xray核对。readback 候选画面和真正已呈现画面分开，不能用提交 FPS 或 ready 冒充没有黑闪。稳定内存/能耗另按同条件测量，不预授收益。

<a id="video-consumer-demand"></a>
## 待实施：视频消费需求与后台解码分离

目标是避免无消费者的并行解码拖住可见视频；资格见[同App输入消融](runtime-evidence-current.md#video-publication-demand-20261021)。不以隐藏、离屏或同源直接判定可停，不改作者内容降低负载，也不把动态视频创建失败合并为此优化。

- **职责与数据流：** 复用prepared图的取源/命名依赖与typed可见性、播放intent形成消费需求；Session在共享帧汇合各surface需求，再交原registry/source决定backend是否工作。未知依赖、脚本帧/EOF观测需求保守active；asset/property视频先保原路。不新增需求registry、时钟、播放器池、图或最终输出owner，普通帧不解析脚本、重建图或扫描资源。
- **逻辑与backend分离：** 脚本命令/snapshot、起点、相位和终结必须先资格，不能把当前eager实现反定为官方合同。10-21官方自有隐藏载体的播放状态、currentTime与EOF回调呈混合行为，原advance/held判据均未成立，保持STOP_UNKNOWN，暂不接dormant。现prepareFrame同时负责首次启动、anchor及依赖backend的loop/非loop EOF，不能直接skip或借全局pause/suspend。恢复必须复用唯一source，未ready保last-ready，不从零重播或伪造帧。
- **identity与失败：** 同源不同owner/播放intent不合并。跨屏取并集，单屏缺drawable不能停另一屏所需source；需求不能在一个surface拒绝后覆盖共享生命周期。原epoch/command generation、候选/commit/discard、GPU持有texture与stop/rebuild/迟到回调继续生效。不能证明无消费时退回当前eager行为，不能扩大黑屏或整帧失败半径。
- **切片与退出：** 无图像消费者的帧提取/Metal包装原型已因非目标footprint退步撤回，限定结果归[运行记录](runtime-evidence-current.md#video-publication-demand-20261021)，不重复同型验收。10-30关联/输出资源退休原型因原包footprint峰值退步撤回，见[后继反证](../history/video-instance-observations-2026-10-29.md#video-output-residency-20261030)；后继须有新的实际物理驻留/供帧依据，不重复这两种原型；保原prepare/anchor/EOF与last-ready，任何首次prepare前汇合跨屏需求，未知依赖保持eager，不合并不同source/intent。dormant另待隐藏行为和typed clock资格，dynamic createLayer另立切片。覆盖改名/等价输入、隐藏→显现、seek/rate、真实loop/EOF、跨屏拒帧/重建/停止及独立真实视频；资格或收益不成立撤候选。

普通优化配置的同输入前后对照须证明可见视频供帧及CPU/内存收益且无非目标退步，按[性能卡](../roadmap/performance-convergence-card.md)风险分级，不把删除输入的消融当性能验收。动态视频实例另需prepared资格、来源及消费者身份、拓扑事务与资源复用/退出设计；不能为绕过null直接放开constructor，更不能照作者每帧destroy/create就重复写MP4、重建播放器。
