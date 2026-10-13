<!-- document-role: historical-evidence -->

# HDR 终端 attachment 输入与驻留收敛（2026-10-14）

> **历史证据 — 非现役入口**。后续归[性能卡](../roadmap/performance-convergence-card.md)，稳定职责归[运行合同](../architecture/runtime-architecture.md)，设计与边界归[D2](../roadmap/batch2/hdr-tonemap-edr-design.md#clear-true-attachment-mapping)。本批接收有界复制/驻留收益，不关闭整体CPU/GPU耗时、呈现波动、HDR视觉或属性专项。

通用语义：清屏HDR帧无persistence/main-target raw reservation、无既有source material/shadow receiver/reflection预算耦合，且实际设备/单sample RGBA16Float attachment和准备期可选PSO支持时，唯一显示owner直接读取color(0)，应用原RGB/headroom/alpha函数。原graph准入成功后、首个optional/source/named-shadow请求前冻结输入；其余组合沿原texture输入和全部原容量保护。预算反例由真实pool复验：图40+终端40时拒阴影50、源20仍可用；不能删除占位后让阴影先挤掉源。未按样本、路径、hash或截图选择。

原作者合成、raw反射快照、Bloom、显示映射及提交次序保留。可选函数/PSO缺失在准备期保原必需owner；尾部encoder失败不迟换输入，SDR保安全画面、linear拒本帧。新旧输入及Bloom前都消费原MainPass完成事实，暂停raw仍由原coordinator证明；真实主clear失败不读未初始化目标、不提交，下一帧恢复。此处同时修旧texture路径的存量安全缺口，没有第二完成、history、输出或资源owner。

## 同条件真实App测量

Apple M4，3024×1964单surface，60fps，静音fixture，94秒/30秒warmup，约62.5秒有效窗口；每轮fresh HOME/engine cache、OS文件cache已暖。关闭execution observations，保分阶段与资源计量；这种performance-only报告不承担材质执行验收。Debug checkpoint通过，性能App为Release配置加Swift DEBUG/-O、C -Os，实际命令/response已封存，非正式Release。4271个构建输入在两次构建前后无漂移，后续产品源亦未变。

主样本3287715210初三轮旧版`40dc7426`与候选`c267a77f`：

| 指标 | 旧版三轮 | 候选三轮 | 接收范围 |
|---|---|---|---|
| 已计数copy/帧 | 2 / 2 / 2 | 1 / 1 / 1 | 少一次终端全屏复制 |
| logical copy B/帧 | 95,026,176 | 47,513,088 | -50%；不是物理带宽 |
| pool sampled peak B | 184,225,856 | 136,712,768 | -47,513,088，25.79% |
| GPU allocated sampled peak B | 591,593,472，各轮相同 | 542,572,544 / 542,572,544 / 542,621,696 | 少约46.70–46.75MiB；与pool重叠，不相加 |
| process CPU/完成帧 ms | 5.797 / 5.699 / 5.893 | 6.671 / 5.402 / 6.486 | 未证稳定收益，首组中位数反而+11.88% |
| GPU p95 ms | 8.710 / 11.279 / 10.922 | 10.401 / 11.249 / 13.484 | 未证稳定收益 |
| ready ms | 5351.849 / 4922.744 / 4829.993 | 5576.108 / 4926.674 / 4811.541 | 未证启动收益 |

各轮约60fps、零GPU失败；候选第三轮GPU max19.55ms、超过16.67ms一次、present间隔超过1.5预算23次。追加旧版回跑CPU为6.323/5.596ms，候选第四轮5.765ms；相邻旧回跑/候选第四轮GPU p95为10.841→12.689ms。原负面信号全部保留，不能写成“GPU无回退”。Process footprint峰值有交错，未声明稳定整进程物理内存下降。

为隔离输入方式，另制同候选机器码的legacy消融App`61bf1c40`：仅从任务副本MSL移除可选attachment函数，用原候选Metal参数重编该AIR，其他四个AIR逐字节不变，再签同团队隔离副本。签名command/payload之外的Mach-O代码哈希一致，必需fragment/helper保持原文；没有产品flag或另一套算法。三对AB/BA依次运行，输入、工具、尺寸、音频、暖机和窗口相同：

| 配对 | CPU ms/完成帧 legacy→attachment | GPU p95 ms legacy→attachment | present超1.5预算 legacy→attachment |
|---|---|---|---|
| 1，legacy先 | 6.414→5.896 | 11.333→10.484 | 28→0 |
| 2，attachment先 | 6.135→6.237 | 8.303→11.431 | 0→0 |
| 3，legacy先 | 6.311→6.484 | 10.314→7.569 | 1→1 |

六轮零失败、复制/驻留差异一致。GPU差值正负交错，较多late也在旧输入出现；该消融未证明稳定总耗时变化或具体波动成因，不能以未知时钟/温度/竞争免责，也不能把全部波动归因于.load。十五轮原报告与未舍入数值均封存。整体CPU、呈现时序、功耗与温度仍归后续性能排查。

单独尾部GPU诊断使用冻结候选App的原metallib、同3024×1964非均匀raw、private目标，每次包含相同reset copy；sRGB/linear1/linear4各60对交替，attachment每对更快。GPU中位时长分别1.301/1.273/1.324ms，对照1.962/1.974/2.006ms。它只量该primitive及共同reset，不证明整个CAMetalLayer帧、CPU、能耗或物理带宽。seal阶段CPU p50旧五轮67–75µs、候选四轮44–53µs，也不扩大为整进程收益。

## 像素、真实播放与生命周期

真实Metal/Swift owner门比较15,050像素，含奇数/非方尺寸、边缘/strip对角、只具render-target usage的目标、SDR/超白/负值/非有限、alpha、headroom1/1.2/4/16/非法值；两输入逐位相同，另有独立公共ColorSync容差oracle。真实HDR Bloom先产生黑邻居光晕，再经两显示输入仍逐位相同，encode不编译。原单亮texel未过既有降采样/threshold，只证明两输出相同；改用自有7×7亮区后保留halo断言闭合，没有改产品Bloom或放宽oracle。

新门保准备期可选函数/PSO故障、真实主/终端encoder故障、最小预算、取消/释放及下一帧。旧history门暴露共享fixture存量ABI错配：CPU Vertex步长24，MSL漏coverage为16；只补MSL字段，保原蓝像素与rollback oracle，三个消费者全部通过。最终宽门另暴露共享coordinator carrier漏接video/timing/reportToken与draw-only旧签名，补既有依赖叶子，视频误调用明确拒绝；七个接口/文档模块复验通过。material-copy-history还持旧PMA标签/像素预期与同一顶点ABI欠账，按现役普通effect直色合同同步精确标签，保原PMA半透明输入、两字节容差及serial/in-flight/data/resource-phase断言，独立反关联后推导IIR；四组原收敛oracle、typed-data、原资源阶段与生命周期均通过，没有修改图执行产品。不能归因为默认metallib缺失，这些fixture使用显式内联library。

实际冻结Debug App四项通过：clear=true、持续HDR、首次绘制后隐藏的raw保留、暂停resize不推进VM；缺整个映射函数的专用故障App未提供，该项skip，不能借仅缺可选函数的消融冒充。GPU carrier不编译完整SceneDrawing，实际Renderer绑定由这些App运行和真实样本负责。

20秒后捕获及严格执行观察检查3287715210、未参与修法的2684431262、3666041758和3662790108，全部运行通过，原画面/颜色/运动未见新增缺损。268非零HDR Bloom作者配置及25材质执行保持，copy1→0；366604图源消费者copy6→5；Solar copy3→2。后两者曾按题材预选为legacy邻接，实际均满足attachment准入，已纠正，不能计作旧路径反例；“图源消费者”不等同prepared source-material预算分支。clear=false/history与可选函数缺失的实际App另验旧输入。Solar现有layer517脚本局部fallback及其余队列视觉断点保持开放，不称整样本兼容完成。

普通产品入口用268的只读来源副本，SteamWorkshopService→App coordinator→client→daemon实际首present一次、3555帧，并保存真实桌面窗口图；停止时audio/surface/VM退出。该产品探针本身只判S3 capture/publication，桌面图是独立视觉观察，不扩成完整音频消费、官方parity、物理EDR亮度或多屏验收。首次把HOME放工作区被原disjoint策略在dispatch前拒绝；重跑移至账号HOME外任务临时目录，未放宽安全门。

## 交接与产物

设计先于实施：窄登记经独立freeze `fcdf904e`批准，后验合同移交运行架构；旧HDR批准没有被扩大。95个选中模块经原宽门和八个失败模块窄复验闭合；结构/链接/依赖/健康/设计等11项其余门通过。构建复用4271输入零漂移的既有Debug和优化诊断App；缺专用App等环境skip保原边界。最终冻结diff/输入身份、独审结论与清理收据保存在本机proof；最终提交不把App、缓存、原始媒体或生成诊断源码加入Git。

证据根为`.artifacts/tmp/hdr-attachment-mapping-20261014/proof`，关键为`final-measurements.json`、`matched-input-ablation-comparison.json`、冻结App/编译与源清单、GPU/App门日志、真实截图和产品入口结果。正式runs根已近1GiB且无过期包，不删除未知未过期材料、不抬预算；必要证据在任务proof压缩限量保留，按校验归档清理本轮停止使用的App、HOME、样本、cache及重复输出。一份连续迭代DerivedData保留于`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`。

下一批优先联合看优化配置下CPU热栈/分配与呈现时序；减少VM候选/帧桥的重复准备须保持realm、getter/setter、副作用、事务和取消。现encoder复用/Bloom尾部合并是后继设计方向，不能凭本轮primitive优势直接扩入。云层编辑重建、首帧准备裁剪、轻重连续切换/cache回落和其余HDR视觉仍未验收。
