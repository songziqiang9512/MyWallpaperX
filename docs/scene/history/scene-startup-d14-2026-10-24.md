# Scene 启动 D14：恢复原 Metal 门与资源窗口采样停止

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**
>
> 截止：2026-10-24。顺序、成本与重开条件归[启动专项](../../development/wallpaper-startup-optimization-plan.md)。本批修改测试与其验证/证据导航；没有产品实现变化、App构建、提交、推送或安装，不认启动提速。

## 原门修复及职责

D13已定位原pass encoder夹具把两个真实16B主机坐标填成4B Float，原门在进入机制探针前失败。D14将该4行默认值修正落入永久测试，同时把内联native代码按真实职责迁到独立编译单元，避免继续维护约三千行的Python/Swift混合单文件。

| 文件 | 职责 | 行数 |
|---|---|---:|
| `script/tests/test_scene_resolved_material_pass_encoder.py` | 原唯一方法、产品源闭包、隔离环境及全部原Python断言 | 182 |
| `SceneResolvedMaterialPassFixture.swift` | 作者shader/Program输入、Metal纹理与读回夹具；两项坐标SIMD4默认 | 720 |
| `SceneResolvedMaterialPassColorCases.swift` | 颜色/alpha关联、格式与像素输出 | 725 |
| `SceneResolvedMaterialPassDisplacementCases.swift` | Flow/Shimmer及原CPU oracle | 741 |
| `SceneResolvedMaterialPassScalarCases.swift` | 标量纹理与载体 | 178 |
| `SceneResolvedMaterialPassPipelineCases.swift` | 输入反例、局部负缓存、reset/warmup与原archive | 384 |
| `SceneResolvedMaterialPassHarness.swift` | 原顺序及结果汇总，含原Terminal probe展开后315行 | 52 |

Swift文件均在 `script/tests/fixtures/`。原Terminal probe263行字节不变，不生成或拼接三千行巨型main。原`SUPPORT`和产品`SWIFT_SOURCES`导出保持，真实texture-transform消费者继续用原闭包；原sole method名称不变。六个新fixture沿现验证登记只选择原pass encoder门，两处repair ledger变量引用迁到ColorCases，原方法引用不变。

四组原case操作body仅移除一级缩进，字节核等；118项表达式与原Terminal23项共同构成原141个唯一key，无新增、丢失或重复。主入口仍依次运行color→displacement→scalar→pipeline→terminal；跨组使用同一encoder及原baseline、authoredTexture、rgbaTarget和second PreparedPass。独审逐项核提前求值只读已捕获Bool/像素数组与不可变字段；live counter/texture读取仍在原操作点，局部GPU均同步完成后读回，后续不依赖已结束中间资源累计驻留。

## 验证及保留的失败

迁移首轮Swift编译失败，native未启动：Displacement抽取漏传原encoder。原case主体不变，仅函数声明和主入口补传该encoder后再做一次编译资格。首轮源、argv、stderr与结果完整保留；没有删断言、拆表达式迎合诊断或native重采。

最终原唯一方法通过：编译28.987s、native2.615s，均退出0；原141项结果全部true，0失败/错误/跳过。129个实际Swift编译输入及7个拥有文件前后双SHA稳定，binary SHA256为 `3160050dfd1fdc70fefcd567424df2e554a3791c10209d2b3077362fcdc1b224`。主Agent另从原始stdout核141个key/值，并核最终7源、Terminal及报告SHA。此处是1方法/141事实，不是141方法。没有第二实际GPU，`crossDeviceExercised=false`；原no-Metal输出shape缺陷保持，未声称验证该环境。原samplingVariant未读值warning保留，其prepare调用有真实副作用，未为清warning删除。

验证选择器68方法通过；代码规模、Scene依赖和断言门通过。新fixture逐个计划核均选择原门，无unmapped。该测试恢复能约束后续shader/Program/Metal改造，不证明官方等价或产品整体无回归。

## 真实入口与失败的外部采样

使用D12已签名Debug.Startup App，exe SHA256 `01c4a7296936607efea48db3c72cb4e4ebda88baa037277c3285f89013d0256d`。用已冻结D8 publisher二进制从任务只读副本一次自然发布可信receipt，未调用旧builder针对当前源码重建，也未手写manifest/marker。沿唯一benchmark原stage、defaults、run_selection、计时与清理核运行一次C0/C1/W0组：3App/4请求，30FPS，正常退出。

四行父端commit后的`admittedSource`均与该publisher实际source完整匹配，三项出版guard、作者字节、生产偏好和原App/helper身份均前后保持。原工具清测试标准域/private suite、App/children、临时HOME及staged App。此组为诊断资格，不作正式冷暖前后对照。

只对该W0 App实际拥有的Scene daemon PID9369启动一次 `sample 9369 2 1 -mayDie`；argv0、flag、lstart/command与W0原生行匹配。收尾等待5秒后采样器仍运行，被驱动精确终止，exit=-15，未生成`sample.txt`/Callgraph；只有采样开始banner。没有native或attach重试，不称热点归因通过。原因未进一步证实，不能承诺延长等待必能成功。原驱动v1把“观测到退出的时间上界”当覆盖证明，在执行前已修正，始终`phaseCoverageProven=false`，v1原件也保留。

## P3裁决与下一门

离线复核D10/D11当前managed旧记录：W0 model约36–39ms、resources约96–98ms；catalog-decode约5ms后至capability-catalog的差额为82–86ms。该窗口同时包含原StockNoise CPU生成/同upload队列的mip等待和ExecutionCapability/variant准入，不能独占归给诊断、noise或纯分析。现有variant profile是并行worker时间之和，不等于关键路径；没有实际cache hit/miss与noise demand/elapsed字段。

不增加完整PreparedContent/Runtime缓存；现Facts/Model含Root/FD、URL及覆盖后属性，现shader preparation/frontend/generic/analysis各缓存继续原owner。下一步先在原NoiseStore/VariantCache对叶级工作做有界资格，再决定减少工作或复用，不凭源码循环数、旧C1包含daemon的组合时间或本次失败采样实施缓存。DEBUG SourceFacts还建立额外引用/能力报告，混入model窗口；不将其成本外推Release，也不为保存死报告新增零caller产品入口。

P4/P5条件STOP保持，D7/D11 seek、D4残余成本、Web C1及完整P2/P3/P7余项保持。当前App资格和原门恢复不覆盖30分钟稳态、完整睡眠/唤醒/多屏/最低设备或正式Release验收。

## 产物和 Git

最终测试收据 `final-source.json` SHA256 `529a7f4c6f3117be001b108cd7cd8fabb825add6a025c78cdca99b3cbef69611`。本批保护包 `.artifacts/scene-evidence/runs/wallpaper-startup-scene-d14-20261024-checkpoint/` 保原编译失败、最终原始native输出/输入、迁移/独审、真实入口及未解决的sample失败。D13原门失配已闭合，其原包材料合并到本包后清原重复包；原任务来源通过report的sourceAliases查实际sample ID/payload，不按已清task路径打开。

原门临时编译目录与私有archive已自动清理。最终包核验后清本批停止使用的出版副本、隔离运行目录、迁移/采样准备和提取副本；精确清单另存任务顶层 `d14-cleanup-receipt.json`。连续任务仍仅留 `/private/tmp/mwx-startup-optimization-fbRhFY/DerivedData` 一份构建缓存及跨批仍引用的材料。未操作其他会话App或真实用户媒体，全部后续实施保持未暂存/未提交，goal仍活动。
