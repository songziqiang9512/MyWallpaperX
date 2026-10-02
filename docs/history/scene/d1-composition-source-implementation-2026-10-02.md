<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# D1 实际source准入与消费链（2026-10-02）

> **历史证据 — 非现役入口**。当前权威：[D1设计](../../scene/design/composition-render-target-design.md)、[兼容路线](../../scene/scene-compatibility-roadmap.md)、[运行证据](../../scene/semantics/runtime-evidence-current.md)。最终候选与独立验收登记见下文；不以资源正确性证明作者成员语义。

## 目标和边界

现有planner已选择的source必须经过实际target分配、成员写入、graph preparation与采样进入唯一terminal。只修该资源合同，不修改parent/copybackground/passthrough成员语义；后者仍由D1设计待定案段拥有。参考项目只提供[中性合同](d1-composition-neutral-contract-2026-10-02.md)，没有复制其算法、shader或payload。

## 分阶段真实反例

基线为119bbe281f4234676140fa9f76d481f41fa20295；以下日志在/private/tmp/mwx-d1-next/implementation/，各阶段源与App分别冻结，不能互相替代。

1. 原pool冷启动合法compositionGroup key产生composition allocation，却被自身keyMatchesAllocation拒绝。真实Metal texture allocation测试pool-red.log失败8.224s，coldAllocated=false、residentBytes=0；对应准入修正后通过6.125s。此阶段没有GPU command提交，证据上限为真实资源分配。
2. 仅修key的admission.app里，同一个自写dim效果作用于普通image的正控制通过；group仍在utility capture失败并导致blueprint拒绝，未到completion。实际viewport3024×1964，旧pool按普通目标上限缩小后又被现有exact尺寸guard拒绝。该反例是尺寸准入失败，不是错源像素。
3. 分配前使用exact poolLimit、source仍绑定mainTarget的exact.app：完成GPU/terminal与ready/after两帧，实际中心均[0,0,255]，没有应有的自有红色source效果。app-exact.log以蓝通道255违反红色ROI断言失败15.681s；主源蓝+健康绿色邻层可见。根也查看实际after PNG。自有效果仅把输入红通道减半，普通image正控制排除了效果本身未执行。此时才取得后继wrong-source可见反例。

exact.app身份：source manifest SHA256 9230c63ced2387ae021ffcdec22325f9d472f755e1538e4755d4646fa5220445；debug dylib SHA256 54b0a335dcf1d6441d37683510f42e7cc1054f0fe2b1add40332837a98461640。原输入/执行命令/App hash/runtime JSON/PNG位于app-exact/test_group_graph_reads_selected_red_source；不把这些中间失败App当最终验收。

## 终审发现的组内 composition 反例

独立终审发现，现 route 已接受的组 G 内无子层 composition C 会在 preparation 取 G source，但绘制仍使用全局 mainPass；当 C 与 G 在末成员共享 trigger 时还会先执行 G。冻结 source-v2 App 的三个补充场景耗时43.858s：C 在成员中间/最后两个场景的 ready 与 after 中心红值均为128，违反两次自写减半效果应为64的门（2 case、4 subtest FAIL）；蓝背景与绿色邻层仍正常。输入、PNG和App身份在 `implementation/app-childless-red*`。这证明效果没有按现有组归属进入外组消费，不涉及重新定义成员语义。

C 在首位置且后继空组的场景通过；不能把静态首读未初始化风险写成已经复现的 ghost。真实旧红纹理复用后全透明另由 runtime GPU 门证明。修复沿同一 pass owner 同时统一采样前结束/clear、写回目标和同 trigger 内外执行序，不单独改 request 字段。

## 最终实现、身份与验证

### 实现职责

- allocation cache 承认现有 group key/allocation 配对；pool 按实际 viewport 取得 exact source，沿原预算拒绝不可满足的尺寸。
- frame preflight 之前预留实际 source；成员写入、嵌套组与 graph preparation 使用同一纹理，现有编译执行序同时拥有准备与预算优先级，不以 layer 数字 ID 决定资源胜者。
- 既有 submission pin 覆盖 prepare→cancel/submit→completion。相同 key 的旧在飞资源保留计费直到最后一个 pin 释放；reset/resize 不提前释放预算。源首次写入或空组首次采样前透明 clear；同帧续写 load。
- 复用现有 graph、cache、FrameRuntime 与 terminal owner；没有新增 provider/registry/scheduler，没有修改 SourceRoute 的 parent/成员/flag 规则。两个源码形状测试由普通 captured-main 和组 source 的真实行为门接管，未用新文本匹配掩盖原红门。

