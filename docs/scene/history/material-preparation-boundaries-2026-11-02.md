# 材质准备边界整理后验

> **历史证据 — 非现役入口**

<!-- document-role: historical-evidence -->

> 2026-11-02 固定批次证据，不是整个 Scene 架构完成声明。现役目标归[迁移设计](../roadmap/engine-refactor-program.md)，未闭职责归[唯一队列](../roadmap/scene-open-breakpoint-queue.md#51-顶层设计已裁决的代码职责重构)。

<a id="m1-format-slot-handoff"></a>
## M1 格式与槽位准备交接

Catalog 将原 Demand 分析及 v10 持久缓存的格式槽结果交给原 Variant 准备入口；合法空集合与格式失败、reachability 失败分别保留。CompiledVariant 在准备阶段形成 mixed/named、候选 purpose、default 和 graph-input 事实，普通帧不再解析格式或推导这些静态形状；当前 publication、颜色/ABI、generation 与 GPU 使用期检查仍由原消费者执行。无消费者的共识透传和单字段 Selection 退出。

19 个产品文件净增 77 行：新增代码承载实际跨阶段事实，替换 Rendering 的重复推导；未新增源文件、owner、cache 或持久 wire。38 个测试文件净增 159 行，包括新格式结果反例及真实 API 接线；不以增删行、依赖边数或构建结果宣称性能收益。

### 身份与范围

| 身份 | 固定值 |
|---|---|
| 迁移前源码 | `02dce22bf7862eb60bc83f5a4d4e47a1d3602237` |
| 本批产品 patch SHA-256 | `a740a6e5acf0f86a602024cb0cc593949ce1d25b8bc453d6c1099aafffbaeb50` |
| 迁移前签名 App SHA-256 | `7f53c0969eed829c679276c18dbc8ebe93140c5df7eae9bdd5f6f6a444883d56` |
| M1 签名 App SHA-256 | `40cca59a65ddb392e6aaf0366f6e7089bd48a27900326c68a8e809d6e36d5381` |
| 签名 / 构建 | Team `H9QWU9XN8R`；严格验签；arm64 Debug、`-O`；构建前后本批产品源码身份相同 |
| 本机证据 provenance | `.artifacts/scene-architecture-continuation-20261102/` 中的 M1 源码、命令、原始日志、报告和 PNG；可用性按产物规则，不作为现役文档依赖 |

### 实际验证

| 责任 | 结果与边界 |
|---|---|
| 格式与准备交接 | Template、Finalizer、persistent-cache、graph source purpose、scalar mask、SamplerDefault、SharedPresence 通过；覆盖合法空/格式错误、格式有效但 reachability 失败及健康单元保留 |
| 当前帧与合成 | prepared material output、terminal graph、OptionalNamed、PreparedBaseImage 及 GraphExecutor 六个用例均有通过记录；首轮三项测试接线错误修复后只重跑对应失败用例，原失败保留，不把首轮整组选集改写成 PASS |
| 真实 GPU | SharedPresence 保原 shader/backend 与 R100/B50 像素断言；修正载体后，迁移前源码与 M1 均通过 |
| 签名 App 固定像素 | 新旧 App 各运行半透明 named 与三候选局部失败两例；ready/after 的固定 ROI 保原 99% / tolerance 2 门槛，健康 peer、后续帧完成和 GPU drain 均通过 |
| 原包与独立邻例 | `3351163962`、`3589819394` 同输入新旧共四次通过，输入 hash 相同、退出 0、无超时并正常 drain；复核 after 图保文字、背景与对应可见内容。墙钟、粒子和动画相位未冻结，不宣称逐像素等价 |
| 实际暖复用 | M1 半透明例复用同一隔离 HOME/cache 再播放，固定 ROI、后续帧与退出通过；两份 Demand v10 条目的内容及 mtime 不变。结合原 load 先于 parser 的接线说明复用边界，不冒充 parser 调用计数或启动收益测量 |
| 结构与治理 | 结构、断言、产物、依赖、残留、代码健康、防御棘轮及设计门通过；原四条实际内部引用退出后库存 44→40，余下真实结构债未关闭 |

### 保留的首失败与纠正

- 原 Template 载体把 Windows 盘符样式误作越界；当前 VFS 将其规范为 root-relative token。修正正反输入，不向产品补路径拒绝；真实 escape 的资源入口边界保持。
- SharedPresence 原 uniform 全零，真实 bounded vertex wrapper 按 `vertex_id` 读坐标 uniform，四点因此重合。原源码同样失败；仅以生产 HostUniformSchema/UniformEncoder 编码 unit quad 修正载体，原 shader、后端、纹理、像素及容差未改。迁移前修正载体再次通过，产品未为黑图加 fallback。
- SamplerDefault 的 throwing Catalog 构造补完整 `try` 传播；PreparedBaseImage 夹具补显式 `return`；OptionalNamed 删除重复 source；GraphExecutor 两处改用真实 Variant 返回入口。未放宽行为、counter 或像素断言。

### 未覆盖与后续边界

材质帧 template 双来源、静态 uniform 装配、launch 选择、设备准备身份和执行能力交接继续按现役设计处理；本批不关闭它们。当前 App 证据经过 direct Host，不能代替普通 App→client→daemon 完整控制链。未认领整体 CPU/GPU、启动或能耗收益，也未证明完整语料、物理多屏、长稳、官方 parity 或正式 Release。
