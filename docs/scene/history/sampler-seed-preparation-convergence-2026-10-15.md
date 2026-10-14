<!-- document-role: historical-evidence -->

# Sampler seed 准备复用（2026-10-15）

> **历史证据 — 非现役入口**

本片现役结果/选序归[性能卡](../roadmap/performance-convergence-card.md#sampler-seed-preparation)，准备/失效职责归[启动合同](../architecture/scene-launch-responsiveness-contract.md)。沿原template与variant准备链消除重复unconditional sampler bootstrap，不新增缓存、调度器或另一份schema权威。

## 归因、实现与最近门

初次`warm-capability-attribution`的A2带sample资格窗中，capability阶段23.893s，四worker重复进入bootstrap；它用于定位，不是无sample收益基线，也不证明整段时间全属bootstrap。

原调用者已为同一不可变template算出完整unconditional seed，却在`launchAvailabilityMasks`再次bootstrap。现于reachableSamplers与variant构造两处将该seed传入原helper。原readiness投影、256 masks安全fallback、固定点、variant集合及逐node eligibility判断保持；没有改变shader内容或扩大准入。原Profile改为per-call start+defer，修并发共享start覆写并覆盖throw；total/rest是重叠worker区间之和，不是CPU或wall，旧success与新attempt计数口径不作集合等价。

4产品及3最近测试路径freeze aggregate `1359a6cad64b0ceac4675dd06ec7fb13f48b997a5ede007c9c9c4619c2ec6d39`，完整逐路径SHA在`proof/candidate-freeze.json`。5个shared-presence真实行为/actual Metal方法及2个受影响async方法通过；历史source-set重复storage组合改有序union，删除async旧调用拼写断言，不改变产品语义。独审最终源ACK；code-health PASS，test-assertions仅HEAD原有5项遗留、无新增，不扩baseline。

一次Debug构建23.946729s、inputDrift=[]；B App executable SHA `31608b5e13133164800418b89a67550c36b3fe5f8851efc590b156b7bd9b8119`，C `29891b0579beef0855a3bb05e76fd193c4755469aee6b6cd8e8e49f8d2833ed4`。最近门与构建分别证明其范围，不代真实像素或完整variant census。

## 五对无sample启动资格

冻结Debug daemon入口、单surface、60fps/output mute、原属性/媒体与既有copy_sample/package选择；每臂fresh PID/HOME/tmp/副本，原generic cache共享，单PID内binary archive由A1建立、A2实际hit。五步为L0(3766415113)→A1(3042492564)→B1(2932157836)→A2→L1；每步等待matching request/record的firstFramePresented及两次rendered推进的frameStats。没有sample、截图、profiler或稳态窗；mute不等于冻结音频/外部媒体。

主指标是A2 request发出至匹配firstFramePresented的观察wall。首对B/C短筛有效后原样复用，补四对顺序C/B、B/C、C/B、B/C，不重跑首对、不混入带sample资格窗。全部normal shutdown/exit0、GPU drained、sampleAttempts=0，源/App/工具freeze无漂移。

| pair | B A2 ms | C A2 ms | 配对降幅 |
|---|---:|---:|---:|
| 1 | 25824.196584 | 17289.392958 | 33.0496385366% |
| 2 | 26530.556542 | 17202.178667 | 35.1608827362% |
| 3 | 26122.844708 | 17249.727584 | 33.9668869267% |
| 4 | 25563.766083 | 17054.958334 | 33.2846409303% |
| 5 | 25441.313583 | 17043.962541 | 33.0067510650% |

配对降幅中位33.2846409303%，B中位25824.196584ms，基线噪声`max(abs(Bi/median(B)-1))=2.73526402149%`；≥10%、>2noise及noise≤5%的主门通过。原`formal-remainder/result.json`状态为`PRIMARY_GATE_PASS_SECONDARY_REVIEW_REQUIRED`、performanceAccepted=false；不提前认领完整性能验收。

原emitted admission/rejection、实际consumed prepared tokens与archive事实一致，支持已发射证据无回退；未导出完整Program/precompile variant身份集合，不能由计数、Profile total或部分token推导完整集合等价。此前ready-request-wave STOP仍成立，本片不是调度优化或重启旧波次候选。

## Secondary与普通原生画面

独立复核接受保留实现并窄接受暖A2启动目标，secondary仍未接受、performanceAccepted=false，不称完整性能PASS。后续核对发现C sampler的CLOCK_MONOTONIC与Python事件原点差5.313–5.316s，原CPU/内存筛窗直接混钟；旧整表内存数值/噪声、last点时间位置及旧CPU范围全部撤回。9份无效派生逐SHA留档，`secondary-correction/withdrawal.json`明示撤回，40份raw不变；Python同钟的五对A2主指标和stage wall不受影响。

唯一有效重算单据为`secondary-correction/corrected-secondary.json`，窗口统一用原行Python receivedMonotonicNs；receipt是采集时刻上界，不是精确采集时刻。十臂receipt内累计CPU差范围B为94.390–99.268 CPU秒、C为55.980–61.792，覆盖长度不同且含旧active293，不能称精确整phase或隔离compiler CPU降幅。原十臂首帧后只有各1–2点短观察，不证明稳定RAM、精确peak或资源drain；逐帧GPU/present尾部分布 unavailable。

一次独立B→C `memory-followup/result.json`不混入正式五对：A2匹配firstPresent后固定观察+8s，+5–8s每臂各3个receipt点。B footprint中位827,983,336B（827,934,184–828,032,488）、resident中位289,898,496B（289,816,576–290,258,944）；C分别805,422,616B（804,734,488–805,455,384）和432,963,584B（432,832,512–433,029,120）。C在+0.725→2.732s的footprint从1,116,309,184→805,488,152B、resident从570,195,968→433,340,416B后进入短平台；晚窗footprint低于B，但resident高143,065,088B且未回落。单对不证明RAM收益、稳定回退或纯瞬态，secondary保持未接受。

两followup均exit0/GPU drained/sample0、archive hit125/compiler operation0、已发射语义事实同，4个PID消失。下一批先按事件对齐分类resident/footprint来源，不重跑startup五对；必要时再追MDL reader重复验证，旧NO-GO保留。

最终C App普通原生入口实际播放3042492564，parent12548/daemon12558、request `4D9F6CB0-847E-445C-9981-5E8957AA9039`、session `DF34A0B5-A2FD-4497-833D-2A352E938E7C`、surface1。root实际查看星空人物、粒子、07:11时钟/date并与前次native保留图对照，未见本片相关缺损，不称逐像素等价；实际Stop后71/71 VM quiescent且failures/timers/jobs/mutations/dynamicLayers=0。原layer1128混合Vec3/Vec2缺z语义的origin non-finite/BAD_RETURN仍开放，未定性为作者异常，区别于544。

同App独立3248220186见实际粒子球及07:13:41时钟，daemon12985、request `28D34B6B-AC33-4405-80E8-07926D115FC3`、session `67FBC1F1-9961-4875-9E89-E797E0466D69`、surface1；实际Stop后17/17 VM quiescent、余任务均0。CmdQ exit0，三PID全消失；未导出pin census，不把VM收尾或进程消失当最终pin归零。原作者树sourceChanges=[]；源verify因两个copied version marker预移差异返回exit1，不记命令PASS，也不记原媒体被改。未验官方parity/HDR/多surface/长稳或原生点击延迟。

## 证据与后继

本机`.artifacts/tmp/warm-bootstrap-seed-20261015/`保protocol、五对原raw/primary与完整身份、源码freeze/最近门、secondary-correction有效重算及无效派生撤回记录、memory-followup独立原数，以及native/proof/native-acceptance.json和原图；`warm-capability-attribution`约6.606MB sample只作定位，native proof保17,681,242B。累计清理已停止可再建产物3,440,355,357逻辑B（原2,970,455,753B加本次469,899,604B），不称运行RAM下降或物理空间释放。保B/C App、一份DerivedData/cache及全部raw/身份。promotion现有1GiB总预算仅约31KiB余量，前次失败后本轮未再复制，未放宽预算或删除未知/唯一旧包。

本片窄接受暖A2启动目标，内存后继转按事件对齐分类resident/footprint来源；不因准备下降直接增缓存、放宽variant/节点资格或重启旧NO-GO。属性卡继续待审语义/媒体入口，准备性能不另设第二选序。