### 最终候选身份

产品冻结：`implementation/final-source-v5/manifest.json` SHA-256 `5fb69eaf5977783b9ec3f19dd7d35ff4d32ab6cf4503520b5675f4e5c3719750`，包含10个产品文件、3个测试文件及1108项依赖。root重新核对各项hash均相符；最终App为 `/private/tmp/mwx-d1-next/source-v5.app`，Debug构建及strict签名验证通过。App记录中的source manifest SHA为 `59bb0e937d27c789887d9d298c37ed1284e21bb8931dfbe94436b63fe88ea46f`；执行文件SHA `53d80b1f5b3ad5177a077596175e7eaae6a3a8f8827c939d46959adb936180e8`，debug dylib SHA `b627ff2be8d432823a0b813e38151632ab5cc89e60bba856a6e22dbb021178a4`。最终运行测试文件身份与后继仅测试缓存参数变化分别登记，不与早期v2/v3混用。

### 最终验证与独立终审

最终source-v5的15门全部通过（202.205s，无skip）：13项真实App场景、1项真实runtime GPU clear/completion门、1项真实资源CPU门。App涵盖普通image/普通captured-main/isolated组源、主源改色、关闭效果、带效果成员、嵌套、空组、resize、prepare cancel，以及childless composition在成员首/中/末三位置。红值按自有预声明±2门检查128/64/32，同时检查组外主源和健康绿色邻层。每项App输入/执行身份、ready/after PNG、实际完成/终结事件保存在 `implementation/app-source-v5/`；root亦目检middle场景。真实GPU门复用旧红target后读取全透明，并核提交前预算pin和实际command completion后的释放；不把pending多command预算测试冒称GPU并行压力测量。

App实际执行的test SHA为 `f1681a7a9c27e7ec5ca1965c3687607c068de000ea8f8a36a2efaba94824f0d1`。随后仅对新测试的swiftc参数添加临时module-cache-path，未改13个App方法及产品/App；最终整批产品/测试冻结见 `implementation/final-source-v5-tests/manifest.json`，SHA `2a2ba077545fc0b8a1462afebc06f2a696bae81cd7e3e657fa0bd9f1af29ab09`。该参数delta另存 `test-cache-isolation.diff`；新身份的资源CPU/GPU helper与相邻门共55项全部通过（36.188s，无skip）。最终证据清单 `final-evidence.json` 包含240文件，SHA `97f589b6ea060d2d340243f90e7c3532d73894506703d3b5fc3e20b39d7fe5c6`。

v3阶段13个相邻模块共发现119个方法：107实际PASS、1个既有源码形状ERROR，11未执行（本批module的GPU方法及整App class未开启）；后者由最终15门独立运行，不将skip算PASS。既有错误为 `test_scene_resolved_material_runtime_bridge.test_production_frame_is_sealed_before_command_buffer_commit` 查找旧连续源码字符串失败；使用HEAD renderer重跑同方法精确复现，证据 `head-seal-shape.log`。本批没有改该调用或通过修改字符串期待掩盖此既有错误。

v5 Debug build、code-health、scene-defense及精确10产品path design-gate均通过；结构/防御基线没有扩张。独立产品终审ACCEPT，报告位于 `/private/tmp/mwx-d1-next/independent-resource-review.md`，审查者未实施本批产品；终审发现及修复前后证据见上一节。文档治理25门通过；提交前核完整owned清单，未触碰三份受保护Scene权威文档或并行layout排序改动。

空组首个 userproperty 实验实际返回 accepted=false，不能据残留红色推断 clear 失败。它命中现有带 parent 的热更新准入边界；普通产品 client 会按现有 Events 路径重启，debug runner 直调没有该行为。最终 fixture 改用已支持 SceneScript 可见性并断言实际事件，未扩张热更新能力或静默忽略拒绝。

### 未验证边界与后继

不宣称 parent=隔离成员、copybackground/passthrough 完整合同、任意 composition 或官方像素 parity；不宣称全 corpus、性能、发布验收或真实 GPU device fault 覆盖。本批新画面门为自写输入。后继按兼容路线推进 D3 normal 输入与既有受光 producer；D1 成员/flag 继续用中性参考证据与必要单变量黑盒定案，不因这一资源修复把整项标记完成。
