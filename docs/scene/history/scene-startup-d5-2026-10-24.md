<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

# Scene 启动 D5：目录字体字节与动态请求退休身份

> 截止 2026-10-24。实施顺序归[启动专项](../../development/wallpaper-startup-optimization-plan.md)，稳定边界归[启动合同](../architecture/scene-launch-responsiveness-contract.md)。目录字体读取、限定回归、签名及两输入产品资格已验证；正式性能卡未过，不认启动收益、无回退或 P2b 完成。本文不倒写 D4 的历史时点与失败结算。

## 原 owner 的迁移与失败边界

本批五个产品文件、七个测试路径，source manifest 与实际 D4-final before 对账，未用 HEAD 重构前驱。FontResolver 保系统别名及固定 App bundle stock owner，作者字体改从现 ResourceView 的原 package Root 取 exact/literal handle，以自持 Data 交原 CGDataProvider→CGFont→CTFont。初始 TextTextureLoader 与每屏 DynamicTextTextureStore 使用同一已建 Root；无新增目录枚举、字体 cache、物化文件或全局资源 owner。

作者范围保原 cacheDirectory 的 package 域，不扩 loose/custom-stock，不加索引 casefold。原文件不存在才尝试 known stock；选中后普通缺失/不可读/坏字体仍为 invalidBundledFont/Helvetica，不能转 stock。来源变化、非法 handle、逃逸和原取消由初始加载按 text 局部拒绝，动态 worker 沿 finish(false) 保旧完整 raster；原布局、装饰、纹理及帧 publication 不变。

真实 D4-final State 最小事件中，同 layer 删除重建复用 gen1，旧完成被接受；相同 harness 的 D5 旧完成被拒，新请求 gen2。原 State 改单个有界单调 issuer，unregister/reset 不重置，耗尽拒新保 ready，不 wrap、不留墓碑或另加 UUID owner。Store 读取前后查原在途 membership；连续新签名不取消已开旧任务，保单在途、追最新与进度。Session 尚无字体 CPU worker 的 cancel/join 接线，GPU drain 不替代该确认。

## before 资格、最近门与已保留失败

actual D4-final native 五项通过。旧 Store fixture 首先因缺 SceneTextDescriptor.renderedPointSize DTO 编译失败；仅补此 DTO 后，真实旧 State/Store 的原完整输出断言 1 项通过、0 skip。这是夹具资格修复。12 个 native fixture 的 before/current 原始 JSON 完全相同、无归一，覆盖既有字体 provenance、改名同字节、初始/动态真实像素与几何；不扩大为整景或官方字体 parity。

首批八模块 **41 tests、1 failure、3 errors、0 skip** 保留。失败来自新测试把既有 substituted stock 误写为 stockBundled、decoration/padding 旧 API 及 script runtime 缺真实依赖。只改四个测试文件，保原绘制/断言；五产品及成功模块输入 SHA 不变。

最终 **71 mixed 检查、0 failure/error/skip** 为两批去重汇总：复用 row-limit16、native5、geometry5、dynamic12，共38；仅重跑原失败 script10、decoration13、padding7、font-resources3，共33。包含 CPU/CoreText、真实 Metal raster 与 controlled Store，不是71项GPU或八模块同批全重跑。全源差异只在四个未复用测试文件；真实 opened-FD 换源、Root 转向/逃逸、原取消及失败保旧 atom 各按最近门证明。

结构门15项仍有3项失败：目录布局、render-chain inventory、声明完成状态。actual D4/current 日志仅 runner elapsed 不同，其余诊断/失败字节一致；不放宽 baseline，不将相同失败改记 PASS。另八个静态门（App debug布局、assertions、产物、依赖、residue、code-health、defense、design）通过。限定结果见 `d5-font-final-tests.json`、`d5-font-native-before-after.json`、ABA 与 `d5-structure-before-after.json`。

## 冻结构建与真实产品入口

Debug/WMO 构建通过，343.824988s，5909 文件的构建前后及计时全程来源摘要均 `fb756f342fe6747edbbcf85e44f91f3732a573aa8190d75be9b251fe413ce815`；executable `32b7399ff09e9e1eb43ebbdcec38a5305135d6744d2feffc0373d3ce633183dc`。专用身份为 com.songziqiang.MyWallpaperX.Debug.Startup，2.11.0(283)，Developer ID Team H9QWU9XN8R，deep/strict 验签通过；不认 Release/安装验收。直接前驱保留实际 D4-final signed App `49394ef80fb6e7d58dadf98fb55e2115280e1a74bb0ba6e1fa08fea4e07baafe`。

