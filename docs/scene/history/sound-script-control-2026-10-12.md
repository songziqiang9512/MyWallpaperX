<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。当前状态归[脚本覆盖表](../capabilities/scenescript-api-coverage.md)及[输入覆盖表](../capabilities/runtime-input-property-coverage.md)，剩余任务归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。
# Sound脚本控制与Vector属性热更（2026-10-12）

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
