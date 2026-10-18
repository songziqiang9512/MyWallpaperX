<!-- document-role: historical-evidence -->

# 链接产物复用与启动测量（2026-10-18）

> **历史证据 — 非现役入口**

当前选序归[性能卡](../roadmap/performance-convergence-card.md)，准备边界归[启动合同](../architecture/scene-launch-responsiveness-contract.md)。本批按“先测量、有净收益才保留”筛选 Scene 冷启动与 Web 启动；只保留 Scene 编译流程简化，不新增缓存、线程、预热容量或运行时 owner。

## 当前链路与局部改动

Scene 普通选择经 Steam 产品入口、切换事务、Scene client/daemon，完成模型与材质准备、capability/Program 编译、资源与首 surface 准备、激活及匹配请求的 first-present。冷启动中，3287715210 的材质准备约 1.8–2.1s；这一段没有改动，也不重开性能卡已停止的声明扫描/variant 缓存方案。

`SceneGenericShaderCompiler.compileStages` 原先先运行 glslang 成对链接；该命令已经在工作目录生成 `vert.spv`、`frag.spv`，随后又分别编译两个 stage。现在直接将链接输出交给原 SPIRV-Cross MSL/反射链：每个普通 source pair 的编译/转换子进程从 7 次减到 5 次，另有的两次工具版本探测保留。签名解析、成对链接、超时/诊断/驻留预算、输出文件校验、ArtifactBuilder 与原子发布保留。

循环保护重试仍走同一 `compileStages`。每次链接前删除该工作目录的两份旧 SPIR-V，缺失、空文件、符号链接、超预算输出不能当作成功产物；第二次输出不全时不能复用第一次结果。失败仍止于当前请求，不扩大 shader 准入，也不修改 request key 或 cache schema。

## 五对同安装路径测量

基础提交 `6cfa807e86579a81d0c0fe17bb388c54209a2fdb`，只叠加本批编译器改动；排除并行工作区修改。机器 Mac16,1 / Apple M4 / 16 GiB / macOS 27.0.1。两版均为 Developer ID 签名的 `Debug + -O + wholemodule`，这是优化诊断配置，不是普通 Debug 或正式 Release。

同一机器、样本副本与产品入口；版本顺序 B/C、C/B、B/C、C/B、B/C。每臂冷启动使用全新 HOME、defaults suite 和应用 shader cache，随后另起进程复用这一 cache 测暖启动。OS、文件系统和 Metal 驱动缓存没有清空；这里的“冷”仅指应用 shader cache 冷。

主边界是产品选择 `load-dispatched` 至同请求 first-present，使用既有日志；没有 profiler、截图开关或完整执行观测。两份 App 在同一个绝对 bundle 路径交替运行，移动前相关进程已退出，每次核对可执行文件 SHA，结束后恢复原路径并验签、验字节。

| 配对 | B 冷 ms | C 冷 ms | B 暖 ms | C 暖 ms |
|---|---:|---:|---:|---:|
| 1 | 5005 | 4330 | 1383 | 1340 |
| 2 | 4948 | 4331 | 1321 | 1276 |
| 3 | 4869 | 4286 | 1353 | 1558 |
| 4 | 4805 | 4382 | 1368 | 1352 |
| 5 | 4804 | 4346 | 1413 | 1318 |

冷启动中位 4869→4331ms，少 538ms（两臂中位数之比降 11.05%）；配对降幅中位 11.97%，B 最大相对偏差 2.79%，通过预登记 ≥10%、超过两倍基线噪声的局部启动继续门。暖启动中位 1368→1340ms，没有确定的暖启动优化结论；C 第三轮 1558ms 保留，五次不用于声称尾部、稳态或能耗无回退。

五对各生成 11 份最终 Program、91 份应用缓存 JSON；两版最终 Program 集合及每份内容逐字节一致。独立的 11 组真实 normalized source pair 对照中，链接输出与原单 stage 重编译的 SPIR-V、MSL、反射均一致；省下的累计 helper 工作约 1117ms，不与重叠 worker 阶段相加，也不冒充 App wall 收益。

