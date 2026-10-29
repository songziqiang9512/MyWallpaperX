<!-- document-role: historical-evidence -->
# 全样本能力与短窗日志筛查（2026-10-29）

> **历史证据 — 非现役入口**

本轮执行用户要求的全量声明盘点、并行短窗日志筛查及公共问题归并；没有修改Core引擎或观看截图。后续选序只归[断点队列](../roadmap/scene-open-breakpoint-queue.md)，方法归[诊断合同](../development/corpus-diagnostic-workflow.md#log-first-corpus-audit)，逐样本结果由[验收台账](../capabilities/scene-sample-acceptance-ledger.md)生成，旧人工视觉裁决未改。

## 范围与能力集合

真实Scene根只读，一次扫描453目录：452可解析、3763323436缺project。声明193099点、4878结构family、2428参数profile、23940字段；19个粗能力映射不等于19条独立加载链。主链与五类prepared产品保持，按原准备/消费者分为九类视觉路线和Sound旁路；跨路线的Script/Property/Timeline/Camera不重复计链。具体分组见诊断合同。

粒子声明组件共42种：2 emitter、14 initializer、22 operator、4 renderer；CP序号不是算法。`objects.[].model`有308个raw字段叶值/37样本，含256个string MDL引用/12样本与52个粒子对象model:null/25样本；null不是加载请求。包内models presence映射451样本也不能当451个模型消费者。后续沿既有入口定点关联105个sample/model路径，未读vertex/index或纹理；这是453快照的声明澄清，不是已加载数，也不覆盖随后新增38样本。

## 执行身份与时序

产品基线`a91a76fcb`，本轮仅增加原DEBUG runner的log-only调度及原Python工具的并发/日志分支；没有第二启动器或解析器。相同签名App只stage一次，每worker独立sample/HOME/TMPDIR，提取日志后逐个删除，结束后删除公共stage。

- 普通签名Debug：主入口`14fe3b5e…d08e`、实际dylib`f3a2a3a3…ba51`。先4并发小批4例，再6并发449例；普通样本Ready后4秒、固定PCM、pointer outside、不注入真实媒体或快捷点击，453行均明确不请求PNG。
- 首轮4例30.139秒、449例1962.713秒；后者36例父超时。206单独复核59.008秒，其中Ready约51.556秒；采样指向未优化Debug的源码分析/准备，不能当能力缺口。
- 使用仓库已有优化诊断profile补36超时及317、377健康相邻，共38例、6并发、154.057秒，无父超时。Release配置加原xcconfig仍含DEBUG、Swift `-O`、C `-Os`、singlefile；主入口`3725913b…4fc0`，构建179.785秒。正式Release/WMO与性能比较均未执行。
- 当前逐样本投影显式选3例pilot、412例首轮、38例补跑，共453唯一行；保存原report SHA、行索引、App身份及所有原失败。不同profile不比较启动/CPU/GPU性能，也不把重试覆盖当原失败未发生。

450例Ready、实际GPU完成且stop为surface 1→0/GPU drained；两例持续拒首帧，另1例输入缺project。归一器分类为337 terminal-chain-complete、110 degraded、6 blocked、65组事件；6 blocked中包括前述3例及3个虽Ready但缺图单元完成的观察，不等于6幅全黑，也不等于116个已证缺能力。归一器按阶段/原因稳定排序，因果首错回原日志核对。

| 原日志/报告事实 | 样本数 | 证据上限 |
|---|---:|---|
| image纹理已加载 | 452 | 准备，不含每层可见性/像素 |
| text纹理已加载 | 254 | 栅格准备，不代布局与字体一致 |
| solid已加载 | 185 | 按需准备，不要求隐藏候选全加载 |
| 粒子已加载 / 非空提交人口 | 284 /268 | 不代每个组件正确或方向/密度一致 |
| Puppet动画层/clip准备 | 98 | 不代所有动作/auxiliary播放 |
| sprite动画入口 | 32 | 不代完整序列周期 |
| utility capture成功 / named binding成功 | 205 /44 | 对应执行，不代所有条件分支 |
| SpotLight成功 / failed报告 | 1 /3 | failed原因/可见consumer需资格，不代地球阴影归因 |

视频、文件/系统媒体、直接模型及Sound沿原日志保留逐目标事实；目前没有覆盖所有路线的统一完成统计，不能用总GPU帧冒充每条路线执行。Sound测试处于paused，PCM仅供频谱；未验可听播放、真实封面/标题/seek、真实鼠标、属性编辑或完整长Timeline。无截图审阅、官方parity、画面关闭或性能收益结论。

<a id="remaining-findings"></a>
## 公共问题归并与未决边界

- **首帧阻断分两类**：2959875782 layer134外部primary依赖报dependency-input-mismatch并撤回帧；3175039950 Program218183166b6c在terminalReplay uniform准备返回nil。后者局部采集矩阵降维与完整逆合同相交，未证明可全局改变Z或放松逆矩阵检查。
- **typed更新/拓扑**：273五个childless passthrough composition已有采集/回绘消费者却被perspective资格额外拒；3763428294、3779904456、3787382101、3804971850先拒authored mutation冲突，再报stale；363先拒516条mutation预算，再报owned handle。3808922316默认初始化995/1763仍报buffer exceeded，静态链指向sort冗余dirty与跨owner冲突，不是已证容量不足。
- **effect局部降级**：274 Xray拒slot2 halo用途proof；280 Shine缺secondary composite引用；357 Combined及texture-purpose接原队列。3632522893、3725148661、3747595588、3750312644报frontend局部fallback；3435573282/3587571382报generic-owner-revoked；3800572533报texture-binding。需实际pass/active consumer及ROI，不按effect名分派新算法。
- **资源/图观察线索**：56 solid、7 image、4 particle候选未全加载；15样本layer-source-not-ready。隐藏、alpha0、离屏、按需/退休与延迟先区分。2804817823/3039882306/3292370168虽Ready但部分图缺完成；377双视频的named-capture告警不推翻用户已确认正常的Xray。
- **脚本异常须按因果拆分**：有限读取12个代表原包，确认作者缺名字/越过父链、未赋值引用、在标量上调用Vec.add、在text索取纹理动画等不能算缺API。3047405322/3603711180无条件调用未实现的engine.isScreensaver为公共候选，360572的console.warn仍缺实际callee资格；3806202923/3812473896创建null接既有recipe/解析范围项，不补假实例。完整typed事件与成员在机器档案，不由首轮21例TypeError统计替代最终观察。

## 验证、保存与方法调整

真实DEBUG调度20方法、最近Python工具45方法、短窗验收3方法及最终归一器24方法通过；最后两项按实际修订补验，没有重跑未受影响的App。独立审查覆盖并发隔离、原视觉缺图仍失败、4秒无长稳summary仍保实际GPU/停止门、负ID及真实`layerMutations=N owner=`拒绝格式。检查不代播放正确性。

台账/archive最近16门及文档、依赖、产物、代码与防御面检查通过。额外结构组15门中1个既有迁移fixture失败：其passive-result历史源摘要在本轮未改的Core源上已失配；直接用HEAD与工作区相同源重算均为false，收据单列保留，未改无关迁移合同或声称全门绿。

本轮结果归`.artifacts/scene-evidence/runs/corpus-log-audit-20261029/`；压缩载荷保存原report/日志/runtime JSON、当前投影与来源行索引、normalization、能力集合、身份、构建参数和验证摘要，不保存Workshop副本/HOME/App/PNG。原始绝对证据路径用于关联压缩包内同名任务相对路径，需解包按需读取，不承诺旧执行目录常驻。唯一未解首帧错误另提取最小证据；普通全量结果14天到期。

本批发现普通O0 Debug是可避免的筛查耗时来源，故后续默认采用现优化诊断profile，仅重试未决例；每个普通样本仍只跑4秒，不统一拉长时窗。队列按公共首断点替换“新增81未跑”，旧具体视觉反馈保留待同状态复验，不据日志健康销账。

生成台账时移除“已移走样本还必须出现在当前运行archive”的检查：历史裁决保原overlay，不计当前分母；不新增存储或把缺目录改成运行成功。最近行为门同时覆盖当前archive有/无该历史ID时，当前行相同且overlay字节不变。
