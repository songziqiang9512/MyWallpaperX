# Shader 直接结果与可选缓存后验

> **历史证据 — 非现役入口**

<!-- document-role: historical-evidence -->

> 2026-11-03 固定批次，目标归[启动/缓存合同](../architecture/scene-launch-responsiveness-contract.md)及[重构设计](../roadmap/engine-refactor-program.md#shader编译结果与可选持久缓存)，当前证据与未闭项归现役入口。

## 职责退出

原 compiler 直接交付同次 typed artifact/encodedData，Program 沿原 makeProgram 验证并采用；退出“先创建持久目录、写 JSON、再读回才得有效结果”。可选 artifact 发布及 GenericShaderAnalysis 完整 store 在 utility 执行，single-flight/accepted program 不等待磁盘，不新增 pending mirror、临时 cache、worker 或 flush API。各写 tier 可独立创建缺失的合法 root/version，读入口不创建；根目录是文件、不可写、坏/过期 entry 均不撤本次正常编译结果。

2 MiB 只约束 cache 读/可选发布；工具 16 MiB 输出边界、makeProgram 的真实 MSL/ABI/颜色/资源边界保持。合法较大直接结果可用而不持久化，真编译失败仍局部 typed 失败。wire/schema 不变，未知/坏 cache 沿原冷链重建，不把历史文件作为播放许可。

4 个产品文件增 98、删 105，净 -7；16 个测试文件增 959、删 777。测试增长含原完整持久载体迁入 fixture、真实大产物/缺失目录与 native cache 故障反例，不代表新增运行时结构。

<a id="optional-cache-adoption"></a>
## 身份与实证

| 项目 | 固定结果与范围 |
|---|---|
| 基线 | `96e2709c9`；产品 patch SHA-256 `ff88b5267300acf010772938e63ca69f801dfbcbf2066d977a545ce08742f1e7` |
| 旧 App | `5e41db87ff8fb4a26bfdb4e52570fe9675caf2b82ee4c1dbf0c8c6140a96e5dd` |
| 当前签名 App | `a993632220c3b7628fe21ff0b0872e9771411a87e11df4406d91d1f6cdc81a47`；同时含独立 localStorage 批，arm64 Debug `-O`、Team `H9QWU9XN8R`、严格验签，6 产品文件构建前后 hash 相同 |
| 真实 cache 门 | artifact recovery、persistent tier、linked stage、prepared normalization、texture transform、dead binding、direct vertex、previous composite、release compiler evidence 分别通过；涵盖八 waiter、不同合同、重试、坏 cache、缺失 root 独立写、合法大 encodedData 不持久化及真实工具预算反例 |
| 当前帧/GPU | Alpha-only 和 derivative 修正载体后保持原 shader/backend、数据/像素及容差通过；不把编译成功当作像素结果 |
| 可复现原故障 | 同一半透明 named 场景，旧 App 的 cache root 为文件时 consumer 实际白色 `(255,255,255)`，原预期 `(50,20,40)` 的正确 ROI 为 0%；健康 peer 仍显示，原失败/输入保留 |
| 新 App 输出 | 正常半透明 named、三候选局部失败、root 为文件及真实 readonly root 四例均过原 ready/after 99% / tolerance 2 ROI、命令完成及 GPU drain；无关 root 文件原字节保留，readonly 目录没有条目 |
| 原包与邻例 | 不变输入 `3351163962`、`3589819394` 均通过、退出 0、无超时；墙钟/动画未冻结，不声明逐像素等价 |
| 本机 provenance | `.artifacts/scene-architecture-continuation-20261102/` 的 cache/storage source freeze、App identity、完整命令/原日志、result JSON 与 PNG；各批共享 App 身份如实注明 |

## 首失败与载体纠正

- Alpha-only 一处旧 inputFor(template,...) 在 M2 helper 去 template 后遗漏；仅去该实参，后续类型推断错误随之消失，所有原断言保持。
- Derivative 原两 backend 的 vertex wrapper 均读顶点坐标 uniform，但载体只填 renderSize、四顶点重合，读回 clear。旧源码同样失败；复用生产 SceneShaderQuadCoordinates.unit 的 packed01/23 填真实 offset 后通过。shader、两后端、`[.125,.125,.25,1]` 和 `1e-5` 未变，不为黑图加产品 fallback。
- Debug 构建本身通过；第一次 staging 缺任务父目录，仅补父目录后复制/验签，未重复构建或安装。

本批证明可选缓存故障不再阻断有效编译及上述实际输出，未认领整体启动/FPS/CPU/能耗收益、全语料、物理多屏、长期稳定、官方 parity 或正式 Release。材质其余准备交接、当前拓扑和完整产品 daemon 继续按唯一队列。
