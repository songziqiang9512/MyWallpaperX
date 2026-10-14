<!-- document-role: historical-evidence -->

# 单帧 GPU 归因与附件输入筛选（2026-10-14）

> **历史证据 — 非现役入口**。选题与正式收益门归[性能卡](../roadmap/performance-convergence-card.md)。本次只定位一个真实基线帧的成本，不接收性能收益，也不关闭 GPU 专项。

## 输入与证据身份

使用已冻结的增量优化诊断 App `cfaca983…`，真实304输入、3024×1964、60FPS、静音、关闭 execution observations；不是前批 WMO App，也不是普通 Release/Product Entry。原项目/包哈希、完整命令、实际 PID73777 与运行前后 App 身份见[摘要](../../../.artifacts/tmp/gpu-cost-attribution-20261014/proof/summary.json)。

本机 Apple M4/macOS27.0.1、Xcode27.0；`gpucapture` 在观测 ready 后53.529秒捕获一个 CAMetalLayer 帧，ready轮询分辨率0.5秒，未冒称固定30秒采集点。真实 Host 正常退出后，才用唯一 `gpudebug` session离线 replay/profile；未增加产品计时或 capture owner。

原运行[报告](../../../.artifacts/tmp/gpu-cost-attribution-20261014/live/report.json)仍为 `particle loading incomplete` FAIL，1128非有限 origin 日志仍在。采集会扰动运行，报告中的实时 GPU/CPU 数字不作性能验收。退出为71/71 quiescent、timers/jobs/mutations/dynamicLayers均0、surface 1→0且GPU排空；session随后精确终止，进程/句柄检查为空。

## 采样结果与分母

[原始 shader JSON](../../../.artifacts/tmp/gpu-cost-attribution-20261014/shaders.jsonl)中，`sceneImageLayerFrag` 的工具 Cost为64.717%，高级混合 fragment为4.937%；最高单 draw为6000×2805 RGBA8 source到3024×1964 drawable的普通四顶点quad，Cost11.790%。这支持先研究共享 image/source fragment，不证明其某一源代码行或慢分支已是热点。

普通 shader工具属性为338条指令、295 ALU、94 INT32、14 Branch；全帧 instruction-throughput limiter/utilization为55.52%/19.70%，原始属性与counter时间序列均保留。它们是指令压力诊断信号，不能单凭静态指令数认定HDR保护慢路径实际执行。

全部147个 encoder 的 Cost归一化和为100%；工具未在本地manual解释其估算算法，shader/command列表并非各自和为100%。Cost不是wall-clock GPU时间占比，不能乘整帧时间发明独占耗时。

离线[时间线](../../../.artifacts/tmp/gpu-cost-attribution-20261014/timeline.jsonl)报告整帧10.434541ms、overlap=yes、只采样2/10核心。请求与工具显示为 `default`，但[嵌入元数据](../../../.artifacts/tmp/gpu-cost-attribution-20261014/proof/embedded-profile-info.json)记 `gpuState=medium`；二者原样保存，不声明与真实 App频率/调度等价。

## 背景 copy 的具体边界

捕获顺序中匿名 `be7` 在空主pass `re6` 与高级混合 `re8` 之间，只有一个blit；后者绑定原背景snapshot。结合每帧恰好一个23,756,544字节 framebuffer capture、共两次copy及另一具名graph exact copy，推断该匿名blit属于背景snapshot；未直接导出其src/dst API参数，不把推断升级为直接资源关联。

[encoder Cost](../../../.artifacts/tmp/gpu-cost-attribution-20261014/encoders.jsonl)对应匿名 `be0` 为3.35739%，末列另显示0.4027ms；[原始 encoder时间线](../../../.artifacts/tmp/gpu-cost-attribution-20261014/encoder-timeline.jsonl)起止1,740,507→2,098,708ns，窗口0.358201ms。不同表示不强凑一致，也不把4.937%的fragment成本当作copy成本。

两个blit的时间线窗口合计0.389701ms，只界定这次记录中全部blit窗口的覆盖范围；其他encoder与其重叠。它不是移除copy后的App收益上界、critical-path节省量或GPU耗时改善证明。

## 筛选决定与收尾

