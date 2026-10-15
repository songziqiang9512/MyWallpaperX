<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。当前状态归[脚本覆盖表](../capabilities/scenescript-api-coverage.md)及[输入覆盖表](../capabilities/runtime-input-property-coverage.md)，剩余任务归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。
# Sound脚本控制、Vector热更与volume脚本（2026-10-12—16）

## 首断点与实现

3761619125的499.origin用普通Sound layer的play/stop/isPlaying选择四首MP3，旧入口却调用particle方法。补Sound四方法及显式startsilent，复用原普通layer身份、QuickJS暂存、typed owner effects、fixed-point验证、唯一AVQueuePlayer registry；原Video命令泛化为带destination的共享media命令并退出旧类型，一个64条预算，提交保持整个journal顺序。未加样本分支、播放器、时钟或回调遍历。声音普通帧仅发布状态与消费命令，不重建Program或surface。

真正运行继续暴露两个前置缺口：registry原在rebuildSurfaces后建立，但surface安装内已同步执行首帧，脚本先异常并永久失效；将同registry前移，候选仍暂停/静音，启动失败由原session stop回收。修复首帧后，五次选曲仍全部拒绝，因为属性热更只登记Scalar/String回调，Vector漏接；沿同consumer map登记真实applyUserProperties owner和已声明key，失效owner仍经all−active拒绝，不另解析脚本。

独审/负例同时闭合：捕获命令溢出不能绕过预算（共享count暴露overflow并由原事务拒绝）；纯value-only Bool仅查询，播放变更复用同权限检查；已提交Sound层销毁从同registry移除并stop，其他声音继续，宿主恢复不复活。作者pause/stop/startsilent和宿主暂停独立；ready回调服从同意图。脚本stop可逆定位归零，registry stop仍永久退役。

## 官方行为与边界

官方2.8.0.42、自有2.000秒MP3黑盒：loop同callback play/pause/play/stop/play后查询为1/0/1/0/1；single自然结束及显式重播、stop归零、pause续播成立。独立双层同时play，1.334秒只B再次play，A2.325秒结束、B3.327秒结束，证明**播放中的single重复play从头**。公开短描述未定义该位置语义，撤销最初“幂等”推断。实现复用同player，播完空队列仅显式play重建item。

loop重复play位置、宿主暂停官方对照、OGG/random/spatial、volume脚本字段、设备变化、桌面产品入口、完整听感/全图parity均未证或未实现。宿主保留作者意图是本产品生命周期合同，不能冒充官方实验。R1/R2缺正音频对照不能定案；R3低音量正对照与R4独立反例才采纳。未读私有实现，guest自有项目已按身份清理并恢复实验前状态。

## 验证与保留

生产Program/Registry真实AVQueuePlayer门26项通过：静音WAV实测时钟、pause位置、stop归零、single重复/自然结束重播、host与作者意图、批次原子拒绝、逐层退役及健康peer继续。seek后固定150毫秒观察首次红，改有界等待仍要求归零、同player/item、继续推进后绿，未放宽产品行为。

证据提升因现有1 GiB缓存已满被工具拒绝，prune无到期候选；未抬预算或删除未知旧证据。本批最小结果暂留`.artifacts/tmp/sound-control-20261012`：两个最终运行的日志/身份、热切后一张截图、官方中性合同与验证收据压缩包。样本副本/HOME/重复截图及重试缓存收尾删除，待现有缓存按规则腾出空间再提升。官方中性合同SHA b874ba2a619db94a7670cdca8e0be3fe9dc64ecd5cca98814e5812a7a621d03a；保留必要截图/自有输入、红绿日志、构建身份及独审，实测结果见下。只复用`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`一份构建缓存；真实用户样本保持只读。本批无push。

真实包隔离direct Host：499.origin init成功，四首MP3准备成功；music 0→1→2→3→4→0连续5次热更均接受，同session/surface/window，正确stop其他曲目并play目标；每次play后500毫秒实际AVQueuePlayer时间分别推进0.486561/0.477935/0.542967/0.540291秒（4/4，rate=1、status=playing）。初始ready后的clock落在选曲前，不能用其advanced=false或缺KVO日志推断故障；仅DEBUG测试入口在play后复用原clock观察。隔离运行静音、频谱silence fixture，证明播放器时钟和脚本链，不证明扬声器听感、系统采集或桌面daemon入口。

同一最终App默认music=1启动也提交选曲：499播放时间从0.018517推进到0.591753秒，其余三层保持rate=0；两个最终进程正常退出。session激活、属性状态和hidden消费者回归22项通过。

