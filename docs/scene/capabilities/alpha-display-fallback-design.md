# Scene alpha 显示与局部降级合同

<!-- document-role: stable-contract -->

本页规定inline alpha脚本的显示权、当前值与局部失败边界。总体职责归[运行时架构](../architecture/runtime-architecture.md)，脚本执行与当前验收归[SceneScript专项](scenescript-api-coverage.md)，属性及Timeline归[输入专项](runtime-input-property-coverage.md)。本合同不按旧样本、表达式分类或旧准入数量决定产品行为。

## 1. alpha的执行与显示权

alpha脚本沿文档binding IR进入既有QuickJS scalar owner，值进入原typed snapshot，再由原图层consumer与compositor消费。引用shared的脚本使用同一domain内的真实JavaScript对象，不另设语法解释器、状态投影或alpha输出owner。

Bool模块初始化及属性事件可以写入该shared对象，scalar回调按既有初始化和事件顺序读取。作者顺序、用户属性、Timeline与脚本返回值各沿原运行时合同处理；不能按源码写法选另一条执行路径。

## 2. 准备期认领与无owner降级

准备期的认领集合为：

```text
claimedTargets = projectedScalarTargets ∪ timelineTargets
```

`SceneRuntimeModelBuilder`使用已准备的scalar及Timeline目标形成集合。scalar准入目标沿`SceneScriptScalarDisplayProjection.apply`释放其alpha脚本压制；集合只说明存在对应值路径，不伪造成功publication，也不替代运行时的typed值接纳。

对于仍标记`displayScriptOwnership.alpha`、但`.layer(id, .alpha)`不在集合中的图层，`applyUnclaimedFallback`只释放alpha压制，保留作者已解析的alpha/current。它不求值脚本文本、不创建owner，也不改变visible位。这个结果是项目的局部降级策略，不是官方加载期显示权parity声明。

认领与降级在准备边界完成，普通帧不重建集合或重新解析来源。独立shared-alpha编译、Runtime状态及帧prepare/merge/commit已退出；当前集合没有第三条shared-alpha来源。模块寿命与资源/graph准入分开：模型或复杂utility的初始化和事件沿同一Bool owner执行；可见返回值进入原typed snapshot，但不产生不存在的prepared资源或target plan。实际资源形态仍在原SourceRoute/UtilityRuntimePlanner消费处准入，不另加模块种类白名单、输出flag或一套寿命。

## 3. 失败与生命周期

成功且类型正确的scalar值进入原snapshot优先级；未构造owner、错型、异常或预算失败时，不以失败结果覆盖对应作者值或低优先级current。其他健康owner继续执行，不能因alpha局部失败把整层永久压制或扩大为整景失败。

真实VM的shared写入、闭包及模块状态与typed输出具有不同边界。回调失败可拒绝本次typed值和mutation，但不能声称撤回已经发生的JS heap写入；某屏未呈现同样不能重放已消费回调。初始化、输入、退出和资源释放继续归原Session/domain及typed owner，不新增共享状态副本或回滚协调器。

visible脚本、Timeline、跨层mutation及其他属性各有自己的消费者；本合同不放宽其能力，不把alpha降级当作强制显示权，也不以旧设计的文件冻结范围限制合理迁移。

## 4. 验证与追溯

行为验证使用实际VM、原typed resolver与真实输出，区分初始化/属性事件、动态shared读取、失败保current、健康peer和snapshot优先级。App/GPU可见结果、切换与退出、官方时序及多屏分别按实际输入证明；VM用例通过不自动授予S4、整批完成或parity。

旧设计的样本、数量、形态表、禁改路径、实验和原验证步骤完整保存在[历史原文](../history/alpha-display-fallback-design-2026-10-01.md)，不定义当前产品准入或任务顺序。

<a id="alpha-display-before-convergence"></a> [归档记录](../history/alpha-display-fallback-design-2026-10-01.md#alpha-display-before-convergence) <!-- archive-redirect -->