附件原型的[最终冻结门](../../../.artifacts/tmp/gpu-attachment-read-20261014/fixture-pso-link-frozen/fixture.log)为13 PASS/16.093s，[14项输入身份](../../../.artifacts/tmp/gpu-attachment-read-20261014/fixture-pso-link-frozen/source-identity.json)中harness为`b65354b0…`；普通shader为`892535ee…`，这是该门的输入，不能混称本次捕获App的源码。library/function失败和真实PSO链接失败均保必需管线；PSO反例的library确实编译成功、required可用、optional为nil，snapshot回退逐字节相同且只1 copy/1 draw，见[原始结果](../../../.artifacts/tmp/gpu-attachment-read-20261014/fixture-pso-link-frozen/report.json)。早期PSO错误轮与source-drift轮无效，不混入最终通过。

本次决定不扩展附件原型的App性能campaign，原型已按[撤回清单](../../../.artifacts/tmp/gpu-attachment-read-20261014/proof/withdrawal.json)恢复HEAD；设计、patch和源码仅留历史证据，不保留active设计链，也不计性能收益或GPU专项完成。约3%的copy归因与64.7%的普通shader成本用于选序，不能证明整App收益一定小于10%。普通shader随后只做下列短筛，不将静态指令数当作已证慢路径热点。

共享modulation增加与原逐通道continue条件等价的四行向量快判，原乘法与HDR慢路径不变；[独立数值门](../../../.artifacts/tmp/unlit-modulation-screen-20261014/proof/numerical/gpu-output.json)5 PASS。冻结真实pipeline、6000×2805 pattern源/3024×1964 BGRA8目标、同fast flags，10对预热后交替40对；[结果](../../../.artifacts/tmp/unlit-modulation-screen-20261014/primitive/summary.json)为B/C GPU中位0.876354/0.877750ms，配对中位节省0.1597%，整图23,756,544字节相同。低于预设10%继续门，立即[撤回](../../../.artifacts/tmp/unlit-modulation-screen-20261014/proof/withdrawal.json)，不跑额外weighted/HDR变体或App；源码独审等价不代表性能收益。

另一[固定sampler mode0消融](../../../.artifacts/tmp/unlit-modulation-screen-20261014/sampler-mode0/summary.json)仅替换该switch，沿同一harness与40对AB/BA测量；B/C GPU中位0.929396/0.904979ms，配对节省2.5699%，候选P95反升，整图相同。未达10%门即停，没有产品PSO改动。两条短筛均不支持继续试改同一假定热点；下一次shader实现前须取得更直接执行证据。当前[行级归因边界](../../../.artifacts/tmp/gpu-cost-attribution-20261014/proof/source-line-method.json)：工具未定义Instructions静态/动态口径，基线关闭shader source信息，未证明此CLI/trace可导出行级Cost。

未验证正式WMO/Release、跨样本性能、多屏、长期切换、能耗或温度；没有候选App对照或正式性能收益。命令导航错误和返回0仍含error的无效查询保留并排除；修正后的JSON与六份counter才是归因输入。

唯一trace已按[清理收据](../../../.artifacts/tmp/gpu-cost-attribution-20261014/proof/cleanup-result.json)精确删除：634条文件记录含237个内部symlink，逻辑1,100,004,003字节，唯一普通文件836,680,355字节。删除前重核全部hash、无session/进程/句柄；[逐文件清单](../../../.artifacts/tmp/gpu-cost-attribution-20261014/proof/trace-file-manifest.json)、原始JSON和测试收据保留，未额外归档trace。当前行级映射未证，后续source-enabled capture须另身份；保留原始归因摘要及追加后继screen的摘要，staging时的app_launched=false不代表该App从未运行。

## 后继：普通 draw 的执行计数

[本机工具核验](../../../.artifacts/tmp/gpu-execution-attribution-20261014/proof/summary.json)确认`gpudebug 1.0`支持源码浏览、draw/stage Cost、heatmap和timeline；安装的help/man没有公开PC采样、行级Cost或Shader Cost Graph入口。源码可读不等于执行归因，不为未经证明的行级能力先做source-enabled构建。

随后沿冻结App `ee885541…`、真实304、相同优化诊断配置采一个Layer帧，App退出后仅做一次离线profile。[离线归因摘要](../../../.artifacts/tmp/gpu-execution-attribution-20261014/offline/result-summary.json)保留最高普通draw的command-scope fragment ALU计数222,754,400，Integer/Conditional/Boolean占70.21%，float/half占17.02%/12.77%，ALU inefficiency为0.13%。工具将后者定义为分歧、部分SIMD或不完整2×2覆盖导致的predicated-out指令比例；它降低“大面积分歧浪费”的排查优先级，不定位某条源码或证明sampler/modulation成本。普通shader聚合Cost64.7737%、最高draw11.9221%仍是工具Cost，不是独占时间。