QuickJS Sound门1方法20个合同事实、Vector live门1方法11事实通过；Video value/cursor8方法、particle/storage事务15方法、solid20方法及routing/source/门选择113方法通过。原hidden-property夹具缺Camera bloom.hdr元数据，在HEAD同样编译失败，补齐stub后原5断言通过；未修改生产判断。独立只读审查覆盖最终产品diff；纯Bool写权限、捕获溢出、Sound销毁和跨destination提交顺序问题均在收尾前修正。构建/有限运行不是全样本或完整官方parity。

结构、职责、设计、断言、文档及产物门通过；residue门唯一未通过项是既有`MyWallpaperX/Core/SteamWorkshopScene/.mimosa`（1文件218字节），归属未证，原样保留。不声称全仓门全绿；未执行自动选择的130余测试模块全量回归。源码构建与本批最近的合同/事务/生命周期回归成立，剩余渲染断点仍归N03/N06。

<a id="sound-volume-script"></a>

## Sound volume脚本后继（2026-10-16）

**通用语义。** 先前IR保留的Sound `volume`纯script wrapper未投影到Scalar owner。现exact object/path、`script/value`或`script/scriptproperties/value`经原Scalar VM产生typed `.layer(.volume)`，由原cadence settled snapshot进入唯一Sound Registry/同一AVQueuePlayer。原Sound Program纯compile前移，以真实资源/模式及raw IR seed与resolved启动seed一致性做迟准入；planned/requested/construct/fallback共用排除，不加descriptor种子或第二player/clock。现有finite `[0,1]`为项目边界，公开volume/update没有给出越界clamp合同，不外推官方数值语义。

snapshot writer只消费无direct property key的binding；旧即时property writer仅有key的binding，集合互斥，无关属性不把脚本音量重置成启动值。暂停时旧direct编辑仍立即生效，脚本保原冻结cadence；mixed outer-user未来须先设计唯一暂停publication并退出旧writer，不能用override map补。相同base/effective gain避免重复AV属性写，详细增益日志仅DEBUG诊断入口限16条；master/mute、play/pause/stop/startsilent、退休及GPU不可用下CPU提交语义保留。本批没有性能测量收益声明。

**最近门与身份。** 修前真实Swift/C QuickJS输入1条、投影/owner为0；修后新门82 facts全true（60.114s），旧Program/命令27 tests通过（62.734s），列明输入hash稳定。含三组变量/资源改名及等价表达式、同owner/player/item、增益/paused direct/master/mute/意图、无关更新、数值失败恢复与健康peer、资源/seed/typed target/Timeline/OGG/random/spatial等反例。异常/预算是运行期局部保留，不称构造0owner；未另扩模块构造故障矩阵。默认Developer ID Debug构建23.356s、4278输入无漂移，deep/strict验签通过；App executable `d4745492a26d7fe55489f61f65d48e5e7ac60d2ef6b2c7e0f706c6095562a38d`、dylib `1254b545197032ce9f1a2117959535fd2709e3724c5bbe5b11c91c88885ebe80`。Sol Xhigh最终独审7产品文件GO、0 finding；源码/设计/断言门通过，不执行无区分全矩阵。

**实际App边界。** 原包3800728730:23从0到1 Scalar owner，music两次热改接受且同window/surface，Sound clock推进，画面实际查看正常；没有该开关改变gain的证据，不把Bool推断为音量数值因果。首轮继承公共静音，后轮仅用进程参数解除静音，未改用户偏好。为闭合增益链，隔离派生副本仅改该volume wrapper和自有slider声明、保原画面/MP3资源；真实native gain为`0.4→0.1→0.4`，两次热改接受且window41214不变、无callback失败、正常退出/GPU drained。首个自有fixture漏声明scriptProperties产生局部异常，补公开createScriptProperties声明后才通过；失败尝试不计结果。该派生门不是原作者公式或官方听感对照。

独立原包3743305891未参与修法，实际FLAC layer107时钟`0→0.422002`、rate1，人物/日期/频谱画面已查看，正常退出/GPU drained。候选3662790108冷运行在120s预算内未ready（prepare-catalog约70.338s已包含model-build约43.313s，嵌套计时不相加）；看门狗精确回收，未获得该样本画面/volume结果。此为启动大成本线索，尚未定位可避免owner，不计性能回归归因或成功。未验扬声器听感、正常daemon/原生面板本片入口、多屏/设备热插拔；4处nonnull outer-user冲突、3处OGG、handle volume setter及原样本其他未修视觉继续保留。

