<!-- document-role: stable-contract -->

# Scene 全样本声明诊断与报告合同

目标是让完整、缺文件或畸形目录都能留下准确的声明诊断，并由同一次观察产生可复验的总览与明细。声明扫描本身不运行引擎；日志运行复用现有runner，不裁决官方画面一致性；执行顺序仍归[断点队列](../roadmap/scene-open-breakpoint-queue.md)，统计归[声明总览](../capabilities/scene-corpus-capability-inventory.md)与[样本明细](../capabilities/scene-corpus-sample-inventory.md)。

## 输入、职责与迁移

真实Scene目录只读。单个目录的project解析失败仍保留sample identity、失败原因和实际材料事实，不能为消除报告异常把失败改成成功，或把未知材料一律补false。

```text
CLI / build_census 唯一遍历与守恒
  -> samples 单目录 authored 观察 -> 现有 resources/effects/particles/profiles -> io
  -> contracts family/repair 声明及引用校验
  -> reporting 同一结果的 snapshot / 总览 / 明细纯投影
  -> CLI 校验输出路径、预生成全部payload、沿现atomic_write写出
```

`scene_capability_census.py` 保留实际corpus orchestrator、缓存query与CLI；迁出的完整职责分别由 `scene_capability_census_samples.py`、`scene_capability_census_contracts.py`、`scene_capability_census_reporting.py` 唯一拥有。原定义退出主文件；既有可导入函数/常量用显式import保持同一函数对象，不复制算法或增加转发wrapper。下游不反向import CLI，不引入第二扫描、缓存或运行结论owner。生成器身份manifest覆盖所有实际职责源。

这次迁移服务两个已证故障：失败row缺材料字段导致报告KeyError，旧单页writer与现役双页文档不符。样本观察、合同、报告按完整职责迁出，使本批触碰的自有源码各≤1000行；不为缩行数切任意代码块。未触碰的profiles既有超限不借此宣称关闭。

## 一次观察、三项输出

- snapshot保留机器可查声明、失败与身份；不装入作者脚本/shader正文。
- 总览只保分母、声明/能力汇总、证据边界及明细导航；不重新塞入整张样本表。
- 明细拥有逐样本行，包含失败目录与材料事实；总览/明细互链。旧N样本矩阵成员只写是/否，不称“新增”、从未运行或当前运行裁决。

原 `generate / verify / query`、缓存优先及显式live语义保留。新增可选 `--sample-markdown`；未提供时从 `--markdown` 所在目录派生 `scene-corpus-sample-inventory.md`，自定义总览输出不能悄悄写入仓库默认明细。旧Namespace调用缺新属性也用同一规则。具体参数以 `--help` 为准。

`generate/verify --sample-id <目录ID>` 可重复指定显式子集；在任何单样本读取前筛选，缺失ID报错，不读取未选样本。子集必须指定专用 snapshot/markdown 输出，三项输出不得覆盖默认全量路径；snapshot和两页明确记录子集范围与所选ID，本次声明/资源计数仅归该子集。repair样本引用、matrix删除成员及full-matrix覆盖状态仍按根目录发现的完整ID集合判断，仅枚举目录不读取未选包；所选新增差集与全根matrix状态分别表达。默认全量语义与 `query --sample` 的结果过滤语义保持；子集不合并旧缓存，也不冒充更新后的完整corpus。新增样本先单列声明/能力并集，再沿原runner短log筛查，旧基线保留。

单样本 tree manifest 已读取的文件摘要在本次观察内供 project/package identity 复用；manifest与identity值不变，不建立跨事务缓存或新增播放认证。

## 失败、写入与退出

1. 构建前校验snapshot、总览、明细的resolved路径均不在只读输入根，且三者不互相覆盖；符号链接按实际目标判断。
2. 每次generate/verify只构建一次census。结构合同失败沿原返回值退出；单样本解析失败保留失败row，不能阻断其余报告。
3. 首次写入前，在内存生成全部三份payload；投影失败不得留下“新snapshot＋旧文档”。随后复用现单文件atomic_write。它不承诺三文件IO事务；IO失败明确报错，由verify逐项识别漂移，不另造持久化协调器。
4. verify分别检查三项输出，区分snapshot、总览与明细drift；query缺缓存的早退与显式live边界不变。

运行归一器和粒子/脚本/资源的视觉准入独立维护。工具正常或声明计数守恒不证明样本能正确播放。

<a id="evidence-capture-timing"></a>
## 运行截图时刻

`after-snapshot-delay`以ready后开始安排截图的单调时钟为起点，约束after请求的最早时刻。鼠标hover、click、trajectory及普通单轮drag还须发出hover截图请求、移出并经过原0.2秒等待；取两者较晚者。鼠标动作不为等after而延长，独立命名的多轮drag保持原计划。普通ready/after、周期截图和spring-after继续各自现有时序。