请求default/overlapping，嵌入记录为medium、仅2/10核；shader timeline末点13.029ms还超过全帧显示10.246125ms，原值并存，不强算critical path。四类heatmap已保存；视看cost/non-ALU/divergence仅见稀疏tile，未建立内容局部热点，黑区不能当零成本，跨图颜色不能推算时间比。已终止唯一session，默认临时目录的9个输出逐一验SHA后迁入证据目录并删除原副本。此次停止探针和盲目shader修改：没有源码行归因、候选对照或性能收益，未完成GPU/能耗验收；执行顺序仍归性能卡。

## 后继：source capture exact-copy资格筛选

冻结App `86b320df…`、真实304和同一优化诊断配置，在观测ready后30.029秒采一个Layer帧。App正常exit0，报告仍仅原`particle loading incomplete` FAIL。随后唯一session27只读取descriptor、PSO及66份inline uniform，不运行profile；[逐capture结果](../../../.artifacts/tmp/source-capture-eligibility-20261014/offline/eligibility.json)与[摘要](../../../.artifacts/tmp/source-capture-eligibility-20261014/result-summary.json)确认33/33不满足中性exact-copy：29次尺寸不同、30次格式不同，另有4次alpha和1次tint非中性；原因可重叠。仅4次同尺寸也均RGBA8→BGRA8。工具未显示的mip/sample/clearColor保留missing，已有尺寸/格式反例足以拒绝全部，不能把缺字段记作已验。

因此停止该fastpath，不写产品、不补像素实验、不计GPU/CPU/内存收益。后继只保输入内容/尺寸/UV/样式实际稳定比例的有界诊断候选；现有shared pair会被后续effect覆盖，不能当内容缓存。若未来复用独立capture结果，须先证明覆盖率、现有pool预算及completion/reset失效，不能用新增驻留或每帧copy换表面pass下降。session已终止；[清理收据](../../../.artifacts/tmp/source-capture-eligibility-20261014/cleanup.json)记录trace普通文件660,813,087字节及本轮重复产物已清理，保必要JSON、inline bytes、身份与压缩日志约1.66MB。


## 后继：源捕获输入复用率（2026-10-14）

临时GraphExecutor观测沿现有成功sourceCapture编码点，要求真实texture匹配FrameTextureRegistry完整publication，且file identity/generation可证明内容；bare/provider/sourceMaterial、sprite、lighting等动态输入保守排除，不以对象地址稳定当内容稳定。现有typed UV、alpha/tint、sampling、表示、PSO、真实target及reset代次组成有限签名；只保上一份值、不保texture/pass。先独审修正prepare提前结束、initialization混入分母、多executor混算及“连续时长/驻留下限”误称，再做单份诊断，不留永久观测owner。

App74e16d63、真实304/单surface、30秒暖机后8秒观察，唯一complete summary，33层各480次成功source编码，duplicate/overflow均0；25层各1次初始+479次稳定相邻输入（共11975），8层排除（5缺匹配publication、2非file权威、1动态）。这些eligible层每层一份target的逻辑预算合计37568512B/35.828125MiB，不是实际Metal驻留/峰值。App正常退出、failedFrame=0，census33 source captures/frame，原particle loading incomplete仍FAIL；只证重复覆盖，不能推出GPU/带宽/能耗收益。

证据归`.artifacts/tmp/source-capture-reuse-screen-20261014/proof/observation-summary.json`与原始摘要/压缩日志。一次优化诊断build成功，唯一pbxproj漂移经plutil核为注释/序列化及membership set顺序，保原件与漂移记录；Graph/临时observer/工程副作用均已还原，诊断App及派生产物清理约215MB，保必要一图。当时共享DD的Release仍是诊断版，独立91fe基线不变；随后按下述原shader/exact-copy短筛及App原型继续，没有将临时观测变成永久owner。


