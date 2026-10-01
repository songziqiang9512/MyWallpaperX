<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF05 未支持 optional/named 组合的局部失败（2026-10-02）

> **历史证据 — 非现役入口**。当前权威：[兼容路线](../../scene/scene-compatibility-roadmap.md)、[能力台账](../../scene/semantics/coverage-ledger.md)、[运行证据](../../scene/semantics/runtime-evidence-current.md)。后两份并行权威未改；本记录只保存本批冻结事实。

## 结果与职责

基线 `5f603403`。真实作者解析保留 material named、instance named、system userTexture 三候选，但既有 mixed-provider 只证明两候选；未支持组合仍进入帧准备，optional 不可用时又无 named 依赖 owner，导致全场首帧反复拒绝。

实施前批准的设计（保存在本记录末尾）选择三个现役职责：`SceneResolvedMaterialExecutionCapability+Stages` 在 variant、active demand、invariant 后对活跃且未被 graph 覆盖的未证明组合产生可定位的 launch rejection；`+ProgramFirstStages` 与 `SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough` 复用现有无 history、无 clear 的窄拓扑证明，将安全 effect 留在入口颜色。候选顺序、IR、用途、exact-two profile 均未扩大；不增加 registry、matcher/helper 家族或每帧分析。

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

## 已退役的设计裁决

本片已实施、验证并独立接受，一般失败合同由[稳定架构§3.3](../../scene/design/runtime-architecture.md#33-保留事务安全不扩大视觉失败半径)拥有。按设计门 policy.retirement 删除完成的临时登记；以下保留实施前设计的独有依据，不再作为 active plan。

本设计在实施前 approved，属于[兼容路线](../../scene/scene-compatibility-roadmap.md) RF05 后继；五判据①②④命中：跨 prepared stage 与执行输出、唯一依赖/失败合同及冻结材质家族。只使用本项目源码与自写输入的行为证据，不扩作者 profile，不读取参考项目实现。

### 目标合同与现状

合法作者输入超出现役 mixed-provider profile 时，只退化已证明可安全跳过的 effect，保留其入口颜色、其他层和相邻有效效果。不能让局部视觉不支持反复阻断全场首帧；identity、cycle、range、history 与 target 生命周期错误继续硬拒绝最小 unsafe unit。

`SceneAuthoredMaterialResolver.swift:105–119,247` 依次保留 material named、instance named、system userTexture 三项 provenance；`SceneResolvedMaterialExecutionCapabilityVariant+ProviderSlots.swift:48–64` 的 exact mixed 合同只接受两候选。`SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift:582–608` 不申领该未证明 named dependency，stage却可继续准入。运行时选到 unavailable system 后，`SceneResolvedMaterialTextureResolver.swift:351–356` 产生 resourceSnapshotUnresolved；`SceneResolvedMaterialGraphExecutor+Preparation.swift:255–261` 缺局部失败证明，整帧反复拒绝。

真实修前输入与签名 App 见[RF05 执行记录](../../history/scene/rf05-named-provider-readiness-implementation-2026-10-02.md)的三候选边界；本机 package SHA256 为 `905a211c779383c75961e471d1f5495ab0b5e87263398218cb76af05e7c98274`，日志记录 rendered=0、151次尝试均drop。退出成功不等于呈现成功。路径行号为 `5f603403` 附近定位线索，实施需按冻结代码重核。

### owner、方案与备选

选现役 `SceneResolvedMaterialExecutionCapability+Stages`：先执行真实 variant、active demand、invariant验证，再检查 launchEnvelopeActiveTextureSlots 中没有 authoritative graph override、terminal candidate 为现typed OptionalInput且lower candidate有named的实际slot。复用现 exact mixed proof；未证明时产生可归因到node/slot的专用 launch rejection。全inactive、静态asset/graph终端遮蔽不触发。不修改候选IR、顺序、purpose或选择器，不新增 matcher/helper family。

`+ProgramFirstStages` 的现失败fold只将该专用reason送入既有 `dependencyStageFailureMayPassthrough`，保留no-clear约束；失败stage不安装materials或申领named执行，相邻支持stage沿原ownership/order守恒。`SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough` 消费同reason且复用相同无history窄拓扑，不能加入更宽的ordinary history-capable列表。

备选扩大frame-time吞错会混淆缺资源与identity错误；去重作者候选或放宽exact2会改变支持合同；引入新依赖结果类型会扩多个owner。本片均不选。新增拒绝的产生者是上述真实三候选模板，拒绝范围只能缩小到这个未证明的活跃optional/named责任。

### fallback、纠正门与退役

安全拓扑按现有effect-entry passthrough；clear/history/copy/swap等不满足安全证明时沿既有拒绝，不捏造history或publication。不得把局部白色原图称为三候选named fallback执行成功。

验收：真实作者解析保留三候选及provenance；launch仅该stage退化、零材料/依赖申领；同修前package在签名App出现首帧/next-frame completion、白consumer和绿peer、无timeout及虚假capture；相邻支持effect继续执行；exact2 system/property的ready/absent/pending/unavailable原合同不回退；inactive/terminal-shadow/graph override不误拒绝；不同provider、secondary、错误slot identity及unsafe拓扑不被归一化。Swift行为门、Debug build、code-health、防御/设计门和独立终审均按本片失败半径执行。

稳定材质失败合同接管且上述门通过后归档本设计并删除临时登记；未来扩大mixed profile必须另行设计，不能用本片安全输出当兼容性完成。
