<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# Rain 标量速度 Remap 有界接入（2026-10-05）

> **历史证据 — 非现役入口**。当前权威：[粒子能力](../capabilities/particle-component-coverage.md)；设计与退出条件见[Remap设计](../roadmap/batch2/particle-remap-design.md)。

基线 `1ed8cbaee1916b4c07e2539bc5bdd5f3571bcce4`。真实3780119725的七个Rain root均声明Alpha Fade → vector velocity Remap → scalar speed Remap → Movement；scalar原先被跳过。目标记录为flags3、speed、缺省operation/input、range −5…7、FBM、scale8。原样本只读，App在隔离副本与HOME运行；3788897599为相同声明的伴随回归。

## 行为来源与实现

固定官方2.8.42（Steam23967692）自有控制点证实缺省Multiply、flags3映射输出饱和0…1、负系数停止而非反向、零初速度保持零；无transform默认输入为age/lifetime、缺省inputrange等同0…1。FBM同寿命不同位置控制点不同相。精确公式、相位来源、inputscale域和octaves尚未知，不把公开页面或短间隔截图推导为官方数学。

原Remap声明/准备计划接入严格有界scalar profile；Simulator按作者顺序求系数并乘当前velocity，沿既有Float安全边界原子写回，再由Movement与原geometry/compositor消费。FBM是项目四octave近似，使用现有归一化年龄、无状态seed/particleID相位与gradient noise；不增加时钟、随机状态、空间或输出owner。共同phase提取消除两处重复，旧vector与position-offset数值保持不变。未知input/range/blend、非法字段与其他profile仍局部跳过。

独审发现通用数字parser会丢弃数组坏元素，使混合数组误成scalar；本批在Remap声明owner局部严格校验，避免扩大共享parser影响面。新增行为反例须实际穿过该路径，不把编译失败记为行为红例。

## 验证与证据边界

CPU覆盖真实parser/prepared plan/fixed-step模拟、缺省乘法、映射后饱和、零/反向velocity、作者顺序、时间分区与snapshot replay、RNG不变和非法输入局部失败。旧Simulator在同一合法声明下有行为红例；HEAD旧五owner与候选五owner的vector/position-offset输出精确相等。Debug build、签名及最终App身份由下方冻结证据绑定。

最终版本三轮真实App均退出0、GPU drained。主样本默认与替代背景各44个可见粒子root中43个加载并提交非空GPU实例，七个目标Rain的两轮并集全部完成，failedFrames=0；伴随样本可见2/2同样完成。remapValueUnsupported从主样本七条、伴随一条降为零。两背景44个不同root进入实际GPU链路；全包有48个root，尚未触发的作者隐藏分支不能当加载失败。root578/472及三处fast child仍受world-space/parallax准入限制，下一批处理。

这些计数是组件执行覆盖，非完整视觉正确率。主图、雨线、叶片、文字与频谱在实拍中保留；精确雨滴轨迹/相位没有同输入官方golden，不能宣称完全正确。退出时既有lifecycle cancellation诊断在基线与候选均出现，gpuDrained成立；本批不顺带改生命周期。四octave每粒子每步的CPU成本尚未做可比性能验收，运行用时受编译/缓存影响，不报提速。

真实定义CPU对照直接读取两个隔离pkg，保留七加一个root的作者override、seed和预热；每root推进1/60×720次。每个root都出现零/部分/完整速度系数与恢复运动，新/旧累计位移比0.673…0.691，出生ID、年龄、寿命及最终RNG一致。Movement重力在系数零时仍继续作用，不能描述成严格冻结。此门不模拟children/world transform或动态脚本；实际App另证原折射/合成执行，不以CPU位移比作为官方轨迹或性能指标。

最终新CPU门6/6、旧Remap两门2/2、相邻粒子94项及文档49项通过；实际旧Simulator有6个行为失败，strict-shape最终同测试有20个畸形数组反例失败，均非编译假红。依赖、代码健康、防御、设计及仓库残留门通过。结构13项中两项既有analyzer inventory/classification失败（66/65及PreparationAdmission），未抬基线；不宣称整仓全绿。

最终Debug build与深度严格签名校验通过，dylib SHA256 `8b1c1267539b864fb5fdfc71d455f43a392b00b12640c5c540449bfd6b50fd7b`。默认Rain六个root各完成73帧，替代选项六个各76帧，并集7/7；伴随291完成210帧，均非空实例且failed0。代码独审已接受数组修复；最终证据审查以同一源码/测试及App身份为边界。

最终证据包 `.artifacts/scene-evidence/runs/particle-scalar-remap-20261005/final/samples/3780119725/runtime_evidence.zip`，24,737,751字节，SHA256 `529b564c81c5f31ad5caeade643bd24d70f25b9db12c1edce885eef62055e408`。118个payload哈希及ZIP CRC通过，保留14日，包含两真实样本日志、主样本有限PNG、同输入CPU前后结果及官方自有控制点/source-only声明；不含原始pkg、App或官方私有缓存。官方研究后VM恢复暂停，原配置hash不变；本轮隔离HOME/样本、旧App及重试输出结束后清理，连续开发保留一份构建缓存与最新已验App。
