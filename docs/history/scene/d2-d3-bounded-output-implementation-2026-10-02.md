<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# D2/D3 有界输出首片实施证据（2026-10-02）

> **历史证据 — 非现役入口**。本记录不决定后续任务顺序。当前权威：[运行证据](../../scene/semantics/runtime-evidence-current.md)、[能力台账](../../scene/semantics/coverage-ledger.md)、[兼容路线](../../scene/scene-compatibility-roadmap.md)。本次按并行工作区约定不修改前两项及 engine-refactor-program；后续能力汇总应引用本记录，不能把旧 L0 总项直接理解成所有子能力均未实现。

## 冻结职责与实际结果

接管 `codex/engine-refactor-program` 的 D2/D3 未提交首片，基线 HEAD `85415320`。修改限 material preparation、既有 source capture、共享 light snapshot、唯一 compositor 后处理及其测试/治理登记。未创建分支、未推送。

- D2：HDR 且每帧清底的不透明终端，在 Bloom 后做一次项目自有 SDR shoulder；保持 display-referred sRGB，不另套 gamma。非 HDR 与 clear=false 不创建该 owner。中间纹理沿现役预算、只缓存当前尺寸；PSO 仅 launch preparation。失败保留原合成颜色。
- D3：真实内建 genericimage2/4 的 material pass `LIGHTING` 默认与 instance 覆盖，进入 immutable profile；共享 snapshot 传 point/spot/ambient。修正 UV Y、完整 world model、非均匀尺寸、逆转置法线、spot 方向及无 normal 与 neutral normal 的一致性。显式 black ambient 不被恢复成白；缺省维持原兼容值。
- 无 effects receiver 使用既有 offscreen source capture 与最终 compositor；graph claim 使用相同 fragment。Puppet/mesh 无可证明 source-atlas→world receiver 映射，局部保持 unlit。捕获失败回退完整 direct uniforms，保留透明度、tint、brightness、sprite UV；不会跳过 graph claim 或 source-copy 的拒绝。
- 内建 shader 身份归同一 helper；删除 profile 的未消费 PBR 占位字段、重复 quad 及重复 snapshot 计算。miss 诊断仅记有限 reason，避免长期累积 layerID。

