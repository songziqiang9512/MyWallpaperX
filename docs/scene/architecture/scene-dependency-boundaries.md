# Scene 跨目录依赖试点

<!-- document-role: stable-contract -->

稳定合同：2026-10-03实施登记已退役；owner：repository-governance / Scene Compilation 与 Rendering。本合同承接已完成治理的 P2-6，现役源码职责见[仓库地图](../../architecture/repository-map.md)；仅约束源码结构。权威执行链仍由 [Scene runtime architecture](runtime-architecture.md)定义。

## 判定与范围

设计五问：横切 Compilation/Rendering 治理边界＝是；修改产品 identity/clock/graph/resource/compositor 权威＝否；用户数据或持久格式＝否；冻结新的依赖债务集合＝是；需要外部语义取证＝否。试点扫描器、基线、正反例已并入验证编排，窄实施登记退役；本文继续作为稳定合同，50条现存todo及原检查器继续执法，不表示产品边界迁移完成。

`script/scene_dependency_baseline.json` 是唯一机器声明：试点只禁止 **Rendering 直接引用 Compilation 内部顶级类型**。Compilation 的已准备 graph、Program、shader/reflection 数据、typed frame 输入和失败值属于可跨边界的合同，以精确符号及说明登记在 `public_contracts`。这不是 Swift `public/private` 访问控制重建，也不按文件整体公开；一个文件可以同时定义公共值与内部 compiler。未登记的新 Compilation 类型默认内部，不能因已有消费者就取得公共资格。

公共性判定：可传递的编译结果、执行描述或 typed frame 输入值，可以列入；解析、编译、schema 推导、准入选择、mutable cache/catalog 和 source digest 实现不因此列入。顶级命名空间混有公开嵌套值与内部算法时，试点保守记录 todo，由后续职责迁移区分，不自动公开整个 namespace。例如 `SceneResolvedMaterialShaderSchema.Sampler` 的类型消费和同 namespace 的推导方法目前都属于该结构债务；`SceneResolvedMaterialProgramIdentity` 的 identity 推导入口、`SceneResolvedMaterialMixedProviderSlotFact.resolve` 的作者形状解析、`SceneMaterialRenderState.compile` 的作者字符串解析也没有因名字像值而公开。todo 不证明这些调用发生在普通帧，也不宣判运行结果错误。

已确认的禁止边包括 `Rendering/Bindings/SceneResolvedMaterialTextureResolver+Launch.swift -> SceneShaderContractSourceParser`，以及 texture resolver 对 `SceneResolvedMaterialVariantCache` 的引用。它们是真实源码引用，作为现存 todo 冻结，纠正门是将解析/选择结果在现有 preparation owner 完成后经 typed 合同传递，或经另一个有据设计调整实际所有权；禁止仅改名、包装或扩公共表来归零。

## 扫描与证据上限

扫描 Git 可见（含未跟踪未忽略）Scene 产品 `.swift` 的类型声明和引用；另扫描 `script/tests` 的 Swift fixture 及 Python AST 字符串中具备 Swift 语法的内嵌 harness。产品报告保留各目录对 Compilation 的词法边；只有 Rendering 边受试点禁令约束。harness 可以直接验证 compiler 内部，因此以独立消费清单报告，不冒充 Rendering，不成为产品公开理由。

扫描器跳过 Swift 注释和普通/raw/multiline 字符串，以顶级 `struct/enum/class/actor/protocol/typealias` 声明建立词法符号表，按 identifier token 关联消费者。Unicode identifier-head 范围及 combining suffix 采用 [Swift 官方词法合同](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/lexicalstructure/#Identifiers)；反引号名字按去掉分隔符后的同一 identity 比较，无法识别的声明和未闭合 raw 名字拒绝扫描。todo 身份是 `(rule, consumer, symbol)`，重复调用仍为同一依赖边；行号只作定位。Python 字符串来源通过 AST 读取，不执行测试代码；嵌入片段的行号定位到字符串起点，Swift 文件按实际 token 行定位。

这是结构信号，**不是 Swift 编译器或运行证明**：不解析重载、条件编译活跃分支、类型推导、宏生成、module 重名或跨字符串拼接；字符串插值内表达式未建立类型解析。匿名 `.init` 和经别名间接传播没有独立边；直接 typealias 所在文件的显式内部类型 token 会形成边。Python 语法型片段探测可能遗漏只含表达式的动态 harness，也可能包含未执行模板；实际 Swift fixtures 均纳入。完整图方向和 Resources 所有权尚未作为禁止规则，需试点之后独立裁决。

## 只降基线与退出

`--check` 拒绝新增边及未同步删去的旧 todo；`--ratchet-baseline --reason ...` 只允许删除已消失边，拒绝增长，不提供自动接受增长开关。`--base-ref REF` 同时拒绝相对 Git 基准新增 todo、扩公共合同和更改试点范围；CI 使用合并基准，首次引入无旧基线时显式报告 bootstrap。边界改变必须独立评审，不能作为随手过门动作。

基线每条 todo 保留 owner、理由和退役条件。债务归零后空 todo 即绝对门。若词法误报不可接受，先提供具体反例，收窄探测器而非放宽整目录；整项退役时删除 gate 与基线并更新本文。报告引用总数与 todo 数用于定位工作，不证明兼容、性能、GPU completion 或产品生命周期正确。

执行：`python3.12 -B script/check_scene_dependencies.py --check`；审计：`--audit --format json`；测试：`python3.12 -B -m unittest script.tests.test_check_scene_dependencies`。编排器注册独立 `scene-dependencies` gate（inner/checkpoint 可选择）；Scene 产品、harness、扫描器、基线变化触发，生命周期为 `active`，无 App build 前提。
