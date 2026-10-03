<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF05 诊断截图与隔离退出实施证据（2026-10-02）

> **历史证据 — 非现役入口**。当前权威：[兼容路线](../roadmap/scene-compatibility-roadmap.md)、[能力台账](../capabilities/coverage-ledger.md)、[运行证据](../capabilities/runtime-evidence-current.md)。受保护能力/运行总表及 engine-refactor-program 本批未改。

## 职责与边界

基线为主目录 `codex/engine-refactor-program`、HEAD `85415320` 和 D2/D3、RF01 已冻结实现。依据[诊断生命周期设计](../roadmap/batch2/debug-frame-capture-lifecycle-design.md)，仅改变 DEBUG 截图请求、readback 提交时点、导出及现役 Session/隔离 Scene 退出等待。没有第二 allocator、registry、clock、compositor；不改变作者视觉算法。

请求按每 capture 两个 required 和一个 latest periodic 有界；全进程一条串行 utility 导出队列，两个工作槽覆盖 GPU、排队及 CPU 导出，总 buffer 字节受现役 resident 总额四分之一约束。真实资源仍由 makeSceneBuffer 的原 lease 记账。16F 转换在独占 readback buffer 原地进行，CGDataProvider 在 buffer 有效期及 autoreleasepool 内同步完成 PNG，未引入可控全帧 CPU 副本；库内部临时内存不冒称全部计账。

readback 移到既有 PreparedFrame.submit，prepare/cancel 不吞请求。outstanding 在 commit 前登记，完成回调只交独立 buffer 与值元数据，不带 drawable/texture/view；PNG 写入或失败后终结一次。close 拒绝新请求并明确终结 pending，等待 in-flight 导出。Session 同时等待现役 GPU barrier、capture terminal 和退役 surface drain；Runner 关闭后不再启动迟到 launch/switch/relaunch/pause。

## 修前反例与独立审查

证据 `/private/tmp/mwx-rf05/`：

- `cancel-before.log`：旧 Capture 在 PreparedFrame.cancel 前消费请求，下一真实帧未产出文件。
- `pause-before.log`：关闭后已排队 pause/resume 仍写 Host；修后 `runner-closing.log` 通过。
- `retirement-before.log`：先退役 surface 的失败回调晚于整 Session barrier 到达，旧路径错误报告 drain 成功；修后 `retirement-final.log` 通过。该反例使用 ObjC MTLQueue/Buffer forwarding proxy 控制平台回调，包括 barrier 创建 nil、late error；没有制造真实 GPU 故障。
- Capture 真实 Metal fixture 阻塞 CPU 导出而本帧/后帧 completion 已完成；原 texture 覆写后 PNG 保持原 snapshot；三 capture 竞争两个槽、supersede/拒绝/teardown、全局预算和写失败、1024级16位梯度与 alpha、GPU completed 但回调 handoff 延迟等反例均通过。
- shutdown fixture 编译真实 Session/Shutdown、Runner ownership/switch/relaunch/pause 代码，边界用最小 stub 与真实 Metal；v2 两个模块通过。真实 GPU error、encoder nil 与整数溢出未逐一注入，仅静态核对出口，不能列作运行通过。

独立终审 v2 接受后，完整签名 App 补查又揭示 AppKit terminateLater 模态循环中的主队列重入等待。`/private/tmp/mwx-rf05-app/after/report.json` 保留 timeout/-15，尽管 PNG 与 gpuDrained=true 已出现；因此 v2 不能判完整验收。v3 使用 Runner 既有终态：已完成直接 terminateNow，真正 pending 经能服务 modal mode 的 DEBUG 主线程交付后只 reply 一次，Release 原派送保持。所有自有延迟 terminate 归现有方法，并在 closing 后抑制；Performance 非法 FPS 的漏口也闭合。