原shader与exact-copy后继短筛使用4条真实model→material→texture链、现役TextureLoader及原资源encoder/Metal源码；56输入冻结，单份-O binary。全图逐字节一致，alpha/tint变更使旧结果失配、重捕获恢复一致。固定3块交错、每buffer16操作：三个大尺寸GPU p50分别降81.19–82.03%/72.59–73.58%/80.13–80.96%，小图91.07–91.15%；对应每操作节省中位0.2135/0.1854/0.1163/0.03065ms。前三大图算术和0.5152ms不是App预测；冷capture+copy每形状仅一对固定顺序、均多成本，不推稳定回本次数。证据`.artifacts/tmp/source-capture-copy-screen-20261014/screen-summary.json`保完整raw/输入及绝对量，编译cache清理，保一份binary/library与12个真实输入副本供独审。此结果只支持进入现有pool/completion的有界设计，不是缓存产品、整App、峰值内存或能耗验收。


## 后继：capture结果缓存短筛撤回

先在现有资源设计落单layer槽、连续三帧稳定准入、原pool父/子预算、必要target提交后才分配、原ledger GPU成功才发布及pin/reset失效方案；原capture保唯一失败回退。候选仅开放匹配file publication的不可写、非sprite、无lighting/dependency/fog的straight SDR RGBA8→BGRA8；初次原capture+copy、暖时copy，输入变化重新观察。32项pool测试含14项新事实通过，产品静态独审通过；这不代替真实Graph/Coordinator接线验收。

冻结优化诊断App B=`91fe54e3…`、C=`0d0573c5…`，同真实304/单surface/3024×1964/60FPS、30秒暖机及64.5秒测量，matrix/package/project/profile相同且计时无编译争用。每帧source capture 33→8、copy 2→27，替换确实发生；[原始报告与摘要](../../../.artifacts/tmp/source-capture-reuse-implementation-20261014/proof/app-screen-result.json)显示CPU 799.8819→860.3970ms/s（+7.5655%）、prepare p50 4.615→4.945ms（+7.1506%）、GPU p50 7.875→12.090ms。GPU allocated采样峰值增加39,059,456B，pool增加37,568,512B。单对不能把GPU/CPU上移定因为本改动，也不是稳定回退证明；B还缺两个后继Client文件，direct-host此窗口不走该控制面，不称严格单改动正式A/B。App均exit0/无timeout/failedFrames0，工具exit1仅原particle FAIL；视看保人物、星空、建筑与云层，时间/动态相位不同，不称全图一致或完整视觉兼容。

整体短筛不支持保留，立即停止扩测并精确撤回全部产品、设计登记及未执行测试接线；不为已花成本补Debug build、独立样本、三对或长切换。完整源码/patch、已运行pool事实、未运行Graph/Coordinator门标记及撤回SHA留`proof/rejected-prototype/`，静态/数值独审接受该边界。每帧新增pin/锁及resident遍历只是可定位额外工作，未单独归因；不能继续用减少pass数声称性能收益。当前不保留capture cache，下一项由性能/属性工作卡选序；共享DD的Release包含已撤回候选，后续使用前须重建。

本轮精确清理候选App、原copy实验binary/library和重复输出226,737,248B，保两张after图、压缩日志、输入身份、完整撤回源码与收据；连续迭代只复用原共享DD。证据提升先触32MiB单包上限、分别提升又触现有1GiB总额；prune无可删包，故保本批压缩最小材料于任务目录，不提高额度或删除未知历史。

## 后继：同帧无用source capture资格观察

冻结优化诊断App `34aa8e2b…`沿原资源encoder投影prepared读取，在Graph最终prepare、terminal preserve copy及replay替换之后，对指定frame1800只记录一次资格，不省略encode。真实304/单surface/60FPS/静音、duration50/warm30、关闭execution observations；启动ready为26.686秒，33行出现在ready后29.953–29.956秒。帧号由clock推进，观察不证明提交或完成，也不作为GPU/准备耗时或启动收益。一次Release诊断构建4294输入无漂移，临时两路径已精确还原；完整身份、patch及[原始报告](../../../.artifacts/tmp/dead-source-capture-observation-20261014/observation/report.json)保留。

[资格摘要](../../../.artifacts/tmp/dead-source-capture-observation-20261014/proof/observation-summary.json)与raw复算一致：同executor/reset/frame共33层、14,614,180pixels，eligible0，issues空，全部因`read-or-output-root`保留。33层均有materialReads（25层1次、6层2次、2层3次，共43引用），16层另有rootReads，共32引用；resource/replay/unknown/sideEffects均0。这些是prepared纹理引用计数，未按覆盖前后区分内容版本；因此停止本次“无任何读取或输出root”的简单候选，不能证明更细存活分析无机会，不实现产品、不计GPU节省。

