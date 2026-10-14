<!-- document-role: historical-evidence -->

# 帧纹理快照覆盖与 CPU 准备收敛（2026-10-14）

> **历史证据 — 非现役入口**。后续归[性能卡](../roadmap/performance-convergence-card.md)与[属性卡](../roadmap/properties-panel-card.md)，稳定值/生命周期合同归[运行架构](../architecture/runtime-architecture.md#frame-texture-snapshot-values)，未修视觉与矩阵问题归[队列](../roadmap/scene-open-breakpoint-queue.md)。本批只接收真实帧准备的局部 CPU 收益，不关闭整体 CPU、GPU、内存、启动、温度或属性专项。

## 实施前设计与通用语义

优化诊断 App 两次独立5秒采样中，graph overlay 含子调用分别占主线程59/1991、73/2919个样本；是 inclusive 采样证据，分类会重叠，不能相加或换算成耗时。比较回调绑定、云层编辑重建与纹理快照三处：前两涉及 fresh JS 引用/descriptor/副作用或候选事务，先选已有 Snapshot owner 的值存储，改动与验证边界最小。E1b设计在产品修改前落库，经独立 freeze `91a71f8e`批准；当时冻结全文与后验差异均留本机 proof。批准只允许实施，不代表性能或产品验收。

数据流保持 authored→prepared graph/resources→registry 冻结→同一 `SceneFrameTextureRegistrySnapshot`→原 Finalizer/Program→Metal。原每次覆盖都复制整个字典；现共享不可变 base，本值只保存扁平 replacement，lookup 先查 replacement。没有递归覆盖链、跨帧 cache、第二 registry、资源/完成 owner 或运行 flag；coordinator 的阶段、锁与帧协议不变，完整 environment atom 校验归 Snapshot，外部直接复制 entries 的旧路径退出。旧提供显式预计算 selectionDigest 的 snapshot factory 保留，避免改回每帧全表哈希。

全部输入先验证，非法批次原子拒绝，旧值/digest 不变；明确状态与 missing 不混同。每次摘要从当前有效 atom 增量替换，并对照独立期望全表；摘要相同仍须写入新物理纹理及内容代次。graph/source/named/background 保各自原 publication、purpose、storage generation、epoch 等条件，不把所有 generation 强制等于 frameEpoch。environment 的 unavailable 清 ready、missing 不更新，不导入旁键；完整 canonical atom 校验未放宽。

覆盖仍可能复制累计 M 个 replacement，成本为输入 K 与 M；没有承诺只做新键。共享 base 可能保留被覆盖的旧 atom 到最后一个合法 view 退出，但不通过链持有已替换的中间 atom。frame value 不进入新 Program/cache/pin/完成闭包。停止/取消不提前回收 GPU 或外部合法引用；最后值退出才是该值持有的释放界。若没有稳定实测成本收益或出现生命周期/画面退化，应撤回或重排；本批没有保留并行旧路径。

## 同条件实际 App

Apple M4，3024×1964单surface，60fps请求，静音fixture，94秒/30秒warmup，约62.5秒有效窗口；每轮 fresh HOME/engine cache，OS文件cache已暖，不并行构建、测试或 profiler。输入 Solar `3662790108`、project/package/matrix哈希固定。性能报告关闭 execution observations，保阶段/资源计量，不承担材质执行验收。App为Release配置加Swift DEBUG/-O、C -Os的优化诊断版，非正式Release；旧`c267a77f`、候选`82270924`。Debug与优化构建的4271输入前后均无漂移，实际产品差异只有两个 Swift owner。

| 指标 | 旧版三轮 | 候选三轮 | 接收范围 |
|---|---|---|---|
| admit-prepare-frame p50 ms | 4.764 / 4.820 / 4.833 | 3.429 / 3.438 / 3.440 | 中位数 -28.67% |
| frame CPU p50 ms | 12.188 / 12.346 / 12.199 | 10.841 / 10.866 / 10.808 | 中位数 -11.13%，该帧编码测区 |
| process CPU ms/完成帧 | 50.812 / 52.096 / 52.878 | 48.768 / 50.101 / 51.887 | 初组三轮中位数 -3.83%，返回不支持稳定改善 |
| process CPU ms/有效秒 | 1070.635 / 1075.956 / 1076.072 | 1072.888 / 1077.712 / 1076.105 | 中位数 +0.014%，未降 |
| completed / driver callbacks | 1317/2006、1291/2021、1272/1999 | 1375/2084、1344/2064、1296/2028 | 工作次数改变，不能忽略归一化 |
| GPU p95 ms | 49.053 / 61.489 / 61.558 | 50.925 / 51.519 / 61.758 | 波动/范围重叠，不记收益 |
| ready ms | 23199.528 / 23471.204 / 23627.635 | 23448.849 / 23326.715 / 23308.183 | 未证稳定启动收益 |

紧接的旧版返回→候选复跑，prepare p50为4.795→3.464ms、frame CPU p50为12.179→10.805ms，支持局部 CPU 差异随版本返回。process CPU/完成帧却为51.676→52.771ms（约+2.12%），有效秒时间率1072.696→1077.098ms，完成帧1297→1276；此负面样本完整保留，不把局部节省冒充整进程CPU或能耗降低。GPU p95为61.341→61.935ms，亦不计收益。

八轮零GPU失败。每帧材质pass、graph source capture、复制次数/字节一致；main/depth约半项的均值差来自采样窗端点，不是删内容。pool peak始终203,869,712B，GPU allocated约1.32GB；footprint峰值两臂交错，候选首轮还更高，不计内存收益。未测功率、温度、硬件频率或长期cache界，不能用未知热状态解释负面结果。DEBUG整表可见性诊断没有被删除，性能数值只归上述优化诊断配置。

## 局部成本与反例

优化 Swift 夹具直接编译真实 Snapshot/registry owner，Metal仅提供同一小纹理，计时使用进程CPU和wall时间，不提交GPU命令。旧源从精确父HEAD复制到任务目录，其他源码和 fixture 两臂一致。每形状1200次、五对AB/BA；原v1/v2试法及小表负面结果均保留，最终无产品flag。

| base N / 累计 M / 输入 K | 五对 CPU 差值范围 | 边界 |
|---|---|---|
| 8 / 0 / 2 | -11.23%至-3.81% | 小表稀疏 |
| 8 / 0 / 8 | -3.64%至+2.04% | 正负交错，不记改善 |
| 256 / 0 / 16 | -33.45%至-32.54% | 稀疏 |
| 2048 / 0 / 8 | -89.52%至-88.79% | 大底表小覆盖 |
| 1024 / 0 / 256 | -10.69%至-8.33% | 初次较多覆盖 |
| 2048 / 256 / 8，重叠 | -77.90%至-76.36% | 固定M的一步覆盖 |
| 同上，新键 | -79.88%至-77.87% | base外新增键 |
| 256 / 128 / 128，重叠 | +6.81%至+18.38% | 明确变慢 |
| 同上，新键 | +19.25%至+24.04% | 明确变慢 |

累计M在计时前形成，表中只量固定M下一步覆盖，不能称连续增长整段graph成本。实际App测量才包含真实整帧链。没有分配次数/字节计数，不从少一次字典COW推算物理内存或分配收益；接受的是代表App局部准备收益，密集成本保留为后继边界，不按样本或阈值增新算法。

## 正确性、真实画面与产品入口

新值语义门用独立期望表和全量digest oracle，覆盖显式五状态/missing、相同选择但新物理/content代次、重复替换、等价批次/顺序/独立分支、改名、wrong request/purpose/epoch、不完整及混合非法原子拒绝。weak A→B→C验证中间B不被最终C递归保留，合法分支退出才释放其值。coordinator补真实 endFrame / invalidate(.surfaceStop) 与最后external view释放；既有prepared/bundle取消、pool/pin及在飞提交门沿原退出顺序，不能要求cancel候选单独结束整个frame。

两处旧fixture因公有entries退役而编译失败：Finalizer的asset launch事实改取其原始additionalEntries（默认只新增graph，无asset遗漏）；空初始coordinator的摘要改用独立期望`.sceneEnvironment: .unavailable`。没有加入生产全表物化API或减弱原oracle。 静态重复组120→121来自两个原已存在的resource(for:)访问器现均按各自lookup提取ready：live stored-entry与replacement/base仍各有正确权威，无新算法副本。独审后用现有acknowledgedChanges记录精确窄调整，检测器、三行阈值及其他上限不变；不为这三行另造protocol/wrapper。新增7×5 retirement输入最初漏完整mip链，独审在执行前指出，修为mipmapped:true；产品canonical factory未放宽。

实际冻结Debug App的持续HDR、clear=true、首次绘制后隐藏的raw保留及暂停resize不推进VM四项通过；缺整套映射函数的专用故障App未提供，该项skip。严格观察的Solar通过，后期画面太阳/轨道/文字/侧面板保留；layer517/Data的`p1_longNode`局部fallback仍在队列，不称整景兼容完成。

预先选定的独立媒体样本2938612768，旧版与候选固定13矩阵都失败，十二项失败列表完全相同：text候选、solid842、utility/graph census及边框期待等。当前23图层执行/下一帧集合一致，contract成功、validation failures为空；两张后期原图中渐变背景、唱片卡片、文字和粒子保留，右下时钟裁切两版均有。原矩阵未改，不能把本批“未见新增差异”写成样本通过或把既有失败写成已修。

追加2684431262只做既有hash形状的边界回归矩阵，要求结构化stage、effect及graph/GPU/最终消费/下一帧，10图层通过，后期画面已检查；它不替代失败的fixed13矩阵。作者配置确有hdr/bloom=true及非零强度；报告`bloom_runtime_count`统计的是preview旧effect标签，0不能排除原生Bloom，也不能证明逐帧调用数。本批未从此字段认领Bloom GPU正例。

同268普通入口实际经SteamWorkshopService→App→client→daemon，唯一request/首present一次，3556帧；真实daemon桌面窗口图保环形图案、文字与粒子。停止日志VM9/9 quiescent、粒子/声音退出。其探针自动判定仅S3采集/发布，视觉单列；不扩为完整音频consumer、多屏或物理EDR。HOME/Workshop/样本放账号HOME外任务临时目录，安全策略不变。

## 验证与交接

55个选中模块的一轮日志保留，文档健康失败经修正重复调整记录及最终合同后窄复验闭合，其他产品模块原轮通过；结构、链接、依赖、健康、设计等11项其余门通过，Debug构建复用同4271输入零漂移的冻结App。专用故障App等环境skip仍按原门披露，不称全测试零跳过。最终独审及提交后身份复核保存在proof；窄设计登记已由稳定合同接管退役，E1只留当前链接。

证据根为`.artifacts/tmp/cpu-frame-preparation-20261014/proof`：App/构建输入、两次采样、八轮实际报告、局部AB/BA、原始失败、严格运行/产品入口、截图、freeze与审查。正式runs根接近既有1GiB上限，必要材料压缩限量留任务proof，逐文件核对后清理可重建App/HOME/cache/样本；不删除未知材料或提高预算。一份连续DerivedData仍用于后继迭代。

下一批联合追优化配置下VM/帧桥重复准备及实际CPU使用，保fresh引用、getter/setter、realm、副作用和事务。现cadence即使未呈现仍消费输入/回调，不能靠跳过作者工作换指标。云层约8.634秒编辑重建、首帧准备裁剪、连续轻重切换/cache回落、属性本地化/媒体/type与其他视觉问题均未完成，继续由原卡与队列推进。


<a id="snapshot-construction-direct-entry"></a>

## 后继：snapshot 构造去增长与重复查询（2026-10-15）

[原生分配资格](native-cpu-allocation-screen-2026-10-15.md)定位snapshot从空表增长。本批在原Registry中把既有状态转换移入私有Entry.lookupStatus，live lookup显式guard-let后委派；snapshot预留entries.count并直接转换已有pair.value，省去每项第二次哈希查询与构造期增长。仍逐帧产生必需独立值表，不缓存snapshot、不移除baseline/COW、不改变digest、epoch/index、publication或资源owner。resource-less ready仍nil，bare与无效publication仍按原incomplete，其他状态及missing保持原值；容量是上界，不承诺精确字节。

初版optional chaining在自有优化binary中生成Optional<Entry>临时区、第二次Entry copy与销毁，lookup三对中位回退19.52%；不能用snapshot收益掩盖。最终只恢复原guard-let解包，保唯一转换；机器码退出该额外copy，无inline提示或重复switch，不能把全部差值归因于它，也不是heap/RSS测量。原版源码、三对与反例汇编保留，不混入最终数字。

真实12产品源码-O门，两臂共同fixture/驱动共15冻结输入；各13个实际编译源（Registry附两臂相同test-only扩展）均无漂移。原18加10项oracle两臂28/28真：真实publishPersistent/set/snapshot、五状态/missing、独立全表digest、存储代次、同selection新物理atom、held旧snapshot跨set/下一帧与weak retirement。只有nil-ready注入私有Entry，不替换生产转换。共享PCM移动导致一次0.5秒工具前置拒绝，恢复原绝对路径后只重编受影响臂，不记产品红门。

同一baseline/final binary按B1/C1/C2/B2/B3/C3执行5个snapshot形状和lookup控制，三pair各5.54–5.60s，CPU窗均≥50ms、最短172.581ms；setup/oracle不计时，结果与代次可观察一致。配对C/B中位与B/C各自中位分别报告：

| 操作/N | CPU配对ratio中位 | B/C ns/op各自中位 | 基线偏差噪声 |
|---|---:|---:|---:|
| snapshot/0 | 0.9652323312 | 49.770/47.763 | 2.00% |
| snapshot/1 | 0.7365970513 | 725.058/533.291 | 2.15% |
| snapshot/8 | 0.4438757715 | 4006.810/1756.230 | 3.04% |
| snapshot/256 | 0.3989105753 | 122408.400/48978.400 | 0.30% |
| snapshot/2048 | 0.3940187031 | 991652.500/392934.167 | 0.62% |
| lookup/256 | 0.9891286454 | 321.947/318.447 | 7.39% |

非空snapshot局部降幅26.34–60.60%，超过局部门；空表不计明确收益。lookup三ratio为0.989129/0.906650/1.109639，交错且噪声>5%，不认领lookup收益、精确无回退幅度或完整非目标性能验收。没有App整体CPU、分配次数/字节、驻留内存、GPU、温度/能耗收益；不把原累计136.37MB全算可省。接受的是这一构造职责的局部CPU改善，不继续泛型/容器微调或启动正式App性能campaign。

一次Debug构建22.420s、4297输入零漂移，相对上一Debug仅Registry产品不同，App SHA `0468023c1752a6a942bd0a2ca5050a3e359a72f7d0ea90e2b584098b12d2f473`。同一原生App播放304再从实际库切独立293，两record各一次launched；原图检查保304人物/塔/星空/时钟及293角色/水面光环/星形/时钟，原生Stop再quit退出0。VM退役71/71、41/41 quiescent，timer/job/mutation/dynamicLayer均0；最终pin/drain未导出。原1128非有限origin、粒子/效果及系统媒体缺口不闭，不刷新旧严格矩阵、HDR/多屏或像素parity结论，未重复面板全交互。

Sol Xhigh独审核源码、派生输入、28事实、三对原数与自有汇编后ACK；实图由root检查，未称第二次独立视觉审查。源码/patch/完整原数与反例归`.artifacts/tmp/texture-registry-snapshot-screen-20261015/`，构建/native原日志、两张必要原图、源manifest及退出归其proof。只读源树复核无变化，已停止运行环境清242,495,769B；保当前App、必要基线与唯一连续DerivedData，冗余binary/cache按归属清理。下一项回现役卡，以新的真实GPU pass成本资格和属性缺口选题，不记整体性能专项完成。
