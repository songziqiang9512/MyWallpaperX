<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF05 未支持 optional/named 组合的局部失败（2026-10-02）

> **历史证据 — 非现役入口**。当前权威：[兼容路线](../../scene/scene-compatibility-roadmap.md)、[能力台账](../../scene/semantics/coverage-ledger.md)、[运行证据](../../scene/semantics/runtime-evidence-current.md)。后两份并行权威未改；本记录只保存本批冻结事实。

## 结果与职责

基线 `5f603403`。真实作者解析保留 material named、instance named、system userTexture 三候选，但既有 mixed-provider 只证明两候选；未支持组合仍进入帧准备，optional 不可用时又无 named 依赖 owner，导致全场首帧反复拒绝。

[设计](../../scene/design/optional-named-source-failure-design.md)选择三个现役职责：`SceneResolvedMaterialExecutionCapability+Stages` 在 variant、active demand、invariant 后对活跃且未被 graph 覆盖的未证明组合产生可定位的 launch rejection；`+ProgramFirstStages` 与 `SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough` 复用现有无 history、无 clear 的窄拓扑证明，将安全 effect 留在入口颜色。候选顺序、IR、用途、exact-two profile 均未扩大；不增加 registry、matcher/helper 家族或每帧分析。

## 冻结身份与实际输出

本机证据根 `/private/tmp/mwx-optional-failsoft/`。旧 App 运行新反例门失败（7.785s，`app-red.log`），`phase=launch-failed`/首帧 timeout；同一自写 package 为2641字节，SHA256 `905a211c779383c75961e471d1f5495ab0b5e87263398218cb76af05e7c98274`。修前后所有作者输入 hash 相等。

新 `frozen-v1.app` 的 CDHash 为 `5153e1e1de46bf60b7f814d6a5fc66a7d94e9db4`；实际 Debug dylib SHA256 `2ceafe6e927e3d28555353cccec004623d55b48aeb1b0d1741658a824631d370`、metallib `f9146b9b0990f669db61deb207ab797c170bbc7393948447fbeb621519676542`。三个产品文件在 build-source 与冻结 diff 一致，`payload-v1.json`保存2561文件 hash，strict/deep 签名通过。

两项真实 App 门通过（46.506s）：三候选 consumer 在 ready/after 保留白色入口，中心通道255，绿色邻层175个采样点，蓝色来源不贡献，named capture/binding为0；exact-two 对照仍为蓝色中心并有实际 named capture/binding。每场 frame0/1/2 同 surface GPU completion，publication、terminal consumption、next-frame及退出 drain 有实际事件；三候选 materials=0/rejected=1，不能把白色结果称为 named fallback 已执行。

## 行为门与终审

最终 `final-v1/manifest.json` SHA256 为 `e5d32c7653c941493d0f4db389b6b88edc60d1f41b9b09c96f78d580bfbdb05c`，绑定三个产品、两个测试、构建输入及 App payload。独立只读终审重算这些身份及448项 harness dependency；App 2561个 payload 无差异，接受本有界修复。

- 实际作者解析及 stage 行为两门通过（201.253s），13项断言覆盖：三候选局部失败、零 materials/依赖申领、exact-two继续执行、不同 provider/secondary不归一化、两个相邻有效 effect、inactive slot、terminal asset、authoritative graph override，以及 history 与真实 clearFunctions 拒绝。clear 另有可执行正控制。
- 边界门曾失败：graph override 测试只改 graphRole、未随真实 producer 追加 `.graph` 候选，触发模板身份错误；terminal asset 测试缺少匹配 path/purpose 的 ready/data 与 r8 事实。按实际诊断补足输入后强断言通过，未放宽产品 gate。产品三个文件在各轮始终相同；旧失败日志保留，不把早期测试版本冒称最终版本。
- 相邻 finalizer 33门通过（99.722s），既有 graph executor GPU 模块通过（99.902s）；覆盖既有 exact-two system/property envelope、缺失/不完整状态及 copy/swap 拒绝。不是本片全部状态均有独立真实媒体 App 对照。
- Debug build、strict/deep 签名、code-health通过（1047 Swift、0 error、237 review warnings），防御面保持0 dead/18 canonical/3 swallow。设计门通过；其输出“无设计前置命中”来自 checker 跳过 approved 条目，另以 `design-match-audit.json` 确认三条产品路径匹配已批准设计。没有改基线规避。
- `test_document_role_index` 与 `test_scene_governance_contract` 在本批精确暂存快照中25门通过（1.041s）。共享工作区首跑的两项失败来自并行新建的全仓审查文档尚未登记；其后该任务新增的登记与索引行完整留在工作区，未混入本批。产品没有新增普通帧解析、建图或 hash。

## 未验证边界与下一批

此片恢复的是合法但未支持输入的安全失败半径，不支持三候选 fallback，不保证任意 optional shader、真实媒体迟到、物理多屏、性能或官方 parity。history/clear及 unsafe command 拓扑仍受原硬门约束。现有两个候选的执行合同由对照保护。

下一能力批是 D1：核官方 composition 外层顺序，再在既有 scope 中闭合普通图片父子层级、实际 group source、透明 clear、extent及 GPU lifetime，撤销可退役的旧捕获分支，不创建第二 compositor。
