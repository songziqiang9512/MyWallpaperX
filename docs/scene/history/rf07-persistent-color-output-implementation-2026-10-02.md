<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF07 原始颜色历史与显示导出实施证据（2026-10-02）

> **历史证据 — 非现役入口**。当前权威：[兼容路线](../roadmap/scene-compatibility-roadmap.md)、[能力台账](../capabilities/coverage-ledger.md)、[运行证据](../capabilities/runtime-evidence-current.md)。本批未改三个受保护的能力/运行/重构总表。

## 范围与责任

主目录 `codex/engine-refactor-program`、HEAD `85415320`，在已冻结 D2/D3、RF01、RF05、RF03 未提交成果之上实施。完整开工字节在 `/private/tmp/mwx-rf07/baseline/`，只审相对该基线的 RF07 差异，不把其他批次纳入本片。合同见 [D2 RF07-HISTORY](../roadmap/batch2/hdr-tonemap-edr-design.md#rf07-history已实施的原始颜色与显示导出边界)，稳定资源责任归[架构 §3.3](../architecture/runtime-architecture.md#33-保留事务安全不扩大视觉失败半径)。

HDR clear=false 的作者合成写入未 Bloom、未显示映射的 raw sceneColor；已有 allocation cache/residency 保存 raw pair 和 display scratch，原 SubmissionCoordinator 只在 GPU 成功且 epoch 匹配后提升 completed raw。每 surface 最多一个 pending candidate；同 epoch 同 simulation frame 重绘只导出，resize/reset 后用同一 snapshot 初始化新 extent 并合成一次，不推进 VM。首次 seed 使用项目现役不透明 clear color；该初始化策略不宣称官方初帧语义。

显示导出从 raw 复制到 scratch，Bloom 与项目自有 SDR shoulder 仅处理显示端。映射或显示 scratch 编码失败可退回安全 raw 输出；不能导出则取消 surface 候选。取消、提交拒绝、GPU failed seam 和旧 epoch 不提升 raw；busy 不回放 VM/模拟/粒子命令。空 graph、paused export 和 clear=true 的 exact display scratch 也沿现 coordinator 持有提交 pin，reset/stop 等待 terminal 后释放。D2 私有 intermediate 缓存撤去，不增加第二资源池/compositor；非 HDR 仍绕过映射。clear=true 只需一张 exact scratch，不额外常驻 raw pair。

## 反例与修复

本机证据根 `/private/tmp/mwx-rf07/`：

- `red.txt`：修前真实 MainPass/显示 owner 输出红色3，无法得到应有的11/12；非 HDR/clear=true控制通过。后续 owner 门直接编译实际 pool、coordinator、MainPass、Bloom、mapping 及 Renderer 终端颜色 helper，fixture 不实现自己的 history 或 fallback 状态机。
- 独审发现 clear=true 复用 composition scratch 会被2048尺寸上限缩小，导致 exact-copy检查跳过映射。`large-red.log` 的真实2056²反例失败；修复为现 pool 精确尺寸用途，并沿原 coordinator pin 至 GPU terminal，避免 reset/eviction 提前释放其预算。
- 独审发现 mapping preparation失败且无Bloom时，drawable可能保持 framebufferOnly，阻断 raw blit。View 由HDR终端的真实读写需求决定配置，不再依赖可选mapping对象初始化成功。
- `app-resize-diagnostic-before-oracles.json`：旧诊断请求在resize后延迟0.15秒，错过paused唯一重绘；应为1512×982的resize-00实际采到3024×1964。Runner改为resize accepted同步返回后立即排入capture，早于现异步重绘。此反例使用未完整签名的v1构建，仅作为局部诊断；最终App重新正常签名验证。
- `app-before-normalized.log`：最终作者夹具在旧签名RF03 App上失败；frame0 visible且实际提交完成，frame1 hidden，ready/after却为黑透明，旧drawable load不是可靠跨帧历史。更早benchmark曾保留255，只能证明那次运行，不能据此宣称旧history稳定。

初版 App oracle错误地把普通layer tint的3当超白输入；现役颜色lane会归一化到0…1。`app-resize-diagnostic-before.log` 的191是正确的M(1)，不是新history缺陷。最终App夹具显式输入1，期望191；真实超白3由浮点GPU owner门验证。保留旧错误假设和失败日志，不以改product颜色合同迁就夹具。

## 冻结身份、执行与独立终审

`final-v3/manifest.json` SHA256 `7e909fbaebe296e6f8a578c0f89ff870d7cad09547dcc206c3f34607e54fb3fb` 保存33路径、29项相对baseline变化。最终产品仍是v3；追加真实helper故障门的两个测试身份见 `helper-v4/manifest.json`，最后一个App测试身份见 `root-test-v4/manifest.json`。三个manifest组合与当前文件全部匹配。

`build-v3.log` 为默认签名 Debug BUILD SUCCEEDED。标准 `frozen-v3.app` deep/strict通过，CDHash `ee87fcbee3e7dc22a2f3967e562cfb6cc026d479`，team H9QWU9XN8R；20项实际binary/dylib/metallib身份见 `payload-v3.json`。v1未签名构建和签名校验失败单独保留，不能替代v3验收。

- `helper-v4/owner-v4-final.log`：4 tests PASS，28.730秒。实际raw3连续八次导出保持11/12，半透明两帧按独立raw/display golden累积，真实Bloom切换不回灌；空graph/display-only pin、cancel、failed completion seam、stale epoch、同frame新extent、分配1/2/3失败、预算、peer与恢复均检查。真实Renderer helper另覆盖首个blit失败后的安全raw输出、两次blit失败的dropped/cancel不提升、mapping preparation nil及seed入口。
- `bloom-v3.log`：14 tests PASS，15.904秒，保留D2颜色、非有限值及编码失败/恢复门。Pool和Coordinator各1项通过，见 `adjacent-v2.log`；该混合日志另有旧Bloom夹具接口未迁导致的setup error，已由独立14项重跑替代，不把整个旧日志写为绿。
- `app-integration-v3.log`：标准App四项 PASS，93.074秒。3024×1964的clear=true输出、连续clear=false、draw-once后隐藏仍保留191，以及paused半尺寸/恢复门通过。`app-integration-v3/` 保存11张terminal PNG、原始作者输入、日志和矩形bounds；1512×982的bounds恰为一半，恢复与原图相同。paused窗口两次新allocation使用同一simulation frame完成，没有VM witness更新。
- `app-mapping-failure.log`：独立故障派生App一项 PASS，21.047秒。只从metallib剔除mapping对象并重新签名；launcher的代码段和真实产品debug dylib保持相同，差异仅metallib与launcher签名，见 `fault-derivation.json`。派生CDHash `175c8a65bec360f466c1aeab5df086232562ad25`；缺函数日志、raw255 PNG及后续 completed/mapped=false成立，不将派生artifact当标准App。
- `no-capture-fault/`：同派生App不传evidence-dir，开启Metal API Validation，首帧完成切换、142次mainPass、framebufferCaptures=0、gpuDrained=true、exit0且无validation错误。它排除了诊断截图强制framebufferOnly=false的掩蔽；关闭诊断时逐帧submitted/completed统计未启用，其零值不是失败或性能结论，不声称该次有完整逐事件GPU记录。
- `code-health-v3.log`及追加`helper-v4/code-health-v4.log`通过：1047 Swift、0错误、237条既有warning；主Renderer颜色编排移入已有ClearColor扩展，未放宽1000行硬门。scene-defense、design-gate通过，无基线增长。

独立只读终审核对最终源码、三个测试身份、两个App的各20项payload、上述实际反例/图像/事件以及guard真实产生者后接受本有界实现，无剩余阻断finding。审查者未运行测试、构建或GPU。

## 未验证边界与交接

GPU失败是实际命令成功后向现completion seam注入failed，未制造设备故障；不保证预排队present后的物理像素瞬时回滚。多surface为受控owner门，非物理多屏。透明输出、EDR、官方曲线/parity、长稳和性能完成均未宣称。4K raw pair+display scratch约189.84 MiB，属于已准入成本，不是性能优化结论。

没有暂存、提交或推送。标准/故障冻结App、独有失败与执行日志保留供复核；故障metallib的四项AIR输入及SHA另存fault-metallib-inputs。本批RF07与前序D2/D3共用的两处DerivedData已按cleanup.json精确清理，约2.4GiB可重建缓存；后续能力只按唯一P路线及中性行为证据推进，不因本片完成开放未知uniform或mip profile。