App exit0、无timeout、测量窗failedFrames0，停止后surface1→0且gpuDrained；工具exit1含两项：原`particle loading incomplete`，以及33条临时资格日志被严格parser计为`resolved material graph observation diagnostic reported`。后者failed_outcome/gpu_failed均0，仍不称产品PASS；本次没有实际省略编码、像素对照、正式性能验收或能耗结论。


<a id="ordered-pair-segmentation-screen"></a>

## 后继：同帧有序双层分段短筛撤回（2026-10-15）

目标是保留全部graph/shader/draw，只把严格独立相邻层的 `graph A → composite A → graph B → composite B` 改为 `graph A → graph B → composite A → composite B`，减少主attachment边界。原OrderedLayerEncoding形成不重叠双层段，原Coordinator授予同epoch/commandBuffer/相邻ledger许可并严格A→B消费，原MainPass合成。原分配lease证明descriptor纹理独立storage，view追root、IOSurface整ID冲突，heap/buffer/未知来源拒绝；排除provider/group/utility/geometry/background/history/replay/local fallback及所有非空lighting，无新增allocation/copy/pin/cache。临时开关仅在Coordinator init读取，默认原路径。

11产品+7测试/fixture文件的最小试验已撤回。真实Coordinator新增22个资格/别名/顺序/撤权事实、真实GraphExecutor/MainPass/生产image shader的SDR/HDR×普通/旋转镜像整目标字节对照、反向draw反例、原fallback、资源/视频寿命及surface取消门均通过。两图fixture保持2 draw，main encoder 2→1；它直接编排图序列，不单独证明完整App。Debug26.787s与优化诊断Release37.368s通过，4294输入无漂移；Sol Xhigh独审冻结11文件无blocking。

同App `a7181afd8ac6dd920c00d34d1249350e5d3fc10d4e6ecc501f2a75b30b98129f` 在M4/3024×1964/单surface/60FPS、原3042492564输入与silence fixture运行，顺序B1/C1/C2/B2，仅分段开关0/1不同。每轮30s预热后64.5s测量，窗口内无构建、测试或profiler。实际首帧9对hoist，暖帧main pass36→27；离屏109、source capture33、material76、copy2及26902272B/帧均不变，GPU分配峰值548208640B、pool136262688B均相同。

| 顺序 | 进程CPU ms/s | GPU p50 ms | GPU p95 ms | CPU帧p95 ms | footprint峰值 B |
|---|---:|---:|---:|---:|---:|
| B1 | 840.370 | 10.694 | 11.544 | 9.737 | 813254288 |
| C1 | 843.391 | 11.051 | 11.883 | 9.776 | 834045632 |
| C2 | 832.776 | 7.798 | 12.703 | 9.702 | 830523048 |
| B2 | 827.231 | 8.512 | 9.098 | 9.473 | 799032976 |

候选两对CPU分别高0.36%/0.67%，GPU p95分别高2.94%/39.62%；GPU基线自身存在明显时段漂移，不能把这些差值称稳定回退或性能验收。两次均未证明整体收益，停止试验，不扩大段长、不追加正式三轮或独立样本矩阵。四轮GPU失败帧均0、正常退出/排空，严格报告仍仅原particle loading incomplete为FAIL；C2呈现超1.5预算比例0.8534%，其余0–0.0519%，不隐去该异常。首对原图的人物、塔、星空与时钟保留；wall clock不同，不作pixel parity。未测温度、功耗、多屏或正式Release。

产品aggregate `31ab2f8b0c969f929633f70ba7c38e31a1697759ffe634cf01cf708153e2193e`、完整patch `911eb638a7aa74cfa6ca5d492e5c6fc8271d626337bacae4b981add6e023c63e`、4份原FAIL报告/输入身份/构建与测试日志、首对必要原图保在 `.artifacts/tmp/main-pass-segmentation-screen-20261014/proof/` 及对应运行目录。冻结SHA核验后仅恢复本试验16个tracked文件到10efdf40、2个新增fixture归档后移除，保并行属性工作。临时诊断App、重复转储和不用的图像按归属清理，唯一连续DerivedData复用。执行顺序回现役性能卡，转查真正重复准备及跨切换资源保有，不以pass数量替代用户收益。


<a id="source-cost-qualification"></a>

## 源码成本归因资格（2026-10-15，停止）

