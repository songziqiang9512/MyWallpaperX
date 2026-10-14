<!-- document-role: historical-evidence -->

# 原生一帧 GPU stage timestamp 资格（2026-10-15）

> **历史证据 — 非现役入口**

本记录只存资格事实；方法归[诊断合同](../architecture/gpu-stage-timestamp-diagnostics.md)，选序归[性能卡](../roadmap/performance-convergence-card.md)。旧Instruments全量导出、Xcode Lite及无收益shader消融仍停止，不因新方法重试。长期Goal继续active。

## 接受的范围

M4公开probe仅timestamp/atStageBoundary支持后，先落设计、独审再接原Telemetry→实际descriptor/draw→原CB completion。1024点及512KiB JSON上限；真实surface/coordinator身份、取消/stale、clear-only缺口与非DEBUG原路径均落实。未增加执行owner、encoder/CB拆分、barrier、等待或重放；稳定方法留作后继GPU对照，设计窄登记退役。

31产品路径freeze aggregate `47579027a5253f5fc6103c99e4ad41ea8af4a645bbd85566826842813e1575b9`；helper SHA `c80554b5c148806b2b06f46e1b9af75b731245394df697bdf2da6ca2412920e9`。12 render工厂、6原帧blit、17真实draw、2 main关闭点经独审逐一核对。最近门直接编译真实Telemetry/helper，26事实通过，无ABI stub、无Metal device/CB；它不证明实际采样。

## 单次原生结果

同一次共同Debug构建，4298输入无漂移；首建51.365s，唯一后继是将调用参数换行合并、恢复FrameDriver1000行的20.392s增量构建，语义门未重跑。最终App SHA `3d66673365c6f56435aca0341e1630562c78afd5747c856ed32c67975df440b7`，普通Debug非优化诊断/正式Release。构建含并行clearColor片；最终两笔提交共用该冻结App，不冒充逐提交独立构建。

304原内容/默认属性/实际音频/3024×1964单屏；设置delay45，host mach_absolute_time与wall-time关联估计首帧完成后44.910s选中frame773、surface1，coordinator/reset/effect/execution身份完整。parent92357/daemon92377，无并行编译/测试/profiler。唯一JSON SHA `fd397607…`；584索引连续唯一、4672B，CPU/GPU校准跨度均45,816,042，换算比例0.001µs/tick，独立重算全部报告区间无差。

145 render＋2 blit；144实际draw render和2 blit区间有效；ordinal6是空main，保留附件工作未覆盖。它的raw点也有值（VS2.750/FS411.791µs端点差），不能称draw或完整clear成本。CB GPU时长11.768292ms，raw端点包络一致。draw FS累加15.664581ms、union10.008874ms；已解释阶段union10.215752ms，不是独占成本/利用率。空main点机械并入后union10.215835ms，仅多0.083µs。

| 观测 | elapsed | 直接限制 |
|---|---:|---|
| main0 / source482 FS | 1226.917 / 1189.750µs | 彼此重叠964.375µs |
| main27 / source986 FS | 979.708 / 980.125µs | 彼此重叠964.208µs，后者目标仅207×428 |
| source583 FS | 723.500µs | 与material482重叠473.250µs |
| framebuffer snapshot / graph copy blit | 693.125 / 31.291µs | 同样是区间，不计独占份额 |

初始校准→首GPU点33.891ms混CPU准备、提交与排队，没有commit marker，不归CPU或GPU idle；末点→最终校准0.156750ms也不当产品延迟。长FS及小目标长区间不足以判断texture/ALU limiter，不按layer或ordinal改算法。

root核原桌面图仍有人物、塔、星空和实时时钟；正常Stop→CmdQ退出0，71/71 VM quiescent，failures/timers/jobs/mutations/dynamicLayers=0，两个PID消失。原视觉问题不关闭；未作完整矩阵、最终pin/drain导出、多屏、长期切换或性能收益验收。

本轮26事实、相关原生验收与代码健康通过；结构/文档17项中目录登记失败修正后只重跑该项通过，其他16项复用。全局dependency与test-assertions未全绿：HEAD `a55ed7dd` 已有SourceMaterials→RuntimeCatalog未登记职责边及改名后的5条源码形状断言，本轮相关文件均未变；不扩大baseline放行，转现役后继。

## 后继与材料

只读相关作者JSON证明source共享capture owner但输入不同：动态图像/atlas和当前主目标都存在，不支持缓存完整帧或删除作者效果。静态非压缩2D TEX的shared/private准备期比较保为AS2条件候选；现GPUOptimized/lossless事实不能保证private更快，额外上传及staging峰值必须计入。先复用原上传queue/completion/资源账做有界筛选，无稳定收益就退出，不扩App campaign。

`.artifacts/tmp/native-pass-timestamp-qualification-20261015/`保probe、设计/独审/源码身份、26事实及正式门；`.artifacts/tmp/native-stage-and-clearcolor-20261015/proof/gpu/`保唯一JSON、原图与正常退出/暖态收据。用户源只读且3份源tree复核不变；本轮已停止HOME/tmp/样本副本和被替代App清理，保当前可复用Debug App、原声明的优化诊断基线、连续DerivedData及共享shader cache。旧大型唯一trace不删除、不扩大预算。无稳定CPU/GPU/内存/能耗收益claim。
