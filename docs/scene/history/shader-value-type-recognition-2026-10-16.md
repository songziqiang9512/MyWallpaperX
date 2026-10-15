<!-- document-role: historical-evidence -->
# Shader 类型名识别成本局部收敛

> **历史证据 — 非现役入口**。截止：2026-10-16。性能选序与整体验收归[性能卡](../roadmap/performance-convergence-card.md)，shader 当前能力归[覆盖表](../capabilities/render-graph-shader-coverage.md)。本记录合并一次启动归因与随后局部修正，不计整体启动、CPU/GPU、RAM 或能耗收益。

<a id="value-type-recognition"></a>
## 启动归因及边界

3662790108 的 instrumented Debug 启动在约 78.731s 触发一次 `/usr/bin/sample`，请求窗口为 **5s**；14.193s 是 sampler 进程寿命。只采一个 App、没有 helper 栈，晚出现的三个 helper 未补采。栈链落到 Variant preparation → BackendCanonicalizer → ScalarVectorBroadcastNormalizer → consistentValueDeclarations/valueDeclarationFacts → ValueType.init/Dictionary.init；嵌套栈计数不是 CPU 百分比，不能推为完整启动成本分配。

该轮 120s 看门狗终止，未 ready、exit -15，精确回收后 owned process group 为空、inputDrift=[]；没有样本画面或 GPU drained 证明。独审确认同 rewrite 每次 assignment 重建完整 immutable declaration facts 再按 before-index 过滤，是可继续研究的重复工作；同时发现 prepare-end 的 clock 标签应属 resourcesStageStart 累计，但本轮并未出现该事件，不能把标签问题当本次归因结果。Sound 前轮 prepare-catalog 约70.338s 已包含 model-build 约43.313s，不相加。

## 原 model owner 内的最小修正

先选择风险更小的类型名识别：`SceneAuthoredShaderFrontendModel.swift` 内 `SceneAuthoredShaderValueType.init(authoredName:)` 原本每次构造19项 alias dictionary，现改为同域 switch；19个映射与 unknown→nil 逐项保持，不增加 cache、另一套类型事实或普通帧工作。最终产品文件 SHA `005c4e6df519220d5efb404c07c2b4903aaba51111a9b17076b4f8517d2160d6`；复杂声明事实重建本批未改。

局部输入为运行期解码的16384个自有中性 token，约20%合法 alias，并非 corpus 分布；两臂19合法/132非法邻居验证通过，共用 byteSize/alignment 访问及外部 UInt64 checksum 防止省略工作，预热在计时外。`-O -whole-module-optimization` 与 Debug `-Onone` 各三配对，顺序 B/C、C/B、B/C；目标 arm64 macOS26、Swift6.4工具链/Swift5模式，使用相同 SDK/工具链与输入。

| 局部识别 CPU | baseline → candidate 中位 ns/lookup | 配对降幅中位 | 基线 / 候选最大噪声 |
|---|---|---|---|
| `-O/WMO` | 358.833 → 26.145 | 92.714% | 2.563% / 3.461% |
| Debug | 784.546 → 143.954 | 81.687% | 2.981% / 0.962% |

两种模式均满足性能卡更严格的局部 CPU 条件：降幅至少10%、超过基线噪声两倍、两臂主要计时噪声不超过5%；未改变原先锁定的5%短筛门或测量值。它只接受 lookup 局部收益，没有 App/non-target 成本测量，不换算成366或其他样本的启动秒数、帧成本或能耗。

最终 Developer ID Debug build 22.231s、4278输入哈希稳定，deep/strict 签名验证通过；App executable `dc8a30a7ac3b247aee5b376b64dd2f5c4ea14b288a106d45fa5e051095448051`、debug dylib `de92598b3edb8cb64a0fb7ab9ae52c3cf24b0b77019ff8f7d29039f3482fe526`。Sol Xhigh 独立最终静态审查GO、0阻断finding，核实精确enum及实际checksum循环；build/签名只证明该构建身份，不替代实际 compiler 与画面回归。

## 独立真实回归

独立原始2932157836完成真实 compiler/画面回归：ready42.005s、总51.177s、exit0、inputDrift=[]、surfaces1→0、gpuDrained=true；主代理实看人物、星空/光环、时钟日期与默认音乐icon可见。properties/playback两个媒体action均accepted、各generation1，但266/325仅generation1空白16×16发布，maxWidth仍635/625，无后继文字重发或可见媒体标题；本次maxwidth资格未取得可达门，按预锁一次后STOP unknown，不强开visible、不跑304。既有launch-program-failure与color-transfer-unresolved仍出现，不写VM全健康、整样本PASS、完整媒体通过或性能收益，也不与其他运行ready计时比较。

## 证据去留与后继

启动收据与独审保留 `.artifacts/tmp/scene-startup-attribution-20261016/`；局部完整配对、noise 复核、精确 enum/harness/token/case 身份保留 `.artifacts/tmp/scene-value-type-recognition-20261016/result.json` 及同目录材料。局部二进制/模块缓存及本轮已退出的样本/HOME、generated source、重复图已清理；保原字节实图、neutral JSON与压缩日志，唯一连续DerivedData仍沿原路径，不声称逻辑字节等同物理释放。

单次 rewrite 内声明事实重复扫描仍是候选，须先有额外集成与整体成本证据再决定；不因局部 lookup 收益惯性增加 cache、扩大重建策略或重复启动五对。真实 compiler 回归、完整启动与该候选是否值得继续分别裁决。