launch失败/取消或closing后不请求新截图。该时间只约束DEBUG请求，实际捕获/保存仍由原frame-capture owner确认；日志时刻、音频和鼠标状态共同决定图像是否可比较。旧鼠标路径提前after的历史图保留实际日志时刻，不按请求参数追认成延后截图，也不因此自动改样本裁决。


<a id="diagnostic-output-acceptance"></a>
## 验收与停止条件

最近小fixture包含正常包、仅shaders/无project、带截屏与说明但project无效的目录；验证发现数=成功+失败、失败诊断不丢、材料事实准确，三项输出可生成与verify。分别篡改每项输出均须报告drift；自定义路径、输入根、符号链接、输出互撞及投影失败前不写入均有反例。

原声明确定性、payload-free、family/repair引用、缓存query与API门保持；测试按完整观察组和输出/合同组迁移，共用原真实fixture builder，不能重复发现同一TestCase或复制扫描算法。所有本批触碰源码/测试/helper实测≤1000行。

小门通过后，从原目录只读完整生成到隔离目录并verify，对照原有效manifest/计数及现双页；已解释的生成器身份与材料字段变化单列。未知计数或语义漂移先停并定位，不靠重生成抹掉。最后才同步现役双页及队列中的这两个子项。此工具批无需App构建或设备运行。


<a id="log-first-corpus-audit"></a>
## 全样本能力与日志优先筛查

**目标与统计口径。** 先对当前真实目录生成一次声明snapshot与现有双页投影，再运行样本；不从历史45成员matrix推当前分母，不重复全文扫描。分别列目录/声明点、公共能力、结构family、参数profile及未知项，后四者不能互相替代。代码保持一条共享Scene主链、五类prepared产品；诊断按独立准备/消费者分组为九类视觉路线及Sound音频旁路，script/property/timeline作为跨路线控制面，不按样本、family或参数组合膨胀“加载链”数。包内资源presence仅作线索，实际对象引用、准备、取源及编码事实分开；现census粗映射识别不到的直模/Puppet细分保未知，由当前代码边界及运行日志补足，不能把通用models资源计成3D模型已运行。

| 诊断路线 | 原准备产品与实际消费者 | 声明入口及边界 |
|---|---|---|
| 静态、序列与内建纹理 | TextureProduct → image/material sampler | texture slot、TEX/sprite；包内存在不等于实际选源 |
| 文字 | Text raster/dynamic publication → image encoder | layer/text、font、参数；字体/栅格化需运行 |
| 视频 | 原Source → typed frame publication → image/graph sampler | TEX视频声明与实际consumer关联；ordinary/asset/userProperty复用Source实现 |
| 文件与系统媒体provider | 原user texture/media store → FrameTextureRegistry → sampler | scenetexture/system slot；文件类型、媒体可用性及实际绑定需运行 |
| Puppet几何 | 原prepared mesh/pose → GeometryProduct → compositor | image model puppet声明仅候选；mesh、动作与draw另验 |
| 直接模型 | objects.model → 原static-model mesh/material/animation → model draw | schema字段可列声明；现旧census把未识别对象归utility，不能用resource/model数当直模数 |
| 粒子 | 原asset graph/simulation → DrawBatch → particle renderer | layer/particle及组件；出生、模块接纳、draw分别记录 |
| 材质、Effect与Utility图 | 原Program/graph → executor/source/terminal consumer | material/shader/effect/FBO/binding；lowering、backend与fallback需运行 |
| SpotLight直绘 | 原light plan/pipeline → MainPass | light仅粗入口；point/directional uniform不另增输出链 |
| Sound音频旁路 | 原sound program → AVQueuePlayer/Looper → 系统音频 | sound/audio声明；不据此认定可播放或可听见 |

上述是诊断分组，不新增产品类型；未识别对象或观测不足保unknown。Camera、灯光uniform及Script/Property/Timeline从现typed更新进入相应消费者，不能乘成额外加载链。

**唯一链与范围。** `census → scene_wallpaper_benchmark/run_sample → scene_diagnostic_report → scene_sample_debug_archive`。仅在原入口增加显式`--log-only`及有界`--jobs`，不另写一套发现、启动、解析、渲染或队列。DEBUG runner保原launch、typed更新、Metal提交、停止及after时刻粒子报告，只停PNG请求；Python日志模式不打开/计算PNG、预览或运动指标，报告明确`not-requested`。现视觉模式和性能模式的图片断言、缺图失败及串行条件保持；日志模式必须保留execution observations。SceneScript动态负layer ID错误与正ID同样归一，不得漏掉后误称未触发。

