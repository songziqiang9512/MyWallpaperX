# Scene authored sample debug ledger

> 这是一份可复查的运行首断点档案，不是视觉通过矩阵。样本根只读，档案只记录 authored corpus 的 identity、运行状态和可定位证据；最终“正确显示和播放”仍须逐样本人工/ROI 验收。

## 2026-09-08 current corpus probe

权威样本根是 `/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Scene`。本次静态 census 发现 **159** 个 numeric sample，`159/159` 的 project、PKGV 和入口 JSON 可解析；sample-id manifest SHA-256 为 `dce37464a0d15c860e3bd8566784f227419d4b2f5e9f4e7f053e38139d760776`。对应的静态快照是 [`scene_capability_census_snapshot.json`](../../../script/scene_capability_census_snapshot.json)（SHA-256 `0346d55c384f90d4931984098e2fd5f01bba18849f952beac9049153747b8351`），摘要清单见[`全样本能力分类与修复台账`](scene-corpus-capability-inventory.md)。

四个隔离分片使用同一签名 Developer ID Debug executable（bundle `com.songziqiang.MyWallpaperX`，version `2.0.9 (277)`，Team `H9QWU9XN8R`，CDHash `610ab437185c4104392b30227afbea3744129ea0`，executable SHA-256 `10951960b67fd3a635f96846886d0829fb3aa6de68c5c771913cc0109d22e247`）。每个样本从只读根复制到独立 runtime root，运行时长 7 秒；该 probe 使用 identity-only matrix，因此没有把历史视觉期待误当成成功条件。四份 report 的 SHA-256 分别为：

| 分片 | 样本数 | report SHA-256 |
|---|---:|---|
| `mwx-v4-authored-sample-audit-part-1-of-4` | 40 | `0737c581457c452d5475b6579bffffe7103cf7820eacfc3dd02f29a8a2604019` |
| `mwx-v4-authored-sample-audit-part-2-of-4` | 40 | `5d31482e6f3e6d39ad7e9a3711fa5a343074425c7a943f2e99c6708939b076d2` |
| `mwx-v4-authored-sample-audit-part-3-of-4` | 40 | `f8fb14de3ae911c55e67f220a90d77b237ef0ba2c4e96ea1b053c0ea28c65075` |
| `mwx-v4-authored-sample-audit-part-4-of-4` | 39 | `e10934d7e2d116d66a7b6d9a70bd28c8d116349a87ca05101ea8a69cc3831751` |

机器可查询的合并档案是 [`scene_sample_debug_archive.json`](../../../script/scene_sample_debug_archive.json)（SHA-256 `36e8d7b1662414c73972742e4fb91e4afd14c48d1fed57f4af5dacf26b19268a`）。它覆盖 `159/159` 个样本，状态为 `117 structural-chain-complete-visual-review`、`37 degraded-runtime`、`5 blocked`。这些状态只描述运行安全和首断点，`structural-chain-complete-visual-review` 仍要求 authored preview/ROI 与 next-frame 视觉复核，不能写成“正确显示”。首断点计数为：

- `effect-admission:admitted-fallback` 12；`effect-admission:unified-capability-unavailable` 9。
- `resource-load:particle-layer-load-incomplete` 9；`resource-load:base-image-texture-load-incomplete` 3。
- `graph-execution:graph-execution-missing` 2。
- `script-execution:scene-script-exception-range-error` 3；`script-execution:scene-script-exception-type-error` 2。
- 另有 1 个 dynamic-uniform binding passthrough 和 1 个 material-pass preparation/library compilation passthrough。

五个需要先回到公共 owner 的 blocked 样本是 `2824109832`（effect admission 后仍有未认领 visible effect）、`3448845950`（GraphExecutor 缺失多层且无 terminal/next-frame）、`3470948192`（terminal flat-preview divergence）、`3775355045` 和 `3775373546`（layer 22 的 GraphExecutor execution missing）。`3509243656`、`3610154602`、`3612199597` 等真实样本还记录了 SceneScript typed exception；这说明“脚本路径更好”不能由全量 probe 推断。

本档案的生成器是 [`scene_sample_debug_archive.py`](../../../script/scene_sample_debug_archive.py)，测试为 [`test_scene_sample_debug_archive.py`](../../../script/tests/test_scene_sample_debug_archive.py)。它只合并样本静态事实与现有 report/diagnostic first breakpoint，不保存样本副本、截图或作者 payload；`/private/tmp` report 路径是 provenance，缓存消失后不能用本页代替重新运行。