`appkit-before.log` 记录真实 NSApplication.run 中已完成/pending 两路超时；`appkit-invalid-profile-before.log` 记录旧非法 FPS 延迟直接 terminate 在等待期间触发提前强退（-5，未完成 owned drain）。修后 `final-v3.log` 三组测试通过，包含8种真实 AppKit 场景：已完成、pending、失败终态、自有重复请求、阻塞导出、退役导出、自有关闭与外部退出重叠、非法 FPS；检查一次 reply/willTerminate，PNG、stopped、退出的顺序。AppKit fixture 编译提取的真实生产方法及真实 Metal/NSApplication，宿主边界仍是 fixture，由完整 App 另验。

重叠场景初次失败另见 `appkit-overlap-inspect.log`：测试自己的放行也排在被嵌套的 RunLoop block，尚不能证明产品交付缺陷。改为 delegate 实际决定 terminateLater 后通知独立后台放行，原产品交付链通过，见 `appkit-independent-release-before.log`；未为测试问题增加产品 timer/selector。直接外部第二次 NSApp.terminate 在本机可绕 delegate 强退，实证见 `appkit-repeat-inspect.log`；本片防住自有产生者，不扩全 App 退出 owner，不承诺拦截框架强退。

## 初次 App 对照的证据上限

`/private/tmp/mwx-rf05-app/before/report.json` 使用 RF01 frozen.app；相同隔离自有 HDR 输入、7秒/预热3.75秒，旧版缺少有效 presentation stream。v2 新版 `after/report.json` 有103 submitted/completed、0 failed、102 presented，但进程超时，仍 NON-PASS。ready/after 两图对比均为3024×1964 RGBA逐字节相等，见 short-window-comparison.json。单次短窗口不是性能闭合，不能用局部统计掩盖退出失败。

## 最终冻结与完整 App

v3 独立终审接受，`/private/tmp/mwx-rf05/frozen-files-v3.json` 的13产品/2测试路径逐一匹配；设计最终 SHA `349035246cb4c7540e39e118cb69b3c9fc1b4c5fd9a9a7c9a68e560d15a1dbb4`。同目录 code-health-v3、defense-v3、design-gate-v3 日志通过，Swift 1042文件/0错误；237条既有 warning 未冒称清零。

`/private/tmp/mwx-rf05-app/build-v3.log` BUILD SUCCEEDED；52个累计受改产品文件的源码 SHA 在 build-v3-source-identity.json，实际 binary/dylib/metallib 身份在 build-v3-payload-identity.json。App 2.10.0(280)，team H9QWU9XN8R，CDHash `0bafd1a4f0d3135d487587617f2f20ed6ea12a8b`；launcher SHA `57b749c1352869fda3f5d9d98a6341018e3f36ecaae98464385878ff8198a869`，Debug dylib SHA `7495797f00d038465dada9bdd132ba9b422f4dc412b5dabc8ca208af662a6641`。

相同7秒/预热3.75秒的完整 App 复跑 `after-v3/report.json` PASS：exit0、无timeout，95 submitted/completed、0 failed、94 presented；03:53:04.909 ready、03:53:07.065 after PNG，随后03:53:08.779 stopped/gpuDrained=true。两图与旧版本逐字节一致，见 final-app-oracles.json；签名执行前后均有效。单次短窗口没有构成长期性能闭合。

`test_scene_frame_presentation_integration` 使用同一 frozen-v3.app，五项完整 App 门全部通过（46.149秒）：一屏缺drawable而peer继续并恢复、post-prepare拒绝不重播shared heap、所有输出缺失后继续最新状态、候选首GPU完成后才promote、候选拒绝保留旧输出。证据在同目录 frame-integration.log 与各场景 frame-integration/，包含真实completion、动态状态和terminal compositor PNG。这是受控多surface，不等于物理多屏验收。未暂存、提交或推送。

## 未验证边界

旧 CPU wiring 26条中24通过、2条 HEAD 已有源码形状失败：test_scene_daemon_client_wiring 仍期待 security-scope/workspace observer 代码位于 Host，实际 owner 已是 Session；未修改这些预期来凑绿。产品/Web/daemon 原退出分支不扩大。外部 TERM/KILL 不保证 graceful drain。物理多屏、持续时长资源/RSS、发布签名与官方 parity 仍未完成。