**材料。** 最小hash/neutral结果、压缩日志及原包和独立实图留`.artifacts/tmp/sound-volume-script-20261016`，本轮样本/HOME/缓存和重试重复图退役；沿用唯一`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`。未抬已满证据提升预算，未删除未知旧材料。Windows VM按用户要求保持运行；未推送。后继先核现役队列共享global/scope正确性静态反例，真实收益须另证，不重启U40无合格载体实验。


<a id="sound-mixed-volume"></a>

## Named Slider与条件输入后继（2026-10-16）

**通用语义。** 普通Sound volume的精确`script/user/value`或`script/scriptproperties/user/value`有限Number现可复用同一个Scalar owner。外层Slider作为原typed下层输入，内层条件沿既有codec；raw seed与resolved当前值分域，最终构造成功才由Sound Program移交writer。旧direct仅保未移交target；增益始终经settled snapshot到原AVQueuePlayer，没有第二播放器、输入缓存或clock。合同与边界见[D4](../roadmap/batch2/script-component-api-design.md#sound-volume-named-input)。

**暂停及相邻修正。** 即时与deferred提交前复用原Transaction完整committed snapshot做scoped刷新，只求值受影响mixed owner；未知声明输入保codec fallback，不造schema。显式mode跳timer/media/ended派发但保Promise drain，未选owner/Timeline/transform保持。partial C镜像的reuse修为保留current origin，原全量publisher继续承担更新；未提交镜像沿原discard恢复。副作用仍走原journal/fixed-point/storage和共用commit，暂只接Scalar结果与Sound命令；其他副作用拒绝整个owner。typed下层fallback与整笔取消分开，任意JS堆回滚不在保证范围。

**可比事实。** 前资格App对原314的Combo真实改值拒绝，instruction=0/callback=0且rebuildRequired。候选同原project/pkg六次Combo/slider更新全部接受且窗口/surface不变；暂停三次刷新保持frame31、sceneTime1.096516。恢复后实际窗口可见壁炉、时钟与音乐UI；早期暂停图仍处作者暗入场，不当渲染成功正证。另以隔离派生只替volume为自有`v*.5+.1`、raw=.2/default=.4/启动覆盖=.8及缺失declared input fallback：基础增益.5→.3→.4，主音量.5后的实际player增益.25→.15→.20；四次暂停刷新同frame31/sceneTime1.105989，七次编辑同窗口。自有条件命令可达pause/play，宿主暂停时play保持rate0。派生不冒充原作者算法或听感。

**真实面板。** 普通App→Client→daemon原包将Volume .5改.8、Fireplace Sound On改Off；关闭重开仍Off且Volume条件隐藏，再改On恢复.8，reset回On/.5。全程仅1launch、1candidate/active session `A1A2EA46…`，停止前0 Sound stop；最后Stop两声源、Quit exit0且输入无漂移。只证明本次编辑/重开/reset避免重建，未量化CPU/GPU、延迟、RAM或能耗；不计面板专项完成。独立原包3747190633实际可见角色、时钟及频谱，exit0/输入稳定，未见本批相关缺损，不计整样本parity。

**门与审查。** Debug最终41.453秒、4279输入无漂移，exe `115d9508…`/dylib `cedb7f26…`，deep/strict签名通过；两次Swift编译错误原收据保留。Sound行为门236事实通过，覆盖三组改名/等价式、raw/current分域、VM/player、错误返回/资源/构造、direct退出/退休、显式mode与partial getter/rollback。初轮15失败来自fixture把Looper跨阶段item固定，改为先确认非nil、紧贴每次gain提交检查item及queue不变，跨阶段仍核同player/owner；产品未因此修改。Scoped Transaction 13项有效结果复用。独审先发现deferred漏刷、partial origin回退与缺schema输入scope，均在最近owner修正并补审。

**未覆盖与材料。** deferred visibility与Sound同key实际资源组合、故障后整笔Session取消、多surface、native暂停操作、完整听感/官方parity、OGG/random/spatial及handle setter仍开放。最小hash、neutral结果、压缩原日志与必要实图留`.artifacts/tmp/sound-mixed-volume-20261016/`；临时样本/HOME/cache及编译探针当轮退役，唯一连续DerivedData沿原路径保留。Windows按用户要求保持运行；不推送。后继按现役队列选真实缺口，不以本片闭合宣布性能或能力全完成。
