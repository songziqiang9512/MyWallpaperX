<!-- document-role: active-plan -->
<!-- retirementCondition: 共享物理分析与消费域分责完成且作者输入取得资格，长期约束进入现役合同后退役。 -->

# 共享音频分析与消费域设计

> 状态：当前三类消费者仍共用显示响应。[粒子16档](../scene/capabilities/runtime-evidence-current.md#particle-audio-prepared-fold)与[shader 32档](../scene/capabilities/runtime-evidence-current.md#author-spectrum-prepared-fold-361)分别已证从准备64档取组内峰值，端点对照把频带身份差定位在折叠前。固定x64默认分析窗与现有窗不同，尚未取得x86实机等同证据。48kHz相邻频轴与同档取峰已有实机资格，短矩形候选可复现邻谱；约85ms Hann 后的幅值无法恢复该窗口。同PCM已证共享快影响与局部慢状态，更新律未定。48kHz离线比较选择精确短窗变换，格式、增益及作者画面仍待验证。

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

每个发布批次只生成实际需求的结果。不同域若确需历史，由原Analyzer持最少必要状态，共用捕获时间/elapsed和既有reset边界；不为未知算法预建自适应状态。六数组合计224个Float，既有IPC入口允许有限非负值超过1，无需扩数组、传PCM或新增native/raw并行字段。采集只交真实有符号声道；首有声Debug整流峰仍按需一次，不增加逐窗归并。

实施时同批退出Scene取显示Levels及均值粗档的路径、三引擎必须同高度的断言和注释；保原native响应门，不留display域运行fallback。新数值失败应回退完整发布批次，不能给不同粒子暗换域。无采集/静音沿稳定零输入；入口与算术边界仍各由实际消费处处理，迟到格式不复位当前历史，普通局部失败不禁用健康消费者。

参考源码只用于研究职责与行为，按本项目独立实现。Mirage粒子helper的不同schema/公式不能当官方数值oracle；不靠更响PCM、gain/bounds/pow或强制出生拟合主束。当前约85ms窗及Hann/尺度只是本项目事实，未取得官方同窗资格。338当前局部印记不证明主束producer或音频单一根因，具体运行边界归[Scene证据](../scene/capabilities/runtime-evidence-current.md#beam-contribution)。

## 验收与边界

1. 原真实Analyzer/Service门保Video/Web的同PCM数值、样式、30/60Hz捕获时间包络、mono/stereo、格式、静音与暂停/恢复；同scope、格式及有效capture epoch的端点/需求变化不额外改变native值/历史，真实边界仍验原重建/token规则；需求不存在不计算无人消费的域。不能复制DSP进测试。
2. Scene数值在同一声源下分开核对实际采集、原始频谱、准备64档、折叠16档和粒子消费。复用已测声道切换及静音边界；单hot-band、L/R峰错位、边界、改名/等价变体与邻例区分新实现，不用全1或bus非零代正控。原“.96顶/固定dB/均值粗档”期望只保作native资格。
3. 六数组经真实decoder→Inbox→帧消费者核shape/顺序、generation、迟到、padding及>1不截顶，内部不重复验数据。Debug后固定作者版本、属性、声源、相位与viewport核主要图层、实际draw/附件贡献和目标ROI；补独立粒子、pulse眼部、32/64 shader/Script及Video/Web受影响样式。
4. 独立审查冻结源与实际画面，原生Web保两帧motion。参考、官方、合成与实际作者结论分开；无可行动资格即转其他开放项，不继续加音量/时长矩阵。没有可比profile不声称CPU/能耗改善，原始音乐收尾删除。

实现入口：`SystemAudioSceneSpectrumAnalyzer.swift`、`SystemAudioOverlaySpectrumAnalyzer.swift`、`SystemAudioSpectrumService.swift`；测试入口：`test_audio_spectrum_response.py`、`test_system_audio_spectrum.py`、`test_scene_audio_spectrum_input.py`及采集恢复/scope/IPC门。
