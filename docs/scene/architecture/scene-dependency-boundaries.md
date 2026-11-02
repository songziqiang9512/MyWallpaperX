# Scene 跨目录依赖试点

<!-- document-role: stable-contract -->

稳定合同：2026-10-03实施登记已退役；owner：repository-governance / Scene Compilation 与 Rendering。本合同承接已完成治理的 P2-6，现役源码职责见[仓库地图](../../architecture/repository-map.md)；仅约束源码结构。权威执行链仍由 [Scene runtime architecture](runtime-architecture.md)定义。

## 判定与范围

设计五问：横切 Compilation/Rendering 治理边界＝是；修改产品 identity/clock/graph/resource/compositor 权威＝否；用户数据或持久格式＝否；冻结新的依赖债务集合＝是；需要外部语义取证＝否。试点扫描器、基线、正反例已并入验证编排，窄实施登记退役；本文继续作为稳定合同，现存todo及原检查器继续执法，不表示产品边界迁移完成。

`script/scene_dependency_baseline.json` 是唯一机器声明：试点只禁止 **Rendering 直接引用 Compilation 内部顶级类型**。Compilation 的已准备 graph、Program、shader/reflection 数据、typed frame 输入和失败值属于可跨边界的合同，以精确符号及说明登记在 `public_contracts`。这不是 Swift `public/private` 访问控制重建，也不按文件整体公开；一个文件可以同时定义公共值与内部 compiler。未登记的新 Compilation 类型默认内部，不能因已有消费者就取得公共资格。

公共性判定：可传递的编译结果、执行描述或typed frame输入值，可以列入；解析、编译、schema推导、准入选择、mutable cache及source digest实现不因此列入。混合命名空间不能整体公开；先按字段、嵌套类型与实际方法消费者区分依赖闭包。PreparedSampler、MaterialRenderState及运行能力声明已归Runtime/Frame；逻辑纹理identity/purpose与GPU Candidate/Uploader分开。作者字符串解析、mixed/launch资格及Program identity算法仍属原准备owner，Rendering消费准备结果并只附设备/附件事实。Material真实Template/Variant准备消费者未因此成为纯leaf；剩余todo依实际调用和机器清单裁决，不以目录名或结构计数宣称全部职责清零。

原Rendering的Launch/LaunchSelection/LaunchColor算法入口已退出，选择与颜色准入在原准备owner完成；CompiledVariant交付帧槽位，PreparedAssembly交付静态uniform与设备准备身份。执行能力的准备构造和运行声明分开，帧经bindFrame消费资格；GraphExecutor仍检查实际资源、transition及history。此类迁移须有真实compiler/资源/GPU反例，不能靠扩大public_contracts、追加wrapper或搬混合namespace归零；todo本身不证明调用发生于普通帧，也不宣判运行结果错误。

图输入role/classification与layer-source构造已并回既有TextureIdentity值语义；Host schema准备caller不再经Rendering转发，Release也不转运整AdmissionCatalog。机器剩余四条是单份共享cache/digest工具引用：archive准备使用统一持久化工具，Graph失败ID摘要和显式DEBUG观察使用稳定编码/摘要。它们不是普通成功帧的解析/整图认证，也未取得compiler公开资格；保守记录目录耦合，不为归零复制工具或增加每stage诊断缓存。

## 扫描与证据上限

扫描 Git 可见（含未跟踪未忽略）Scene 产品 `.swift` 的类型声明和引用；另扫描 `script/tests` 的 Swift fixture 及 Python AST 字符串中具备 Swift 语法的内嵌 harness。产品报告保留各目录对 Compilation 的词法边；只有 Rendering 边受试点禁令约束。harness 可以直接验证 compiler 内部，因此以独立消费清单报告，不冒充 Rendering，不成为产品公开理由。

扫描器跳过 Swift 注释和普通/raw/multiline 字符串，以顶级 `struct/enum/class/actor/protocol/typealias` 声明建立词法符号表，按 identifier token 关联消费者。Unicode identifier-head 范围及 combining suffix 采用 [Swift 官方词法合同](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/lexicalstructure/#Identifiers)；反引号名字按去掉分隔符后的同一 identity 比较，无法识别的声明和未闭合 raw 名字拒绝扫描。todo 身份是 `(rule, consumer, symbol)`，重复调用仍为同一依赖边；行号只作定位。Python 字符串来源通过 AST 读取，不执行测试代码；嵌入片段的行号定位到字符串起点，Swift 文件按实际 token 行定位。

这是结构信号，**不是 Swift 编译器或运行证明**：不解析重载、条件编译活跃分支、类型推导、宏生成、module 重名或跨字符串拼接；字符串插值内表达式未建立类型解析。匿名 `.init` 和经别名间接传播没有独立边；直接 typealias 所在文件的显式内部类型 token 会形成边。Python 语法型片段探测可能遗漏只含表达式的动态 harness，也可能包含未执行模板；实际 Swift fixtures 均纳入。完整图方向和 Resources 所有权尚未作为禁止规则，需试点之后独立裁决。

## 只降基线与退出

`--check` 拒绝新增边及未同步删去的旧 todo；`--ratchet-baseline --reason ...` 只允许删除已消失边，拒绝增长，不提供自动接受增长开关。`--base-ref REF` 同时拒绝相对 Git 基准新增 todo、扩公共合同和更改试点范围；CI 使用合并基准，首次引入无旧基线时显式报告 bootstrap。边界改变必须独立评审，不能作为随手过门动作。

基线每条 todo 保留 owner、理由和退役条件。债务归零后空 todo 即绝对门。若词法误报不可接受，先提供具体反例，收窄探测器而非放宽整目录；整项退役时删除 gate 与基线并更新本文。报告引用总数与 todo 数用于定位工作，不证明兼容、性能、GPU completion 或产品生命周期正确。

执行：`python3.12 -B script/check_scene_dependencies.py --check`；审计：`--audit --format json`；测试：`python3.12 -B -m unittest script.tests.test_check_scene_dependencies`。编排器注册独立 `scene-dependencies` gate（inner/checkpoint 可选择）；Scene 产品、harness、扫描器、基线变化触发，生命周期为 `active`，无 App build 前提。
