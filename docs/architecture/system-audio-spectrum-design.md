<!-- document-role: active-plan -->
<!-- retirementCondition: 共享物理分析与消费域分责完成且作者输入取得资格，长期约束进入现役合同后退役。 -->

# 共享音频分析与消费域设计

> Scene 已由原采集服务发布独立作者域。原采集回调和Metal验证了48kHz可比频谱、[361原包亮弧与Bloom](../scene/capabilities/runtime-evidence-current.md#author-spectrum-capture-live-361)及独立346前景。普通持续发射器沿同一作者16档，见[338原包](../scene/capabilities/runtime-evidence-current.md#floor-beam-continuous-emission)。44.1kHz通过本机物理轴行为门，官版该格式、首起音、强弱交接与整段时序待验。

## 目标与职责

Video/Web 保留现有可视响应与样式。Scene 作者的选带、bounds、指数和条件行为消费作者数值域。两域共享PCM采集、完整快照、分析调度与发布时钟；相同分析窗只求一次。Video现有产品只有柱形。

SystemAudioSpectrumService独占采集、需求和约30Hz发布。原 CaptureBuffer 保存连续PCM，一次移交同时间的完整快照；原 Analyzer 按消费者需求分析，Video/Web共用原去DC/Hann输出，已证不同的Scene短窗取该快照尾段，在同一worker和调用中变换。只在两个不同窗口同时被消费时各求一次，复用底层FFT资源、冷系数与有界scratch。Analyzer不另存PCM，也没有第二采集器、调度、时钟或IPC。短窗候选只算准备档消费的物理格，冷备系数，热用原私有工作区。精确变换及数值误差以实测为准；完整输出仍验端点格式、历史响应和作者画面。

`PlaybackSpectrumDelivery`继续由控制面更新有身份的进程目标，后台沿原有界transport发布成品数组，普通帧不经主App的AppKit队列。Scene仍沿原六数组→Inbox→帧快照→shader/Script/particle消费，不让消费者反推显示值或各自调增益、分档。scope、generation、停止及替换撤权归原owner。

Video需求仍同时要求设置开启、未暂停且有运行中的transport；保留的旧Video也算接收端。目标创建、退出、崩溃与回收重核需求，空Web预热不建立需求。没有接收端不维持采集/FFT；撤Video/Web需求先向旧合法目标投一次有序静音屏障，再拒迟到帧并清父端快照。仅端点/需求变化且采集scope、格式及有效capture epoch未变时，不额外复位仍服务Video/Web的历史；真实process scope、格式、active Scene epoch与恢复边界仍沿原Service重建/token规则。本次不迁移采集生命周期，也不为作者域初态额外重启。

Video helper仍首次开启才建子层并采用已接纳高度；空数组表示未建，不添状态。关闭保留对象及0.18秒淡出，再开启复用，柱数变更沿原重建/清零。

## 分域与旧职责退出

现 `frequencyAmplitudes` 的64带轴、覆盖面积均值和固定频率增益归显示域。Scene只在短窗得到实证的物理格上归约，并从同一份64档准备值折叠。格式权重沿原冷准备更新，各域计算一次，每屏读取同一结果。

| 消费域 | 合同与资格 |
|---|---|
| Video/Web现有显示响应 | 保原64带轴、固定频率tilt、-100…-10dB/0.96 smoothstep及30/140ms高度包络。Overlay先求立体声均值再投影并用静态style/sensitivity，Web拼接左右64。不将其提升为官方作者标定。 |
| Scene作者输入 | 由已验证的物理格与准备历史形成。保留超过1的合法供值，不套显示gain、顶高或包络。从同一准备64档以相邻四档峰值供16档、相邻两档峰值供32档；实证范围见本页状态。尚未证明所有Scene消费者同域时，六数组承载不等于完成。 |

[48kHz有限窗与状态对照](../scene/capabilities/runtime-evidence-current.md#author-spectrum-reentry-slew-361)支持对PCM尾段取矩形窗，保留基线对非DC格的贡献，冷备连续权重，按格上界取峰。精确非二幂格可在原Accelerate setup用有界chirp卷积，左右串用scratch，单声道只变换一次。每组八档从自己的有效分母按捕获时间追目标；目标取该组峰、当次双侧总峰三分之一及弱段底限的最大值。共同峰只形成当次目标，原独立平滑的共享分母退出。强音刚进入时，弱组和已稳定有量的组可同时以相同速率从不同位置上升，持续同峰后收敛。双侧低信号持续越过已测边界后，沿原reset恢复各组冷起分母。原捕获时钟、发布、停播和格式边界继续由原服务承接。

原串行Analyzer以29ms取最近样本，按48kHz/2089的物理间距跨端点建格，并限制在正频非混叠频带。44.1kHz用1279样本遵循该物理间距假设，官版端点仍需核对。有效时间来自同一采集时间戳，保现有连续快照，0.5秒低信号边界按双侧加权峰判定。离开作者域仅清作者历史，显示域失去最后需求即退出。缺采集或真实capture epoch由Service清零，有限输入保留大于1的供值。

完成分母归一后，准备64档按各档上一次有效值限制单次变化至±1，再沿原取峰折叠。双侧静音发布六组零值并保留最近有声的各档值；0.5秒重入只恢复分母冷起态。复用原最近一次结果，格式、声道与采集代次重置仍清除作者历史。以既有有效捕获分析为步进单位，重复及乱序时间不推进，普通渲染帧只读取。实机步进时钟的其它帧率证据仍开放。

有声组分母下降时，按捕获时差向当前目标缓释，残差半衰期取已测约40ms，下降量沿用原绝对速率上限。每次分析计算一份缓释比例，左右各组共用；相距较远时仍由绝对上限决定。当次输入、上升速率和静音重入均沿原职责。

每个发布批次只生成实际需求的结果。不同域若确需历史，由原Analyzer持最少必要状态，共用捕获时间/elapsed和既有reset边界；不为未知算法预建自适应状态。六数组合计224个Float，既有IPC入口允许有限非负值超过1，无需扩数组、传PCM或新增native/raw并行字段。采集只交真实有符号声道；首有声Debug整流峰仍按需一次，不增加逐窗归并。

显示Levels仅保64档给Video/Web，作者32/16档统一峰值折叠。频谱非有限时该作者批次发布稳定零值，清逐档输出历史并保分母。迟到格式不复位当前历史，普通局部失败不禁用健康消费者。

参考材料用于行为研究，按本项目独立实现。保作者PCM和参数，不以调幅、改bounds/pow或强制出生拟合主束。约85ms Hann仅为本机显示域。主束另沿[贡献链](../scene/capabilities/runtime-evidence-current.md#beam-contribution)核对。

## 验收与边界

1. 原真实Analyzer/Service门保Video/Web的同PCM数值、样式、30/60Hz捕获时间包络、mono/stereo、格式、静音与暂停/恢复；同scope、格式及有效capture epoch的端点/需求变化不额外改变native值/历史，真实边界仍验原重建/token规则；需求不存在不计算无人消费的域。不能复制DSP进测试。
2. 同源核PCM、原始谱、准备64、折叠16与[发射器出生](../scene/capabilities/runtime-evidence-current.md#floor-beam-emitter-338211)。普通持续发射验中置同档平均后取峰、bounds内smoothstep后取幂，含指数100。算子和初始化器单验。保单峰、错位峰、边界、静音、等价变体与原包出生。显示域保原数值门。
3. 六数组经真实decoder→Inbox→帧消费者核shape/顺序、generation、迟到、padding及>1不截顶，内部不重复验数据。Debug后固定作者版本、属性、声源、相位与viewport核主要图层、实际draw/附件贡献和目标ROI；补独立粒子、pulse眼部、32/64 shader/Script及Video/Web受影响样式。
4. 独审冻结源与实际画面，原生Web保两帧motion。分开记录合成输入与作者画面。剩余时序差用同相位端点和频谱对照，复用当前脉冲证据。无可比profile不授性能收益，原曲收尾删除。

实现入口：`SystemAudioSceneSpectrumAnalyzer.swift`、`SystemAudioOverlaySpectrumAnalyzer.swift`、`SystemAudioSpectrumService.swift`；测试入口：`test_audio_spectrum_response.py`、`test_system_audio_spectrum.py`、`test_scene_audio_spectrum_input.py`及采集恢复/scope/IPC门。