## 手动启动与脚本运行不是同一实验

用户的 `xcodebuild ... .codex/DerivedData && open -n .../MyWallpaperX.app` 与上述 probe 的可见结果不能直接比较，至少有三项已由当前证据确认的输入差异：

1. **可执行文件身份不同。** 当前 `.codex/DerivedData` app 的 CDHash 是 `2d84e8322db54101cc519371a65b8ebf8da8493f`、executable SHA-256 是 `cae686f4523ba1c8244270995479db04f246bd349c581ee4147c5ec957f749e0`（2026-09-08 03:39 +0800 重新核对）；probe app 的 CDHash/SHA-256 是上面的 `610ab...`/`109519...`。bundle identifier/team/version 相同仍不能把两个 signed app 当成同一可复现 artifact。对两者去除签名后的主 executable 完全相同，Debug dylib 的 `__TEXT` 与 Swift metadata 代码段也相同；因此身份差异是比较前提，却尚无证据把它单独认定为日期或文字缺失的代码根因。
2. **有效输入不同。** probe 以每个样本的隔离副本和独立 `HOME` 启动，identity-only matrix 不带用户持久化 Scene property overrides；普通 App 从 Workshop record path 启动并读取 `com.songziqiang.MyWallpaperX` 的已保存 overrides（例如 `3396722575` 的 `newproperty3` 长文本），以及用户属性纹理 URL。值、路径、缓存和资源 ready 状态因此可能不同。
3. **启动/窗口/策略不同。** probe 传入 `--mwx-debug-scene-root`、evidence directory 和 duration，走同步 `SceneDesktopWallpaperHost.launch`，强制 resume 播放并使用 DEBUG evidence window；普通 App 走 UI/desktop request 的异步路径，使用实际 display/window 与持久化 pause policy。两条路径最终汇合现役 host、Program/VM、Metal encode 和唯一 compositor，但窗口尺寸和有效 property snapshot 会影响首帧布局与文字栅格。

已用两个 app 对同一 `3396722575`、同一只读样本副本和同一 identity-only matrix 做 A/B：两边都是 `61` layers、`30` image layers、`62` effects、`textScriptDiagnosticCount=0`、ready/after 非黑、`1/1 PASS`；当前 app ready 约 `16.415 s`，probe app 约 `17.067 s`，差异落在启动和帧采样抖动。这个 A/B 没有复现日期或文字差异，说明“脚本一定更好”尚未成立，仍需把普通 Workshop record 的 overrides、纹理 bookmark 和实际 display extent 纳入同一组实验。

当前 frame code 的 debug 与 production 都从同一 `Date()` 形成 `wallDate`；本次 probe 没有设置 debug wall-date override。这个结论可由 [`SceneDesktopWallpaperHost+FrameDriver.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+FrameDriver.swift)、[`DebugScenePlaybackRunner.swift`](../../../MyWallpaperX/App/DebugScenePlaybackRunner.swift) 和 [`SteamWorkshopSceneService+SceneProperties.swift`](../../../MyWallpaperX/Modules/SteamWorkshop/Scene/SteamWorkshopSceneService+SceneProperties.swift) 的当前实现复核。因此“手动启动拿不到时间/日期”目前不能归因为 debug clock 被注入。应先用**同一个 executable、同一个样本副本、同一个 effective property snapshot、同一个 display extent**各运行一次，并比较 SceneScript exception、text publication generation、terminal compositor 与 next-frame；只有这组 A/B 能把日期缺失区分为输入/路径差异、typed script contract 失败或文字 provider/layout 问题。

## 结论上限和下一步

本次 probe 证明 159 个样本均有可复查的运行条目和 first-breakpoint/lifecycle 证据；它没有证明任一样本的视觉等价、时间文字正确、稳定帧性能或官方 parity。当前最高收益的 V4 工作是先固定同一 build identity/effective input 做手动与 probe A/B，再修复共享 GraphExecutor layer-22 缺失与 SceneScript date/text typed exception 的首断点，并为每个修复样本补 authored ROI、GPU completion、publication、terminal compositor 和 next-frame 证据。没有必要因这份 triage 档案启动 Ghidra；若上述 A/B 仍无法区分首断点，再按官方行为研究工作流取证。