**测量反例保留。** 最初不同临时 App 路径的五对结果，冷启动配对中位只降 3.58%，暖启动反而慢约 17.14%，不能据此保留候选。进一步空 Web/Scene daemon 试验将额外约 0.15s 定位到 shader 工作之前的进程握手；只交换 App 路径、保持原字节后，这一差异消失，回到原组合又重现。因此追加上面的同安装路径比较，避免将临时启动环境差异记为 shader 回退或收益。未确定 OS 内部原因，也没有在产品中加入移动 App、绕过校验或改变进程模型的处理。初次测量、hello 及路径反例一并保留，不丢弃不利结果。

## Web：未取得代码修改资格

Web 选择现已重叠空 daemon 启动与项目分析，并可采用已有空宿主。之后依次完成网页加载、原生快照准备、媒体暂停 ACK、切换激活、媒体恢复 ACK 与 WindowServer 可见证据；不删除这些正确性交接条件。

同配置普通 Steam 入口七次 CWAV（1509243786）基线全部完成且有真实音乐输入：首次约 1763ms；后续冷宿主 892/933/912ms，已有预热宿主 488/552/493ms。既有进程阶段计时约 0.4s，其余约 0.45s；首次额外成本单列，不能拿首次与已暖候选相减。 候选包的额外真实验证中，CWAV 七次提交均完成且观察到音乐；后续冷宿主 930/999/991ms、预热 540/542/576ms。首次 3669ms 的日志明确先提交了 Video，混入启动恢复与跨引擎退场，不能与初次基线直接比较或记成 Web 纯冷启动。独立 Raindrops（3700131876）七次也均提交，后续冷宿主 991/934/931ms、预热 517/560/559ms；该作品没有请求频谱，runner 的音乐条件为 false、总 passed=false，不能写成音频门通过或误报启动失败。两组都只作不变 Web 链路的有界运行观察，不认领性能收益。

筛选了“新建未暂停的 WKWebView 时省略初始原生 resume”候选，保持导航失效、`afterScreenUpdates` 快照和 suspend/activate ACK。原生 WKWebView + 产品 `WebMediaPlaybackGate` 的生成 canvas 窗口试验，资格对之外五对就绪中位 206.29→205.38ms，仅 0.91ms，低于波动；初始调用约 0–5ms，基本与导航重叠。这个试验不是工坊产品入口收益或兼容验收。候选不进入产品，Web 源码保持原样；不为缩短表面计时增加预热进程、隐藏网页、缓存或削弱可见交接。

## 正确性与边界

- 最近门 12/12：4 项编译编排正反例，3 项真实签名编译器 → Program/PassEncoder/Metal 行为测试，5 项 helper 成功/非零退出、signal、超时与诊断/驻留预算测试。真实 GPU 测试产生 36 份 artifact，覆盖坐标、纹理槽、顶点/片元采样及应拒绝反例；编排替身只用于注入缺失输出、旧输出和链接失败，不冒充真实编译器。
- 当前候选在 3287715210 与未参与修复的 2067939514 上独立运行，分别实际产生 11/14 份通用 Program，并取得 ready/after 真实窗口图；已查看后续画面中的人物/时钟/柱形与山景/环形内容。这是直接 Host 有界画面资格，产品入口 first-present 由上面的五对测量独立覆盖，不称全样本或官方等价。
- 普通 Debug（默认优化设置、禁签名）在隔离固定源码上构建成功，108.71s、输入无漂移；code-health、Scene defense、依赖边界、设计及产物预算通过，本批文档链接通过。全库形状断言门仍命中与基础提交字节一致的 `test_scene_daemon_client_wiring.py` 既有项；文档健康门另有三个 Web 文档旧审阅日期，导出树全库链接检查还缺本机忽略证据及旧 fragment，不将这些写成本批 PASS。没有改写其他 owner 或放宽基线。优化测量 App 与普通 Debug 构建身份分开。未验正式 Release、最低设备、多屏、长稳、全局 CPU/GPU/内存峰值及功耗；不声称整个启动专项结束。

原始测量、App 身份、失败反例、必要截图与测试日志在 `/private/tmp/mwx-startup-gosp8uz3/final/` 限量保留（约 23.5MB，含可重放命令和本批精确 patch）。标准证据缓存完成安全到期清理后仍超总预算，正式 promotion 被拒绝；没有提高预算或删除未知/受保护材料。可重建运行 App、HOME、shader cache、临时样本和探针按产物规则清理。同任务只复用 `/private/tmp/mwx-web-process-93lokqq7/build-cache/dc9ce36d13b722cbbbb4aec6` 一份构建缓存及对应固定源码，供续轮验证，重新使用前复核必要性。