这不是 EDR、PBR、阴影、reflection、ltube、任意作者 normal 槽、透明输出或官方像素 parity 的交付。clear=false 需要 raw sceneColor/history 与显示结果分离，见 [RF07-HISTORY](../../scene/design/reference-evidence-implementation-cards.md#rf07-history--clearfalse-原始颜色历史已移交证据)。

## 修前反例与修后门

| 问题 | 可执行反例 | 修后证据 |
|---|---|---|
| HDR 超白仍输出大于 1，SDR 裁成同白 | 原 Swift 曲线对 1、1.5、3、5、12 未保留 SDR 内层次 | 真实 Metal 分别约 .75、.8333、.9167、.95、.9792；16F/8-bit 高亮阶梯、灰/彩色、非有限与失败恢复通过 |
| clear=false 重复映射保留像素 | 实际 SceneMainPassEncoder 的 load/no-draw 连续两帧，修前 FAIL | factory 直接消费真实 hdr/clear flags，反例及整个 Bloom/display mapping 模块 14 tests PASS |
| 受光坐标与法线错误 | 矩形、旋转、上下光源、-Z spot、缺 normal/neutral normal | 12 组 GPU case，独立 world oracle 最大误差 .000327；neutral 与缺 map、下一帧恢复逐像素一致 |
| 捕获失败丢作者 uniforms | 真实 compositor + capture/draw stub；alpha=.25、彩色 tint、非 identity UV；旧 Compositor 单文件 overlay FAIL | 同一最终 fixture 修后通过，下一次成功 capture 使用 target 与 neutral final uniforms；相关 3 tests PASS |
| graph fixture 串用 shader 分析缓存 | 不同 shader 共用 `executor-contract-node` 假摘要 | fixture 采用真实 stages 摘要；不放宽产品颜色合同；完整 graph executor 测试 PASS（90.549s） |

其他已运行模块包括 base material binding、lit image GPU、pipeline repository、graph resource、direct draw、copy history、runtime bridge、static-model light snapshot、material render state、asset catalog、runtime input。新增 builtin identity 的独立编译 source lists 已同步。不是全量 suite 通过声明。

完整 Debug `BUILD SUCCEEDED`；code-health 1042 Swift/0 error（236 review warnings）、scene-defense 0 dead/18 canonical/3 swallow 保持、design-gate PASS、文档角色与治理 25 tests PASS、diff check 通过。独立审查两次：首次拒绝 clear=false 与 capture fallback；返修后 D2/D3 均 accept。审查另核对 shader digest 和 normal ROI 修改，未靠改期望绕过产品失败。

提交恢复复核另发现 shared preserved-channel fixture 也使用按 node index 生成的假 shader 摘要，使不同通道源码及合法/非法 uniform 反例串用分析缓存。只把测试 producer 改为真实 stages 摘要，不改产品缓存。隔离 D2/D3 暂存快照的修前两个反例失败，修后使用专属缓存根运行 material-copy/history/visual-failure 三模块全部通过（211.4s），独立复核接受。日志保存于 `/private/tmp/mwx-commit-recovery/copy-history-stage01-real.log`。frame-local-unique 仅在完整当前工作区复跑通过。该早期快照文档角色门有两项 HEAD 既有失败，均来自 sampler-alias-precedence 未登记；在修改该合同的下一 RF01 批补登记，不能将此快照报告为全部门绿。

## 实际 App 与像素证据

隔离证据根：`/private/tmp/mwx-d2d3-takeover.BNPvJb`。真实样本先复制到该根，原 `~/Movies/MyWallpaperX/创意工坊/Scene` 未写入。benchmark 使用隔离 HOME、样本与签名 staged App，结束后 staged runtime 自动清除，日志/JSON/PNG 保留。

构建与内容身份：`build-source-identity.json` 固定 26 个产品文件；App 2.10.0(280)，Developer ID team `H9QWU9XN8R`，CDHash `df1170f62f22d3ac0a1227f7bec294a8df7bc77e`，执行前后签名身份一致。Debug 真正产品 payload `MyWallpaperX.debug.dylib` SHA256 `9f4c1309c5e4cf2c81069cf926185b6e8d09c2991db91f97e92f33208ea40a9e`；`default.metallib` 为 `98565898fd56250ddf077a0e2b61394180b88844d4dc093f4b5317bb41104388`。不能只用启动 stub 的 hash 代表产品代码。

受控作者输入从隔离 2815826216 保留真实材质与 layer 20，只去掉 effects、固定相机，黑环境光、单 point；改变 LIGHTING / light intensity / HDR，包摘要在 `witness-matrix.json`，生成 recipe 为 `make-lit-witnesses.py`。这是生产作者入口→material profile→实际纹理→source capture→terminal present 的证据，不能冒充原样本 parity。

| 受控输入 | 3024×1964 输出中心 50% ROI 平均 RGB | ready→after |
|---|---|---|
| LIGHTING=0 | 108.016 / 98.321 / 90.125 | 逐像素相同 |
| LIGHTING=1，point intensity=1 | 36.568 / 33.073 / 30.127 | 逐像素相同 |
| LIGHTING=1，point intensity=0 | 0 / 0 / 0 | 逐像素相同 |
| 同 unlit 内容 HDR=true | 89.853 / 84.762 / 79.569 | 逐像素相同 |

`d3-lit` 采样窗口 96 submitted/completed、0 failed、95 actual presented，96 offscreen captures，与新增无 effects lit 路径一致。零光反例按合同应全黑，通用 benchmark 的“非黑”门因此 NON-PASS；本记录保留该结果，以预先约定的黑色像素 oracle 判定反例，不修改通用门或隐藏失败。上述状态是分进程对照；动态 next-frame 恢复由 GPU fixture 另证，不混写成同一 App 的 live mutation。

HDR 首次 7 秒短跑的 present 统计无效；12 秒、warmup 5 秒复测 valid：326 submitted/completed、0 failed、301 presented/1 stream。初次异常发现既有 `SceneDebugFrameCapture` 在 completion 回调同步转换 16F 并编码 PNG，短窗口受诊断重工作干扰；未证明全部 2–3 GB 峰值来源，不宣称性能完成或提升。后续区分实验与 bounded snapshot ownership 已列 RF05。

原样本隔离回归 `app-originals/report.json`：

| 样本 | benchmark | 实际输出证据及边界 |
|---|---|---|
| 2815826216 | PASS | 18 layers/6 image/14 effects；351 submitted、350 completed、0 failed、349 presented；正常 surface 1→0。仅当次运行回归，不证明所有 effects 或受光画面与官方相同。 |
| 2684431262 | PASS | 17 layers/14 image/25 effects；首帧25 effects返回输出且共享command buffer completed；304 submitted、303 completed、0 failed、302 presented；正常surface 1→0。没有官方HDR golden或EDR设备验收。 |

采样窗口末的 submitted/completed 差 1 是窗口内计数，不能由此推断整个会话最终有未完成 frame；日志另记录正常停止。原样本完整 graph 与受控 direct 路径分别验证，不能用单一路径代验另一路径。

历史复核命令入口：`xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -derivedDataPath <isolated> build`；`script/scene_wallpaper_benchmark.py --app <signed executable> --sample-root <isolated>/samples --matrix <matrix.json> --output-dir <fresh> --duration 12 --performance-warmup 5`。精确参数、矩阵摘要、App identity 在各 report.json。

## 后继

[参考证据实施卡](../../scene/design/reference-evidence-implementation-cards.md) 已覆盖59个唯一条目及当前owner；下一片 RF01 修 shader-default RT identity 的实际消费断点。未开放能力保留各设计的前置与纠正门，不以本片、设计 approved 或两个原样本 PASS 代替全部 Scene 兼容性。
