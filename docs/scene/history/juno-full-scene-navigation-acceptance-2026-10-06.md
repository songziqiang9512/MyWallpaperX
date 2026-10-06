<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。现役顺序见[断点队列](../roadmap/scene-open-breakpoint-queue.md)太阳系条目；JUNO 隔离夹具修复见[默认 albedo 记录](static-model-default-albedo-implementation-2026-10-06.md)，光照合同见[能量合同记录](model-light-energy-contract-implementation-2026-10-06.md)。

# JUNO 原完整场景导航验收（2026-10-06）

起点 `8119cfee`（光照修复后）。交接 S1 卡要求：原完整场景内进入 JUNO，验证不缺主体且其他部件无回退。

## 导航方法与作者机制（诊断事实）

- 调试回放宿主无键盘输入；标签双击每运行仅一次。为在单运行内完成多跳导航，用隔离测试副本（原 pkg 全字节 + 仅 Main 脚本两处测试钩子）驱动**作者自己的** `startViewTransition` 链。
- 机制发现：`initialFocus` 脚本属性只设 `currentFocus`，不驱动相机（两轮 initialFocus=5 运行均停留总览）；相机实际由 `startViewTransition` 过渡/稳态分支放置。航天器聚焦 id 形如 `sc_5.01`（JUNO=`p5c1`→`'5.01'`），且 `canSwitch` 要求**先聚焦母行星**（parentType 'planet' 需 effectiveFocus===parentFocusId）——裸 `'5.01'` 不满足前缀判定、按数字体处理致 bodyStates 缺失回退总览中心（实测确认）。这与作者交互设计一致：先到木星，再从木星进入其下探测器。
- 生效变体 `9000000006`：帧 90 `startViewTransition('p5')`（木星），帧 420 `startViewTransition('sc_5.01')`（JUNO）。

## 验收观察（dylib `ca60b5de…41bd`，含光照修复）

- **木星段**：过渡抵达木星近景，盘面约 25-30% 画面、半明半暗弦月照明，受光面棕/米色云带可辨、无过曝；「木卫一」标签与实心小天体可见；右侧面板正确显示「行星： 木星」；光照合同（k=0.30）下无白淹。
- **JUNO 段**：第二跳后进入深空探测器稳态。探测器**主体完整可辨认**：多面体箱身（背光剪影+棱线高光）、顶部短杆碟形天线盘（最易辨认部件）、**三条旋转对称太阳翼**（与真实朱诺构型一致，走向 7-8 点/1-2 点/5 点钟方向）、连接桁架可见；无大块缺失或碎片化。底部「朱诺号」标签在位；背景密星点、无木星盘面（近景取景）。
- 其他部件无回退：行星标签、卫星标签、探测器标签、右侧信息面板（正确切换天体名）、媒体面板均正常。

## 边界

双击标签进入 JUNO 的物理交互路径未复跑（机制已在水星双击批证明，本次以作者过渡链等效驱动）；布局对照（媒体面板默认 1.5 重叠）仍无官方对照未决；变体仅存隔离 Workshop（9000000003-9000000006，原 pkg 哈希与变体哈希入 manifest），真实创意工坊只读未改。一次 110s 运行曾被外层超时 SIGTERM 截断（帧循环慢），非应用崩溃，后续运行正常退出。

## 证据

`/private/tmp/mwx-mercury-20261006/juno-acceptance-20261006.zip`：木星过渡末帧、JUNO 稳态末帧、两运行 command/summary、变体 pkg 哈希 manifest。运行现场保留于 `/private/tmp/mwx-solar-layout-20261006/{jupiter-transition,juno-twohop}` 至清理。
