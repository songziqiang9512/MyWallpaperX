<!-- document-role: historical-evidence -->

# 源材质输出域与采样输入分离（2026-10-15）

> **历史证据 — 非现役入口**。合同归[源输出域设计](../architecture/runtime-architecture.md#源输出域与采样输入分离)，余项归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。本片没有性能、全样本或官方 parity 结论。

## 通用修复与职责

合法常量片段无需读取 slot 0，却被旧源准备的“每个 variant 必有 sampler0/purpose”拒绝。现 `PreparedSourceMaterial.OutputDomain` 将实际输入与输出几何分开：全 variant 采样 slot 0 保留原 typed 资产物理/padding 域；全不采样 slot 0 借固定 prototype 的完整 base-image Candidate 的 physical/mapped/UV/sampling。真实输入仍由原 schema、finalizer 和 encoder 负责，不伪造 sampler、颜色用途或原始 Candidate。输出 content/purpose 由实际编码 pass 推导，沿原 pool、pin、submission、layer-source atom、后置 graph 与 compositor 发布。

Catalog 保留既有 unconditional seed 的已知用途资源预载，另存实际 reachable 槽，仅对后者报告用途错误；不能为删死纹理破坏 bootstrap 固定点。分析内存缓存和持久 tier 同时携此事实，schema4退出为安全 miss，schema5替代。无用 seed/default 资源消除不属本片收益。

准备方法按既有职责从 DeviceResources 移入同类型 extension，退出单一强制 sourceIdentity。模型 alias 的 trim/反斜杠/大小写合同迁到共享资源值 `SceneModelResourceIdentity`，Rendering 不再访问 Compilation 内部 Catalog；依赖门回到50条既有todo，没有扩大公开编译类型或放宽基线。

## 同输入真实前后

本批自有800×400三卡片，白色底图几何、literal-blue、用途未证明的active采样和builtin绿色。首轮fixture错误使用VERSION/translucent，未到目标 owner，不计修前；修正版移除custom VERSION并用已准入normal state，未改产品。修前两个custom均编译但在源域准备拒绝，三ROI为白/白/绿。

最终Debug App executable SHA `2ad143ce10b5698db5f4e7fc805f97d9b64a76ba8bfabb58ba68c4b5518dac41`，实际产品代码debug.dylib SHA `3eee39d3c6fdbd27701856c81dabed66f8d5fe2db9f83994d141a51575e000e3`，CDHash `607052aa84c20cca6ad6d6be0743f47e6b52e755`。同输入修后literal实际prepared并逐帧encoded，ready/after/三张periodic的固定ROI均为蓝 `[0,0,255]`；用途未知的真实active采样仍白并拒绝，builtin始终绿 `[0,255,0]`。PID4566 exit0、App/dylib drift=[]、GPU排空；已实际打开检查Metal PNG，不以route命中代替画面。来源与输出保留在 `.artifacts/tmp/source-material-entry-20261015/corrected/`。

## 变体、相邻反例与真实回归

同最终App一次运行10层自有变体，运行前固定期望与ROI：无sampler声明、typed-dead albedo、变量/资源改名与等价literal均蓝；只有slot1 active的albedo为品红，typed-active slot0为青；原untyped active仍白并拒绝。material alpha=.5且layer alpha=1/.5的两卡均为[0,0,128]，保持既有style中和、没有二次Alpha；同源后接自有passthrough effect仍蓝，健康builtin为绿。五张Metal PNG的50个ROI全部符合，已实际打开检查；8个positive custom逐帧encode，后effect另有exact-key encoded-output、compositorConsumed=true及GPU completed事实。PID5475 exit0、App/dylib/input drift=[]并GPU排空，证据归 `variants/`。

未参与本批修法的真实833227004原包与project文件仅复制到隔离目录，字节未改、原件前后SHA无漂移。同最终App源1沿原2048²资产物理域prepared并逐帧encoded，实际PNG可见完整彩色流动画面；ready/after有5405965/5939136像素差值大于2，只作为观测到动态，不作同步parity。PID5848 exit0、App drift=[]、GPU排空，收据与图归 `heldout/`。两次现有benchmark选择器因矩阵未收此ID在启动前拒绝，随后复用显式native正确性runner；没有把预条件拒绝算成产品失败或benchmark PASS。

## 验证边界与产物

完整生产准备方法以受控compiler/encoder边界验证15组variant数据，13项门通过（含原10项base-image行为）：全无slot0、只有其他active槽、相同purpose；用途未知/冲突、混合active/inactive、空/不完整envelope、schema/precompile/plan/warmup失败。此门不冒充实际shader编译或GPU。原隐藏消费者门11项通过；持久cache实际cold/warm、多个tier与损坏/失效安全miss门通过。Debug build、代码健康/布局/设计/依赖/防御门通过；GPT-6.1-Sol Xhigh独立只读审查ACCEPT，无剩余明确P1/P2；核对源码冻结、same-input实际收据及UV/purpose/pin/epoch/coldwarm owner边界。变体与heldout由运行lane验收，独审未自行运行App，不冒充独立故障注入。

无base-image的纯程序源、混合variant域、更广provider、多pass、perspective、跨surface及HDR本片未新增验收；无base且带effect须解决原preflight与源晚绑定，不能跳effect或造白纹理。外部style中和沿既有官方有界合同，本片不重新定义；GPU失败/取消未注入，不把静态owner复用当作新故障测试。

保留最小输入、最终PNG/日志、App及源码身份和失败资格收据；隔离HOME/TMP、样本副本与缓存按运行退出清理。默认证据cache已达总预算时保留本任务根的有界结果，不提高预算或删未知材料。连续迭代仅复用 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`，不复制第二份长期App。
