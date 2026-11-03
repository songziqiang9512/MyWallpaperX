# Scene 依赖边界

<!-- document-role: stable-contract -->

<a id="boundary"></a>
## 当前约束

当前方向是作者事实 → 准备结果 → typed 状态 → 编码与输出，见[总架构](runtime-architecture.md#data-phases)。Compilation 解释源码、schema、选择及准入；Runtime/Frame 承接被消费的描述与运行声明；Rendering 消费准备事实和当前资源，不回到作者解析或 compiler cache 推导静态资格。

可传递的 Program/graph、identity、layout、sampler、失败值不是对完整准备 namespace 的公开许可。纯值按实际消费者放置；mixed/launch、字符串解析和 mutable cache 仍归原准备 owner。只有具体消费者需要才分离，不能为目录或计数制造 wrapper、复制 helper 或另建 owner。

[机器清单](../../../script/scene_dependency_baseline.json)明确允许的产品合同与存量词法边。剩余共享 digest/cache 引用分别用于错误 descriptor 摘要、显式 DEBUG observation 和 launch archive；它们不是普通成功帧整图认证。保单份实现，不能为归零公开算法或增加每 stage 诊断缓存。

<a id="scanner"></a>
## 扫描、变更与上限

`script/check_scene_dependencies.py`扫描 Git 可见 Scene Swift 类型声明/引用，并从 Python AST 和 Swift fixture 读取测试消费者；不执行测试。当前强制边是 Rendering → Compilation internals，其他目录只作结构信号，不冒称完整依赖图已被机器认证。

扫描器不解析 Swift 重载、活跃条件编译、宏、类型推导或完整别名传播。todo 是 `(rule, consumer, symbol)`词法边，不是调用次数、帧热点或运行失败。测试可直接验证 compiler 内部，不因此令产品 namespace 公开。

新增依赖先判断实际数据/算法 owner；已有 typed 结果足够时直接交接，不反向调用或持完整上层对象。真实共享基础工具保其单份实现，必要调整单独说明消费者和退出条件。

`--check`拒新增边及未同步删除的旧条目；`--ratchet-baseline`只删除已消失边。改变范围或公共合同须有实际设计理由，不能改数字过门。语法扫描不能代替编译、GPU 使用期或可见结果；真实验证入口由当前脚本和仓库工作流维护。
