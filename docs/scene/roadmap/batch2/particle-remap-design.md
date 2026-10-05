<!-- document-role: active-plan -->
<!-- retirementCondition: Rain scalar speed Remap 的执行与可见验收由现有粒子能力台账接管，未决 profile 明确归属后归档。 -->

# 粒子 Remap 后继设计

## 目标与差距

恢复作者 Rain 定义中被跳过的 scalar speed Remap，使其结果由后续 Movement 和原粒子合成链消费。与追加调试窗口、继续扩大已接线的封面选项相比，本项直接补齐真实运动职责；先闭合一个有官方行为依据的速度控制，不扩展为完整 Remap 平台。

真实声明顺序是 Alpha Fade → vector velocity Remap → scalar speed Remap → Movement。后者为 `flags=3 / output=speed / range=[-5,7] / fbmnoise / inputscale=8`，缺省 operation 和 input。既有实现只执行显式 `operation=remap` 的 flags0 vector/simplex 子集；不能把该项目噪声近似改名为 FBM，也不能把缺省 operation 猜成 Assign。

## 职责与数据流

沿 `DefinitionParser → Remap declaration → prepared operator plan → Simulator → 原 geometry/compositor` 接入。声明保留缺省与畸形差别，准备期确定准入及参数，普通 fixed step 只按作者顺序消费 typed plan。数学计算归现有 SimulationSupport；不新增时钟、随机状态、诊断扫描、资源或输出 owner。既有 vector Remap 保持原结果和准入；新增 scalar 路径不重复执行前者。

新增字段/flags 的识别必须在同一 declaration owner 校验，避免通用 parser 把畸形 flags 默认成0而扩大旧路径。有限输入仍可能产生超出 GPU Float 的候选；完整候选通过现有数值安全边界后才原子写回，失败保留当前安全 velocity。未知 profile 只跳过对应 operator，其他健康组件继续执行。

## 行为裁决与实施门

公开 [Remap Value 文档](https://docs.wallpaperengine.io/en/scene/particles/component/operator.html#remap-value)说明通道、clamp、运算与映射，但不足以决定 wire flags、缺省输入/运算和 signed speed。先用固定官方版本、自有多行控制点和同场时钟裁清以下执行阻塞项，再批准产品接线：

- 已证：固定官方2.8.42的自有同场控制点中，前置velocity每步重置20；缺省operation与显式multiply的0.5输出均约10单位/秒，显式remap约0.5。flags2/3的49…50输出被压到1，flags0/1仍约49；本批只据此开放目标flags3的输出饱和与缺省Multiply，不外推所有通道。原始有效PNG和自有声明随最终证据保留。
- 已证：无显式input、无transform时，寿命10/20/40秒的opacity随各自age/lifetime变化；延迟出生控制排除system time。缺省inputrange与显式0…1同轨迹，显式0…10约十分之一；复用现有particle age/lifetime，不新增时钟；步内相位和inputscale的变换域继续独立核对，不能把未知wire回退当同义输入。
- 已证：FBM同寿命/出生/scale而不同层位置的两行并不同相，不能只使用共享的 `N(age/lifetime)`。真实range映射能产生停顿、部分速度和完整速度。scale精确域、空间/随机相位来源、octaves、官方公式和严格连续性仍未知，不将短间隔像素当官方数值golden。

## 本批有界实施裁决

开放flags3、缺省或显式multiply、speed、FBM、显式有限标量输出上下界和正inputscale；上下界绝对值及scale不超过既有Remap的1e6边界。显式input/inputrange、blend、其他flags/operation/未知字段继续局部拒绝。缺省operation与显式null/畸形必须区分，不将解析失败当作者默认。

缺省乘法和输出上下界已有速度对照：flags3的负系数与零系数均静止，flags0的负系数则反向移动，零初速度保持静止。按映射输出钳制0…1后乘本步当前velocity，随后由作者顺序中的Movement继续积分。零velocity保持零，负向velocity保留方向，不将系数误作绝对速度。粒子age相位沿现有fixed step，不建立第二时钟。

FBM采用明确标记的项目自有近似，复用现有gradient noise与simulationSeed/particleID导出的无状态相位，以现有归一化年龄乘inputscale作为项目变化输入，四octave倍频/半幅叠加并归一化为0…1；无transform的年龄实证不冒充FBM官方输入域。不读取或复制官方公式。四octave、相位域与scale响应是项目实现选择，不能由上述对照宣称官方相等；用seed去相关符合已观察的不同相，但尚未证明官方相位来源。复用共同相位计算时旧vector/position-offset的数值必须保持一致。

这份批准只允许恢复可观察的有界速度调制，不把operator执行算完整兼容；真实样本必须出现有意义的速度变化并保持健康层、child和合成。若项目近似出现持续静止、所有系统锁相、普通速度路径回退或未达到可见收益，则不提交为已完成；修正项目方案或回到区分实验，保留原安全运行路径。剩余官方轨迹/相位校准交回能力台账，不制造全量正确率。

## 验证与退出

新增小型 CPU 门穿过真实 parser、prepared plan、simulator，验证真实省略字段、操作顺序、正负/零、时间分区、旧 vector 行为及非法字段/数值反例；不继续扩大既有超长测试。Debug build 后在隔离副本比较真实样本的雨滴运动、健康邻层、实际 GPU completion 与唯一 compositor，研究 VM 与 App 串行运行。

样本进度以作者声明和真实执行事件分别计数，不把准入、非黑截图或进入链路当完整正确率。独立只读审查冻结最终 diff 与证据；实际收益达标后重新选择下一缺口，完整官方数值、未测组合和全样本正确性继续独立验收。
