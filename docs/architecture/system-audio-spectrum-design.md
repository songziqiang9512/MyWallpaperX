<!-- document-role: active-plan -->
<!-- retirementCondition: 共享物理分析与消费域分责完成且作者输入取得资格，长期约束进入现役合同后退役。 -->

# 共享音频分析与消费域设计

> 状态：Scene 仍共用显示响应。[粒子16档](../scene/capabilities/runtime-evidence-current.md#particle-audio-prepared-fold)、[前景16档](../scene/capabilities/runtime-evidence-current.md#author-low-band-pulse-346)和[shader 32档](../scene/capabilities/runtime-evidence-current.md#author-spectrum-prepared-fold-361)在已测档取准备64档组峰。48kHz 已有[矩形短窗、起音与前景实绘](../scene/capabilities/runtime-evidence-current.md#author-spectrum-silence-onset-361)证据。攻击、静音重入边界、全带权重、发布时钟及44.1kHz待证；实时原包有声与Bloom待验。

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

[压力及红环实绘](../scene/capabilities/runtime-evidence-current.md#author-ring-offline-spectrum-replay-361)支持48kHz候选对连续PCM尾段取矩形窗，保留基线对非DC格的贡献，再按已测格上界取峰。稳态分母候选取逐声道每八档本地峰与双侧共享峰三分之一的较大值。已证较长全零后重入会从共同有效分母近似线性释放，成熟弱音分母低于旧候选固定下限；共同抬升可由共享峰承担，现有证据尚不能裁决本地慢峰是否也需要重置。接线前以短静音、弱非零过渡与受压强弱双脉冲区分状态和攻击，并验捕获时间及格式。保持独立低多音阈值和原红环实绘。

每个发布批次只生成实际需求的结果。不同域若确需历史，由原Analyzer持最少必要状态，共用捕获时间/elapsed和既有reset边界；不为未知算法预建自适应状态。六数组合计224个Float，既有IPC入口允许有限非负值超过1，无需扩数组、传PCM或新增native/raw并行字段。采集只交真实有符号声道；首有声Debug整流峰仍按需一次，不增加逐窗归并。

实施时同批退出Scene取显示Levels及均值粗档的路径、三引擎必须同高度的断言和注释；保原native响应门，不留display域运行fallback。新数值失败应回退完整发布批次，不能给不同粒子暗换域。无采集/静音沿稳定零输入；入口与算术边界仍各由实际消费处处理，迟到格式不复位当前历史，普通局部失败不禁用健康消费者。

参考材料用于行为研究，按本项目独立实现。保作者PCM和参数，不以调幅、改bounds/pow或强制出生拟合主束。约85ms Hann仅为本机显示域。主束另沿[贡献链](../scene/capabilities/runtime-evidence-current.md#beam-contribution)核对。

## 验收与边界

1. 原真实Analyzer/Service门保Video/Web的同PCM数值、样式、30/60Hz捕获时间包络、mono/stereo、格式、静音与暂停/恢复；同scope、格式及有效capture epoch的端点/需求变化不额外改变native值/历史，真实边界仍验原重建/token规则；需求不存在不计算无人消费的域。不能复制DSP进测试。
2. 同源核PCM、原始谱、准备64、折叠16与[发射器出生](../scene/capabilities/runtime-evidence-current.md#floor-beam-emitter-338211)。普通持续发射验中置同档平均后取峰、bounds内smoothstep后取幂，含指数100。算子和初始化器单验。保单峰、错位峰、边界、静音、等价变体与原包出生。显示域保原数值门。
3. 六数组经真实decoder→Inbox→帧消费者核shape/顺序、generation、迟到、padding及>1不截顶，内部不重复验数据。Debug后固定作者版本、属性、声源、相位与viewport核主要图层、实际draw/附件贡献和目标ROI；补独立粒子、pulse眼部、32/64 shader/Script及Video/Web受影响样式。
4. 独审冻结源与实际画面，原生Web保两帧motion。分开记录合成输入与作者画面。供值待取得能区分更新律的异幅预测或运行中原值，不重复当前脉冲矩阵。无可比profile不授性能收益，原曲收尾删除。

实现入口：`SystemAudioSceneSpectrumAnalyzer.swift`、`SystemAudioOverlaySpectrumAnalyzer.swift`、`SystemAudioSpectrumService.swift`；测试入口：`test_audio_spectrum_response.py`、`test_system_audio_spectrum.py`、`test_scene_audio_spectrum_input.py`及采集恢复/scope/IPC门。
