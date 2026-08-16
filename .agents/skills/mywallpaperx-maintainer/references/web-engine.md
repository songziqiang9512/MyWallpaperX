# Web 开发方法

本参考保存 Workshop Web 中难以从单一文件恢复的模型降低、request/surface identity、资源安全和生命周期方法。当前 owner、host strategy、能力和运行结论只从现役 Web 文档、当前代码和当前证据读取。

## 目录

1. [按问题选择权威](#按问题选择权威)
2. [重建唯一生产链](#重建唯一生产链)
3. [Request 与 surface identity](#request-与-surface-identity)
4. [模型、属性与本地化](#模型属性与本地化)
5. [资源与 origin 安全](#资源与-origin-安全)
6. [页面生命周期](#页面生命周期)
7. [Web correctness atom](#web-correctness-atom)
8. [验证与反漂移](#验证与反漂移)

## 按问题选择权威

先读 `docs/web/README.md`，再只加载命中项：

| 问题 | 唯一入口 |
|---|---|
| 当前 owner、生产 host、当前事实与未闭合边界 | `docs/web/current-state.md`，随后核对当前代码/运行 |
| 稳定作者行为与兼容边界 | `docs/web/wallpaper-engine-web-rules.md` |
| project/descriptor/runtime/context 分层 | `docs/web/web-project-json-runtime-model.md` |
| 原始声明、派生值与本地化 | `docs/web/web-project-json-localization.md` |
| 运行证据、评分和声明口径 | `docs/web/web-wallpaper-benchmark-standard.md` 与当前 gate manifest |

不要为一个 navigation bug 预先加载全部 Web 文档。历史样本、旧 PASS、host 名称、route、cache version 和 matrix 成员不进入 Skill；它们只对各自当前入口或历史截止日期负责。

上表中的现役文档裁决 Web 目标与当前事实；下文只给出如何追踪 identity、owner、资源授权和验证边界的方法，不能覆盖这些合同。

## 重建唯一生产链

沿当前代码验证：

```text
read-only authored project and dependency roots
  -> stable descriptor interpretation
  -> session-effective runtime model
  -> minimal immutable playback projection
  -> current playback/switch owner
  -> one production Web host
  -> per-display WKWebView surface
  -> navigation/bridge/property/resource/input/audio/visual result
```

类型名和 host strategy 从 current-state 与代码重取。Diagnostics harness、placeholder 名称或旧 daemon 路径不能因“已经存在”获得第二产品执行权。若替换生产 host，目标合同、原子 owner transfer、旧 owner 撤权和回滚必须同批明确。

每个 consumer 从同一 runtime interpretation 降低，不从 raw JSON、descriptor、UI state 或 cache 另开平行解释链。cache 是带 fingerprint/signature/schema 的派生物，不能反向成为作者合同。

## Request 与 surface identity

对每个异步 producer 定义 typed envelope，按实际链包含：playback intent、request、record/project、display、surface、navigation、WKWebView/process、property replay generation 和命令/event identity。

关键方法：

1. producer 创建 work item、property delta、directory/media/audio demand 时捕获来源 identity；不要在投递时读取 mutable `currentRequest` 重新贴标签。
2. playback owner 在改变共享状态前校验一次。
3. host 在合并 payload、扩大 readable roots、启动 watcher 或注入 WKWebView 前再次校验。
4. JavaScript timer/listener/replay 绑定 document/surface/navigation generation；Swift owner guard 仍是主防线。
5. stale rejection 同时记录来源与 current identity，不能从 current state 反推旧事件归属。

至少覆盖：A request 延迟事件在 B 后到达、同 record 快速重启、旧 navigation delegate、surface replacement/teardown、WebContent delayed recovery、display removal 和 audio demand 撤销。`recordID`、路径或 webView 存在性单独都不够。

teardown 要撤销 delegate/work item、message handler、scheme task、watcher、media/audio demand、input forwarding、surface registry 和 pending replay，再释放 WKWebView。只改 current ID 而不停止 producers 会留下跨 request 写入。

## 模型、属性与本地化

模型变更先读取稳定 runtime-model 合同，识别当前阶段的 owner 和允许的降低方向。descriptor 保存稳定作者解释；runtime model 合并 session-effective property/root/profile/diagnostic；playback projection 只携带宿主需要的 immutable 数据。当前类型可能迁移，职责方向不能由 Skill 中的旧类型表决定。

属性链保持 authored key/value/condition identity。localization 只影响 AppKit label、description 和 option text，不能改 persisted/runtime value。property update 带 producer-time identity；stale delta 原子丢弃。`file`/`directory` 变化在扩大 readable root 和 watcher 前再次校验 request/generation。

semantic input、effective value 或 cache key 变化时，同批更新真正受影响的 fingerprint/schema/signature，并加 stale-cache 反例。decode 失败回到安全重算，不写回 Workshop root。

## 资源与 origin 安全

运输方式由共享、可测试的结构/风险 profile 选择，不能按 sample、站点、路径、文件名或截图切 route。每个资源 request：decode/normalize URL，解析 symlink，确定声明 owner root，解析后重新 containment check，只允许 project/dependency roots 与由现役安全合同明确授权的 file/directory roots；路径存在或出现在 payload 中本身不构成授权。保持授权粒度：`file` 只授权解析后的精确文件，不得提升为父目录；`directory` 才能授权其合法后代。返回正确 MIME/range/cache/error。

路径逃逸、单资源越权和局部 origin 混淆默认只拒绝对应 resource task；只有入口、root authority、surface 或 request identity 整体非法时才终止 Web playback request。optional missing resource 可以局部失败。不要通过任意 `file://`、全局 CORS 放开、禁用 WebKit 安全或扩大根目录换兼容。固定文件名/目录 heuristic 若仍存在只是待收敛 current fact，不是新增特判的先例。

## 页面生命周期

- Compatibility bridge 按 bootstrap、property/plugin、resource rewrite、media、DOM lifecycle 和 interaction 分责；只实现有来源边界的共享行为，不固化页面 DOM/asset identity。
- Web media 属于当前 request/surface，不转交 Video helper；pause/resume/mute/reload/teardown 使旧 element callback 和 demand 失效。
- 输入只在当前 surface 和明确区域短时接管；surface hidden/teardown 后立即撤权，不长期抢 focus、Space 或桌面全局事件。
- 系统音频是共享稀缺服务；只有有效 request/surface 的真实 demand 才保持 consumer，pause/switch/crash/teardown 时撤销。页面/host 不建立第二长期采集器。
- plugin/RGB placeholder 只声明实际返回行为，函数存在不等于硬件兼容。

## Web correctness atom

```yaml
target_current_debt: author/runtime contract; current code/evidence; deviation
first_breakpoint: parse | model | property | resource | host | navigation | bridge | input-audio | environment
identity: request + display + surface + navigation/generation
user_result: one observable page behavior
failure_radius: smallest binding/resource/surface/request
counterexample: stale/reload/teardown plus an unseen structural fixture
evidence: host stage + same-request behavior + visible/event result
```

修共享 owner 并加入同 family 未见 fixture，证明不是 Workshop ID、site、path、filename、asset 或 DOM 特判。optional binding/resource failure 保留页面其余部分；资源越权拒绝当前 resource task，非法入口、无合法 surface 或 request-wide root/identity 失效才终止当前 Web playback request。失败不应重置无关 Video/Scene output，除非当前切换合同明确要求。

## 验证与反漂移

从当前 `script/tests`、Web benchmark `--help`、risk gate 和 machine manifest 选择最小门。parser/property/cache 先定向 harness；lifecycle 必含 stale/teardown；Swift 产品变化再 build；可见声明再运行全新隔离 runtime home/output 和直接相关内容。只有同一 App/build、request/surface/navigation identity 的行为与画面证据才能支持相应结论。

不要用 host ready、navigation finish、handler 存在、非黑图、单样本或 matrix 汇总证明完整兼容。完成前确认只有一个产品 host、没有平行 runtime interpretation、资源 root 安全未放宽、旧 request 无法写新 surface、输入/音频 demand 会撤销、cache 与语义 identity 同步，并明确未运行的发布/性能/长稳边界。
