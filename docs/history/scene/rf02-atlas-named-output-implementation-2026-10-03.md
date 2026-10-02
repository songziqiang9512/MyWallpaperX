<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->
<!-- cutoffDate: 2026-10-03 -->
<!-- uniqueValue: atlas named 原失败包、specialized nil candidate 真实来源、局部失败与资源生命周期的本批冻结证据。 -->

# RF02：atlas named 输出与局部失败（2026-10-03）

> **历史证据 — 非现役入口**。 基线 `1f4434af`。完整批次独立终审 **ACCEPT**，限下述职责及验证范围。当前路线见[兼容路线](../../scene/scene-compatibility-roadmap.md)，公开 companion B 不随本批开放。

## 改动与真实反例

产品仅改 dependency reservation 的图像资格与 frame preflight 的精确 ordinary miss 分类。prepared graph 输出按现计划真实 extent 预留；原始图像捕获继续保留原 profile。实际 specialized atlas loader 发布 texture、sprite/sampling 而没有普通 Candidate，不能要求其伪造 Candidate 才发布已准备 graph 的输出。存在却损坏的 Candidate、texture type/sample/usage、计划关联及原 publication identity/epoch/extent/hazard/budget 检查不软化。raw atlas 暂不受支持时只让已获 rollback proof 的 effect 保留入口 current，健康邻层继续。

原失败包来自[上一批实际 App](rf02-authored-sampling-implementation-2026-10-03.md)：atlas effect 层12被层31读取时 image-provider-invalid、零 rendered；padding 对照正常。本批沿原 pkg/project 字节与 ROI 重放，没有把消费者改成 padding。

中间失败保留在 `/private/tmp/mwx-atlas-named/`：

- v1 静审发现 required 集只表示作者可见 effect，双向要求 prepared extent 会误拒现有 source fallback。v2改为非空 extent 必须关联计划，nil仍走原资格。
- v2 原生门通过，但实际 App 六项仅 padding 通过，其余五项仍 image-provider-invalid。根因是 native fixture 手造 Candidate，遗漏真实 specialized loader 的合法 nil；v3修正消费入口，不改 Loader/Candidate 等 B producer。
- v3 产品冻结 `implementation/checkpoint-v3-products.json`，SHA `51665ea54fb2c874b35a0c0ca40d0f5dc9030af9c922ff02375569ba968e2cb5`。独立静审 `implementation/checkpoint-v3-review.md` SHA `c0fdf9c977ee1a255cc8175e5243dab5c825c146dbb4f1c1ed5933dcfd26178c` 接受窄差异，不能替代整批运行批准。

## 验证

原生 RED：冻结基线26个实际 Swift/Metal 输入，合法 atlas 64×32、prepared output 80×40 在真实 reservation 返回 image-provider-invalid。`/private/tmp/mwx-rf02/atlas-named-native-red-v2/red-receipt.json` SHA `40934c6525a31a9e2ec88dd6e0357b88ff46182f0551048643812031d571cf79`。最初测试夹具 sampler shorthand 编译错误保留，不算有效反例。

原生 GREEN：`/private/tmp/mwx-rf02/atlas-named-native-green-v3/verification-receipt.json` 对应8方法通过：7项真实 owner 门和1项旧 stub 非回归。覆盖 prepared extent、两消费者共享且每epoch一次copy、新内容全幅读回、nil Candidate graph准入/raw局部失败、坏metadata/计划/alias/identity/epoch、极小合法raw、无prepared graph的原source fallback，以及同registry epoch1→2取消→3恢复、在飞旧target寿命和真实预算失败恢复。native自行提供 graph-output纹理，不能冒充真实effect compiler或完整Preflight；后两者由App验证。

Debug v3构建成功，1021个tracked Swift/Metal输入构建前后相同；`build-v3/receipt.json` 与 `app-identity.json` 固定证据。隔离 App 为 `source-v3.app`，本地Developer ID签名及strict验证通过，未发布。完整App六项全部通过：原v1 atlas包、原padding对照、raw miss保入口及健康邻层、双消费者、atlas新frame、resize。共14张PNG的预登记内区匹配率100%，每panel四个外点为黑；resize实际1512×982→3024×1964。`app-v3-summary.json` SHA `f8be0d24899a9440823f4c7e6226c26b5a70200bc78bab43602b2a478ea44463`，`app-v3-manifest.json` SHA `ce4afa44d49549805574b637cbc3dc8e4b50f204d4d83da87ac1251a579715cc`。App五binary、两产品、测试及每case pkg/project均前后同冻结身份。动态ready/after覆盖新palette，不声称严格相邻帧索引绑定。

实际GraphExecutor安全补门（`external-safety-v4.log`）通过：history/非零clear图先ready并真实GPU执行，下一epoch缺源prepare拒绝；即使提交拒绝prepare所用command buffer，已有output读回不变；更新provider至epoch62恢复并完成。普通external-primary缺源局部保入口、stale拒绝与恢复同时验证。初版测试自身String/Bool输出错误，以及共享lease夹具把多个FBO映成同一token造成setup失败，均留在v1–v3日志；最终使用既有真实单graph lease，没有改产品或把setup拒绝算运行验证。无FBO的clear function另经真实admission负例拒绝，`admission-clear.log` 1方法通过。

补门发现旧 external-primary 测试把 RT default 当作必然失败输入。其 `independentFramebufferFailureDoesNotRevokeDependencyStage` 在冻结 HEAD 原测试和所有编译产品输入未变时同样失败（`external-head-baseline.log`）；本批把该夹具换成明确非法的 sampler mode，保持原独立阶段失败/后续依赖继续的行为目标，不改产品或通过预期。第一次同时启用 internalDefault 和 invalid sampler 时，前者优先遮住后者，因此没有形成反例；最终移除该冲突设置。完整模块终测 `external-safety-final.log`：2方法通过，206.234s。

code-health、scene-defense、design-gate 通过；有历史warning，不称零警告。文档角色初检发现新历史入口未登记完整，已按既有索引补齐。上一批已经独立证明的两项全局结构库存超额不随本片抬预算，本片不新增结构家族；不宣称全库全绿。

## 最终独立审批

`final-review-v1/owned.diff` SHA `59607d6a00a657b6efeb69e9d37095d5349e075cffd4cc81c98d78b579629eda` 的14路径获 **ACCEPT**。独立报告 `final-review-v1/review.md` SHA `c170a0db03b451e9988365918cfe1e12e1c8c569a5e19607f648715fa5a91e3e` 复核实际产品、原生owner、全部14PNG和失败边界；批准后仅机械填写本裁决、修正报告路径和删除本批设计门登记，B仍blocked。文档角色13方法通过，未追加运行或扩大验收结论。

## 边界与暂停

不宣称官方parity、性能、任意非轴UV、复杂依赖回退或全部atlas profile。三份受保护Scene权威和并行 `script/scene_source_layout.json` 排序改动不进入本批。按用户最新要求，本批独立终审并提交后暂停Goal，不启动下一批。恢复时入口为 RF02 B 的 physical/mapped尺寸与动画相位证据，之后 RF04 mip；不重开已经关闭的旧观察窗口。