**阶段证据。** 逐能力保存`declared / prepared / executed / failed / not-triggered / unknown`，分别由现parser、Program/graph、provider和实际encode/完成支撑，prepared或总帧非零不能代目标执行。无事件先核触发/观测，隐藏、alpha0、离屏、延迟、缺输入或退休不算可见失败。开场和切换过渡不作正式效果；先核作者时序与实际scene时钟越过过渡，再在同输入/阶段比较，只有相关代表延长观察。`scene-color-completed`是唯一producer在GPU成功promote后发出的通知，原日志parser不将其归错误，也不给terminal/GPU/publication补证；未知、畸形与显式失败保原错误链，dormant成员仍须原完整图门。日志健康只归所跑条件，不授像素、官方或全属性通过。

**批次与并发。** 使用现有`scene_diagnostic_build.xcconfig`的优化DEBUG构建筛查，保完整App身份（普通Debug含主体dylib），只stage一次。未优化Debug的shader源码分析会放大冷准备时间，不能把它的超时直接记成缺能力；改profile时只补未决项并分别记录身份，不混作性能对照。每样本独立输入副本、HOME、TMPDIR、日志与进程；只给worker自己的子进程/目录执行退出清理，全部worker结束后再清公共stage。先小批确认隔离、实际GPU完成和回收，再按设备内存/GPU余量提升并发；普通样本ready后约4秒（允许3–5秒），冷准备有单独超时。长时/延迟/定时行为只对相关代表延长，未触发分支先留未覆盖，不给每个样本几十秒。普通日志诊断可并行；正式性能、真实系统音频/全局媒体与真实鼠标对照仍串行协调，不能从争用数据认性能收益。标准PCM与受控鼠标输入如使用须写入条件，禁止触发作者外部快捷操作。

**失败与退出。** 已知坏输入保source-invalid行，不丢分母；并发超时、OOM、缺drawable或进程异常先用相同输入串行复核，未复核标运行环境/工具或待确认。原始首错保留，次生错误按依赖归属；复用现`stage/owner/reasonCode/profile/failureRadius`聚类，记录受影响与健康相邻样本。每个worker完成即提取报告/必要日志并清其副本和HOME，不累积整库复制；唯一未解失败只留最小材料。普通结果不留PNG，必要结果按现证据规则归档。

**验收与后继。** 最近门须覆盖日志模式无采图但after报告存在、视觉模式缺图仍失败、正/负动态ID归一、并发隔离/实际重叠/逐样本退出、单个坏输入不吞其余结果。小批通过才扩全量；当前能力/样本双页由同次snapshot生成，运行裁决归原验收台账。最终队列按共同首断点合并：确认关闭移历史、当前可复现保开放、未触发/缺证据单列，不据日志健康删除既有未核视觉报告。整理后再按画面合成/播放正确性、性能、属性能力顺序选修复，不能用统计与工具数量代替样本收益。

人工裁决由原overlay独立保存。已移除样本只列历史ID，不进入当前目录行和分母；无需当前运行archive继续携带该ID，不能因此阻断其余台账生成。裁决类型/必需日期等入口校验保持，不自动改视觉结论。

新增样本的运行归档可用原 `scene_sample_debug_archive --base-archive <旧archive>` 追加互不重叠的子集。旧行、原report身份与断点原样保留，仅新子集调用原normalizer和行投影；两组ID并集须等于当前目录，重复ID或缺口报错，不静默覆盖。source分别记录base archive与本次subset census身份，summary从合并行生成，原ledger照常join人工overlay。这是多次观察的归档，不是完整census重建；不恢复/重读旧日志，不另增扫描、归一或视觉裁决链。替换旧样本观察仍显式选择原report后按完整入口生成，不能借追加改旧事实。

调用顺序如下；`current-matrix.json`只从本次snapshot的`samples[].sample_id`投影schema-1的`id`行，按需记录受控PCM等条件，不继承旧matrix的截图/性能期待。原始Scene父目录只读，runner按样本复制并及时清理，不能先复制整库再跑。

```sh
python3.12 -B script/scene_capability_census.py generate
xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX \
  -configuration Release -xcconfig script/scene_diagnostic_build.xcconfig \
  -derivedDataPath <同任务复用的隔离构建缓存> build
python3.12 -B script/scene_wallpaper_benchmark.py \
  --app <签名优化DEBUG-App可执行文件> --sample-root <含Scene的父目录> \
  --matrix <current-matrix.json> --output-dir <新的隔离结果目录> \
  --log-only --duration 4 --jobs <本机已验证并发数> --audio-spectrum-fixture
python3.12 -B script/scene_sample_debug_archive.py \
  --report <结果目录/report.json> --output <本轮诊断archive.json>
```

先读archive中的公共聚类，再回原始日志核因果首错、目标是否active及后续恢复；归一器按阶段/原因稳定排序，不声称日志时间顺序。多轮先明确选择每样本的有效观察，保存原report/行索引与App身份，再向原archive提供不重复的行；不以重试抹掉原失败。复核失败可对同一matrix用`--sample-id`与`--jobs 1`补跑，不能因短窗没有长稳性能summary重复采集已有效的GPU/生命周期证据。实例数由本机余量决定，工具不设置跨设备固定上限；正式性能结果沿原性能卡另验。