一次预登记固定五组、交替 AB/BA，两输入合计 **60 App/80请求** 全部资格通过；同 setAsWallpaper 产品入口、30 FPS、隔离 HOME/cache/偏好，实际 presented 与 parent finalize 匹配，正常退出及输入/App/生产偏好身份检查通过。C0 为新隔离 HOME/cache 的新 App，C1 为同内容/HOME/cache 的新 App，W0 为同 App 两请求的第二次、同 daemon PID/generation；不清 OS 页缓存。资格不代替完整画面/音频或 typed drain ACK。

| 五组中位，ms | C0 前驱 → D5 | C1 前驱 → D5 | W0 前驱 → D5 |
|---|---:|---:|---:|
| 自有四层字体 PKG | 813.994 → 798.017 | 784.835 → 802.284 | 26.283 → 26.555 |
| 独立五段 MDL PKG | 868.439 → 884.344 | 835.396 → 849.471 | 98.864 → 96.149 |

| 条件 | 前驱/候选最大相对中位偏差 | 两 arm 均≤5% | 非目标预算 / 中位变化 |
|---|---:|---|---:|
| 自有四层字体 PKG / C0 | 40.5319% / 6.9461% | 未过 | 81.0637% / 在内 |
| 自有四层字体 PKG / C1 | 5.5470% / 3.4465% | 未过 | 11.0941% / 在内 |
| 自有四层字体 PKG / W0 | 8.1117% / 25.8407% | 未过 | 16.2234% / 在内 |
| 独立五段 MDL PKG / C0 | 4.1491% / 3.0487% | 通过 | 8.2981% / 在内 |
| 独立五段 MDL PKG / C1 | 1.5268% / 2.5894% | 通过 | 5.0000% / 在内 |
| 独立五段 MDL PKG / W0 | 16.1808% / 4.1061% | 未过 | 32.3616% / 在内 |

六条件 raw `medianChangeWithinTimingBudget` 均 true；仅模型 C0/C1 满足两 arm 噪声门，其余四条件未过，所有 target false、`wholePerformanceCardPassed=false`。预算依原噪声规则得出；高噪声不能据此证明无回退或收益。保所有原点、范围与配对值，未删点、混池或重复到绿，详情归 `d5-runtime-analysis.json` 与两份原 report。

## 剩余边界与归档清理

[D4记录](scene-startup-d4-2026-10-24.md)的模型 W0 resource-progress→surface-progress 残余增量 +6.429ms 仍开放；这是父端观察重叠窗口，不是独占 CPU/GPU，D5不关闭它。独立 AV/媒体 URL 桥、字体 CPU join、可信 receipt/lease、package backing 与 extractor 退役仍后继，P2b 不结项。未验长稳、多屏、Release、能耗/温控和完整视觉/音频。

证据已提取到工作树 `.artifacts/scene-evidence/runs/wallpaper-startup-scene-d5-20261024`：320 个 payload（含 report），10,068,491B，manifest SHA-256 `819d4d5544ddcc8da0ae29e43a624a56ea0f245ff206aa2c51606a6e4cca174f`。全部原件与归档逐项核过 SHA/大小，`batch/report.json` 的 label→样本 ID 负责文件映射；默认14天、32MiB单包上限未改。完整 before/最终源码、原夹具失败、首轮current失败、两批来源与输出、ABA、构建/验签和全部计时原点均保留。后续文档治理、语义终审、清理与最后门的收据另存同根 `wallpaper-startup-scene-d5-20261024-closeout`，不改写已提取主包。D4受保护回退包继续保留，D5普通包不代替其未关闭复现。

`d5-cleanup-receipt.json` 记录实际删除246文件、136空目录，文件逻辑长度15,296,691B；包含已归档重复日志/源码/受控输入及可复建native binary、任务导入字节码，不等同实际磁盘释放量。精确计划均核归属及原件/归档哈希，执行时相关App/helper、benchmark及编译进程已停止、待删文件无打开句柄，没有猜删未归档未知项。

连续迭代保留 `/private/tmp/mwx-startup-optimization-fbRhFY/DerivedData` 一份构建缓存和最终签名App32b7，`d5-predecessor-app` 保实际前驱App493；D4的App4f/483为未解决回退继续保留。隔离 `inputs`、`d2-synthetic-inputs`、`d5-font-inputs` 留给后继验证，私有偏好备份不进入公开证据；少量文档before/治理快照留到closeout交接。未触及真实用户媒体/官方参考原件，未安装测试App。五正文预算按同path设计调整，600行硬上限及591永久redirect均未放宽；历史登记不增加正文预算。

代码、测试和文档均未暂存、未提交、未推送；主checkout保持干净，修改仅在startup-optimization隔离worktree。限定D5字体/身份结果完成不等于正式性能验收；持续goal继续，下一步沿原owner闭合独立声音的流式私有文件与CPU退出、可信receipt/同源lease及package激活依赖。
