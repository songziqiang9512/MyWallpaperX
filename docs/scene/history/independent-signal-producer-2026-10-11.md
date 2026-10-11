<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。稳定合同归[shader覆盖](../capabilities/render-graph-shader-coverage.md)，当前结果归[运行证据](../capabilities/runtime-evidence-current.md)，剩余工作归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# 独立信号 producer 可选 alpha 写入（2026-10-11）

## 首断点与改动

3248220186 的 GodRays `101#effect#179` 在 `godrays_downsample2` 被 compiler colorTransfer 拒绝，五节点 effect 整段局部回退。作者 NOISE=0 变体只有 whole 输出；现有 source analyzer 已接受这种形式，但 MSL lowerer 无条件要求额外 `.w *=`。这是既有合同两端不一致，不是缺少光束算法。

从同一 analyzer 提取 typed ProducerFact，原 ArtifactBuilder 将 source slot 与可选 alpha multiply 事实传给同一 lowerer。保留单颜色采样、数据投影、slot/carrier 和输入去预乘，信号输出维持原始值。whole 输出必须赋值；有遮罩时必须在其后仅一次 alpha multiply；缺失、额外、提前、非乘法及下标写入漂移均拒绝。无新 profile、renderer、运行 owner、缓存版本或样本分支。既有成功编译语义未变，旧失败产物没有发布为成功 artifact，无需全局 cache bump。

产品基线 `492f8fa46ecb89286bf1e7f1abfc4a1564642b53`；三文件 diff SHA256 `c3f308b4d0162442cc3c77e865c236771b21ab55b3807e9065c778189ade4a4a`。独立只读审查发现第一候选未拒绝下标输出，补齐后复审无产品阻断。主工作区三份 U06 在途文件未纳入。

## 验证与实际画面

- 固定旧产品红门：1 个测试中 4 个子例失败；最终 producer、compiler artifact、straight-alpha 三模块 12 项通过。正例覆盖有/无遮罩，反例覆盖 source/artifact 输出写入漂移。
- Debug build 成功。最终 App executable SHA256 `b4c9db3fdf8fc78024c0eec17d182cac75550d315e6e0da7cc441195847cf2f8`，debug dylib `bbc3b014b22aa28d83cbf150e527f635f066d11886cf65ce289ed830ea175933`，CDHash `ce2046768fa366fa5e87ae1441fc72866a07b619`。签名前后核验通过。
- 使用真实原包的隔离副本、原参数、同一签名 App 的直接 Host 窗口；不是普通 App 选择→桌面、系统音源或长稳验收。用户解锁后已取得真实 presentation。

| 原包 | 结果 | 边界 |
|---|---|---|
| 3248220186 | GodRays 5/5 节点进入 Program，0 rejected；GPU 完成、compositor 消费及 next-frame 成立。截图可见蓝紫球向外放射光束。最终 299 GPU completion / 298 presentation / 0 GPU failure，排空并 exit0，隔离 benchmark PASS | 首轮启动截图采集失败，保留失败收据；仅重跑此例后通过。两球层 14/72 持续出粒子，2157 虽加载仍无已证发射。运动、密度、大小、强度与官方差异及音频响应仍待修，不能把 PASS 当整样本正确。 |
| 3807668787 | 原 GodRays `25#effect#802` 的 producer→accumulator→composite 继续执行，截图中头冠和剑仍呈亮色发光；298 GPU completion / 296 presentation / 0 GPU failure | 整包 FAIL：可见鼠标轨迹 958 因 `alphatocoverage` 不受支持而 unavailable，另有粒子预算诊断。此轮只证既有 GodRays 回归，无外部音源，不宣称整样本或频谱完整验收。 |

324 的 Program 为 `70eb7b6999e729485421d8dd171593426b258a87a51b410ced576b2046198c1f`，两张 `1024x665/rgba16f` target；原 Blur `101#108` 保持 4/4 节点。约 5 秒测量窗不具备稳态资格，不能声称性能收益。官方截图仅用于确认放射光束的存在及整体方向；viewport、时间和音源不同，未证明逐像素或数值一致。

## 验证工具边界

原 utility 工具把所有 prepared capture 数量当作实际必须完成数，导致默认隐藏、从未激活且无命名消费者的 265 误报。沿既有 utility failure owner 对完整 capture identity 集核对，消费既有 visibility/graph 解析结果；只有证据完整的 dormant 层可排除。曾可见、命名提供者、任何实际 graph 执行观察、显式 required ID 或 capture 失败仍必须检查；身份/历史缺失不放宽。兼容当前 producer 的可选 trigger 字段，不新增日志解析 owner。

工具独审指出仅看 GPU 已完成成功层仍会漏掉 `outcome=succeeded gpuCompletion=-` 的非终结执行记录。沿原 graph observation owner 输出全部实际观察 identity 后复用，补非终结和失败反例；此门不修改产品呈现。最终 5 个 CPU 模块共 213 项与 3 个工具结构门通过；原始日志离线重判收据保存在证据根，运行时工具与最终重判版本分别登记。既有超长 benchmark/主测试文件仅窄改，未声称本批清完工具结构债务。

## 产物与后继

证据根 `.artifacts/tmp/independent-signal-20261011` 保存精确身份、原始日志压缩包、最终两张原始截图、红绿及独审收据。真实媒体只读；staged App/HOME、原包副本和重复输出在提取后清理。连续迭代只复用 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData` 一份缓存。两份最小提取共30,577,147字节，低于单包32 MiB；promotion仍被全局1 GiB预算拒绝，prune无可清条目。未提高预算、未删除未知证据，必要结果暂留原根。

本批关闭可选 alpha 写入这一公共合同缺口；只新增证明一个真实受益原包，不能关闭其他同名光束问题。下一步优先 N03 多段材质函数类型转换：24 段 multistage_wave 有同类实际首错，现有 direct-function argument owner 可接入；N07 粒子范围/方向还需官方行为边界，暂留后继。先复现原函数形参/实参转换，严格复用原类型事实，保留 out/inout、重载及未知类型拒绝；不得触碰主工作区 U06 并行改动，不能据同名效果宣称全部受益。U19 鼠标轨迹独立断点已回填队列。
