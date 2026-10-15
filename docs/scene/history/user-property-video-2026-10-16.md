<!-- document-role: historical-evidence -->
# 本地视频用户纹理：资源事务与有界验收

> **历史证据 — 非现役入口**。截止：2026-10-16。本批补原属性链的本地视频入口；相邻format metadata反例、最终构建/审查及真实前景复验均已通过；只计本片有界验收，不代表整专项、整样本、官方parity或性能完成。

稳定职责归[资源准入](../architecture/scene-resource-admission.md#user-video-property)，当前能力归[属性覆盖](../capabilities/runtime-input-property-coverage.md#user-property-video)，后继顺序归[属性卡](../roadmap/properties-panel-card.md)与[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

## 问题与最小能力

原编辑器、验证及prepared资源只接PNG/JPEG，合法视频选择没有持续播放consumer。
本片接本地MP4/MOV/M4V；一个key的完整prepared需求必须全为PMA，其他用途整key拒绝。
同一文件可由不同属性key各持独立播放状态，不按样本、属性名或文件名派算法。
每key Source复用既有AVPlayer执行链、SceneClock、Registry及最终输出owner；embedded layer/asset路径保持原职责。

## 实际资源与提交链

原loader在后台流式写一次私有快照，复用共享SourceKey前后校验原来源与snapshot。
单文件上限1GiB、单次读最多1MiB；取消、30秒检查间隙期限、regular file和实际大小失败清候选。
这不是OS阻塞I/O绝对中断保证；bookmark仍是持久来源，临时路径不写回用户意图。
prepared declaration与Source共持引用计数文件lease，最后引用退出删除；Source不再重写同一视频。
Registry candidate在prime期间不进live集合；唯一epoch即使失败也不复用。
同一decoder取得item0 buffer并导入Metal，只存seed，不先推进Scene lifecycle/frame/generation。
Session复核当前record/program/device/Registry/revision/cancel与snapshot，再无yield采用资源、值及全部当前views。
首个active prepare经原pending事务发布seed；至少一surface提交才共享commit，全deferred/drop保seed重试。
暂停采用保suspension；surface重建复用decoder/位置，reset恢复原absent/default，不重置SceneClock。
clear/stop取消准备，旧候选不能回流；scope等读取实际退出才释放，GPU引用保原backing/预算lease及drain。

## 自有行为门与边界

| 门 | 已记录结果 | 能证明与不能证明 |
|---|---|---|
| Native property video | 同次编译2 tests、56 checks与2个改名PMA MP4变体PASS；每变体59次GPU读回、24个generation | red/blue持续实际输出；不实例化Host/Session或物理多屏 |
| 媒体验证 | MP4/MOV/M4V正例；audio-only及坏媒体反例 | MOV/M4V为metadata资格，不当连续播放GPU证据 |
| OwnedFile | 13项真实I/O/ARC门PASS | SHA、最大单次读边界、超额/取消/源变、最终lease删除；无测试专属API |
| Control | 44项真实Loader/Session行为检查 | 控制边界部分stub；不当真实窗口/GPU事务 |
| 原asset/layer视频邻例 | 两个native变体各34 checks PASS | 原decoder/publication与layer/asset身份回归，非全部codec |
| 旧图片入口 | JPEG/PNG全purpose 20 tests PASS | 保原decoder/purpose合同，不扩大图像格式 |

Native与OwnedFile门的TemporaryDirectory媒体/module cache按各receipt退出清理。
producer metadata修复后的同次native编译覆盖真实producer与持续GPU；未改的旧门复用边界仍按各receipt，不能混写App身份。

## 正常App的原生选择与重放

隔离正常App通过真实NSOpenPanel、Service及daemon执行：MP4→关闭重开保文件名→MOV。
坏MP4被明确拒绝，MOV选择仍保留；逐key reset显示作者默认，再Stop。
热编辑全程只有session `DF82700B-EC26-46E5-B455-CCD6F2577E33`，只有一次activation。
Stop后再次明确选择MP4，离线metadata验证保存；“设为壁纸”启动新session `F6AC29F5-67EF-42E2-B83D-8E0665985B5D`，首GPU completed，随后Stop/Quit。
reset/Stop及最终Stop后owned视频快照均为0；普通App退出码未保留，精确进程消失另核，不能写成exit0。
一次过快GoTo/paste复用了坏文件选择，已丢弃；重试先确认真实MP4选中后才接受，不计无资格尝试为产品失败。
该路未捕获正常桌面像素；UI选择/持久化与实际视频可见分别取证，不能互代。

## 真实输入与实际可见结果

3357627941的背景 `_916` 已准备，但被前景遮挡；`selected-video-screen`不算视频可见证据。
初次matrix用了不支持的`user_texture_overrides`，原runner读取`texture_overrides`；该轮335只作默认图片control。
`screen-input-correction.json`记录纠正；不能把默认control改称视频已执行或可见。
最终前景改用有真实consumer的`newproperty`，同key typed filepath进入原资源链。
修复前Root查看`foreground-video-screen/scene-series-0000/0001`：完整蓝画面→完整红画面，先证明该输入的持续视频输出。
该轮PID37577，exit0、timedOut=false、reaped=true、elapsed28.5186s、inputDrift=[]、stopped/gpuDrained=true。
最终producer修复后，Root重新查看`foreground-video-final`两张PNG，仍为完整BLUE→完整RED；`real-screen-observation.json`已改指最终图。
最终轮PID40562，exit0、elapsed29.839743s、timedOut=false、reaped=true、inputDrift=[]；phase=ready，stopped surfacesBefore1/After0、gpuDrained=true。
最终签名executable SHA为`3a80ea1360e81ff21c2da8d73fce589a8fc76c7ce66e233ee19e17d0ab858cd4`；不把修复前截图冒充新App身份。

独立3662390671原样WebM layer185保持人物/背景正常，398次publication、PTS0…7.983并1次wrap。
该轮exit0、reaped=true、timedOut=false、GPU drained；没有把WebM扩为用户文件输入。

## 相邻缺陷与最终收口

相邻静态P2：外部property视频错误携带`authoredFormat=rgba8888`，现役format-combo仅匹配nil。
SourceDomain以真实producer的两个改名变体复现before-fix FAIL：publication完整但authoredFormat=0；不是半publication或缺decoder。
修正只应让无TEX authored format的外部视频保持nil，不能改物理纹理、放宽typed purpose或修改其他producer。
修后同次native编译2 tests与56 checks PASS；self-owned现役format-combo的slot/UV/resource两个变体均取真实production launch=[nil]，runtime nil匹配，generation1→7不改key；rgba8888控制确实匹配失败。
Source修后SHA为`c20ddb15a963987d1bd6e72824abc6fbe5441676770625bedb637cb9cc46f1e0`；最后产品独审ACCEPT，其他21个产品文件与先前审查一致。
最终Debug build exit0、21.448s、inputDrift=[]，24个输入SHA一致；上述新App前景短复验与独审共同闭合本片有界结果。
IPC control-plane 2 tests PASS；初轮历史fixture缺callback metadata及发送端request-ID模型，仅修同fixture envelope并保所有原断言，新增foreign accepted不能换发送端ID反例。

物理多屏、HDR/alpha、更多codec、WebM用户输入、非PMA用途及完整effect/particle形态未扩。
没有同条件性能测量，不计CPU/GPU、内存、启动或能耗收益。
U40连续三轮拖动只登记后继资格，尚未fresh复现；N08负值/world语义继续unknown。

## 证据身份与保留

本机忽略根为`.artifacts/tmp/u41-video-property-runtime-20261016/`、`u41-user-property-video-native-20261016/`与`u41-video-file-20261016/`。
`normal-ui-hot-edit-receipt.json`、foreground的`execution.json`、native `receipt.json`与OwnedFile receipt保存具体操作/输入SHA/边界。
runtime根`cleanup.json`记录243个精确删除项：自有App/HOME/workshop/CLI环境与媒体、raw JSON、生成Metal/GLSL及冗余PNG已清，日志gzip；owned App active=[]。
仅保最终BLUE/RED两PNG与366 holdout一PNG，runtime根约10.42MB小报告/日志/截图；唯一DerivedData为`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`，供U40直接复用。
提取到`u41-video-property-20261016-final`被evidence cache总预算拒绝；prune-expired removed=[]/retained=[]，未知既存证据未删。`final-evidence-report.json`及三PNG暂保原精确runtime根，明确此保留限制。
真实用户媒体全程只读；提交、推送与发布状态由root另行汇报，本记录不授予相应授权。