为补普通image/source fragment的实际分支/访存归因，复用Debug App `97e6d9ea…` 与默认库 `41575aea…` 的现有INCLUDE_SOURCE信息，不另编source版本。原304、3024×1964/目标60FPS/静音，动态发现实际Layer，ready后30.613s抓一帧；未改变作者内容/尺寸/质量。首轮隔离cold准备超过原runner110s预算、未ready/未capture，原失败保留；因仅验暖帧源码资格，复用已生成磁盘cache重跑一次，不改产品timeout或验收期待。

第二轮成功capture1帧，App exit0/无timeout，原stop surfaces1→0/gpuDrained=true；既有particle loading incomplete仍为FAIL。Xcode回放勾Profile后明确提示：workload超过完整profiling支持上限，只能Lite GPU Timeline。Summary显示Lite/Overlapping/Medium、1 command buffer/145 render encoder/2 blit/162 draw/3024×1964 BGRA8；1.83ms仅为此次调试回放，不当真实App GPU收益。没有得到源码行/块Cost或texture-wait，资格失败；停止后续source重建、重复CLI ALU/heatmap与shader原型，不缩内容制造热点。

证据归`.artifacts/tmp/gpu-image-source-attribution-20261015/`与`warm-qualification/`的原始result/capture/xcode-qualification。Replay已由Stop GPU workload结束；close窗口观察超时，Xcode与replay仍持有trace的store0，630MiB trace暂保留待句柄退出，不清仍打开的材料。此工具边界不关闭GPU专项；下一项以新物理证据选题，原逐帧1128失败/诊断成本与属性媒体入口分别研究。


<a id="native-gpu-limiter-qualification"></a>

## 原生 GPU 阶段与 limiter 资格（2026-10-15，停止）

复用冻结优化诊断App `56ecb327…`，Release/-O/singlefile、DEBUG；原304默认属性/实际音频、单surface与原显示尺寸，隔离原生入口且媒体只读。ready后超过30秒，唯一daemon79650附一次公开Metal System Trace；保存的模板经重开确认Performance Limiters、Shader Timeline与Default GPU state，CLI请求8秒，实际run为03:43:28.804–03:43:38.027（+08:00）/9.223031秒。没有新构建或与采集并行的测试/benchmark/profiler。采集后原生quit退出0，隔离运行副本清理170,675,318B；未导出最终pin/drain或逐帧统计。

代理从Instruments的GPU Channel Activity Summary (Frame)全run转录目标PID行：

| 阶段 | Total | Avg CPU→GPU Latency | Max Duration | Count |
|---|---:|---:|---:|---:|
| Fragment | 3.75s | 8.13ms | 2.83ms | 38609 |
| Vertex | 339.17ms | 6.76ms | 1.69ms | 38559 |
| Compute | 248.17ms | 7.00ms | 2.81ms | 538 |

数值按GUI舍入保留。Total为累计阶段区间，Count为区间数，不是无重叠busy、完成帧数或每帧成本；CPU→GPU latency本身不是CPU提交等待或texture stall。Fragment主导目标累计阶段时间；同表WindowServer Fragment另有734.63ms/4380段，不能把系统GPU占用全归到Scene。未建立有界execution union/具体encoder窗口，尚不能判断idle与持续busy，也没有逐shader执行排名或源码行成本。

公开导出得到84行counter定义，但derived metal-gpu-counter-profile为0行；这不能推出raw采集为空。为核raw counter与shader inventory的联合导出体量失控，root在1,089,261,997B时精确SIGINT；工具退出1并删除partial。已见loaded shader清单只说明pipeline加载，不代表执行；raw完整行数、值及counter/device/time/target关联均unavailable。最少schema不等于小结果，此后停止重导出/重录，不继续全量解析或以空派生表推断瓶颈。没有取得texture/filter、ALU、LLC/MMU/带宽限制资格，不据此写shader优化或认领GPU/能耗收益。

模板SHA `bf207b62…`、原始run身份、完成的小型XML、GUI转录与资格/停止receipt归`.artifacts/tmp/native-gpu-counters-20261015/`。本轮trace正常关闭、不保存显示状态，owned Instruments正常退出；既有Xcode20658/Replay64627未操作。原recording压缩校验后按归属去掉展开包；唯一归档超promotion单包限额且现有cache已满，保任务目录、不扩预算或删除未知材料。状态仅`PARTIAL_TIMING_ONLY_STOP_NO_SECOND_RECORD`；普通image片元高成本与GPU专项仍开放，执行回现役卡。
