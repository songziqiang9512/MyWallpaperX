<!-- document-role: historical-evidence -->

# 编译结果与帧材质准备收敛（2026-10-13）

> **历史证据 — 非现役入口**。稳定所有权归[代码地图](../architecture/runtime-as-built-map.md)，后续成本与验收归[性能卡](../roadmap/performance-convergence-card.md)及[E1](../roadmap/engine-refactor-program.md#e1--压缩-admission-与帧存储cpu-热点成立时优先)。

## 通用语义与旧职责退出

材质的不可变ABI、固定slot索引、sampler channel-use与shader/prepared/render-state identity，由原variant admission的唯一throwing factory准备一次，存入原CompiledVariant。Finalizer继续生成当前帧Program；原derivation每帧校验publication、purpose/content/sampling、device、generation、extent/UV、graph-source对应、color及output。原sampler-name/binding准入保持。raw assembly同factory，不以布尔信任入口绕门，不跨commandBuffer缓存PreparedGraph/PreparedPass，也没有第二cache/registry。pipeline key消费Program已有identity，保attachment/sample/writeMask。旧重复layout/identity推导与无调用的validatedSamplerChannelUses退出。

factory的frontend失败在原最早位置提交，其余typed结果在原sampler、graph、uniform守卫后消费一次。初稿曾改变组合非法输入的失败优先级，独审发现后修闭，不能把首稿构建当最终验收。没有样本、路径、hash或固定源码形状例外。

原1322/7120行测试入口按输入、准备、framebuffer、动态uniform、provider、graph、失败等完整职责迁至13个Swift单元；一个Fixture持有全部case族、唯一Harness按原顺序初始化并延长生命周期至输出完成。未任意切字符串、复制算法或删除旧断言。

## 固定身份与验证

产品聚合SHA `fee58720dc1fb4edf1a4c7881dd07dd24bbe3f13850097e5b6cd0497177d56e7`，两个新增fixture聚合 `22b3e1664df323caea1739fd6dc54e5de033fff6a5b5bb100be3c79f6db0b93f`。改名、等价表达式的60项及连续帧live变化及邻近非法layout、stale/purpose/missing slot、attachment/sample/writeMask反例通过；七项组合错误优先级和恢复冷暖均通过。原/迁同产品测试73个Python断言AST、64个helper token、166项初始化顺序、原键值与诊断守恒；最新两门35 tests通过。4项实际GPU近邻门通过；签名Debug显式-O最终App SHA `517c746fa3b1b5c45fa9cb7bfc6a245f66d189f032a4862f87322b6867ded41e`，构建前后逐源身份匹配。

**同条件成本对照。** 2932157836、内部Host、签名Debug -O、固定静音音频输入、3024×1964、60 FPS、warmup 30 s、测量约63.5 s；performance-only关闭执行观察，不能作为能力矩阵PASS。三份初始基线均保留，包括第二轮CPU/GPU高值；其后按T1→C4→T2→C5→T3→C6交替，不挑最好基线。各轮输入哈希、属性、每帧GPU工作相同：55次resolved pass、13次source capture、4次copy、23,756,544 framebuffer capture及33,398,528 copy字节。

| 运行 | CPU p50 / p95 ms | GPU p50 / p95 ms |
|---|---|---|
| 原B1 | 5.565 / 6.066 | 8.112 / 8.266 |
| 原B2 | 6.103 / 6.548 | 11.214 / 12.593 |
| 原B3 | 5.537 / 6.082 | 7.969 / 8.622 |
| 新T1 / 原C4 | 5.424 / 5.866 · 5.524 / 6.432 | 8.217 / 8.598 · 8.602 / 12.194 |
| 新T2 / 原C5 | 5.487 / 6.251 · 5.535 / 6.301 | 8.560 / 11.216 · 8.383 / 11.556 |
| 新T3 / 原C6 | 5.434 / 6.030 · 5.648 / 6.063 | 8.332 / 9.180 · 8.111 / 8.245 |

相邻三组CPU p50观察下降1.81%/0.87%/3.79%，prepare p50下降2.29%/1.92%/4.29%；C4–6中位5.535 ms与T1–3中位5.434 ms（−1.82%）。差异仍小于初始轮次噪声，**不宣称稳定整帧性能、GPU、内存、首帧、功耗或温度收益**，按删除静态重复工作的结构消融交付，性能专项不因此增报完成比例。GPU工作未减少；footprint与GPU时间有轮次波动，不用其偶然下降作收益。九轮failed/discontinuity均0、steady-state eligible均true；C4实际present超1.5预算比例1.2871%超过默认1%，如实保留，其他轮低于1%。该控制轮债务不能被中位数或性能矩阵PASS掩盖，也不关闭全局AS1。

**实际画面。** B1与T1内部Host图片检查人物、水纹、星星、颜色与合成保留，仅动态位置变化；该入口原有时钟/媒体差异不算修复。未参与CPU修法的3042492564用正常App→client→daemon→桌面：同owned window23104的13:15与13:16两帧实际时钟进位、星星/光束移动、音频条及封面更新；原颜色544 `event is not defined`、封面右侧裁切仍存在，未关闭属性完整cohort或样本parity。未控制实时媒体，不能据此宣称平台媒体适配或幅度完全正确。正常App/daemon已退出。

静态独审已接受最终所有权、安全与fixture迁移，最终实际证据另以冻结packet审查。已通过11项静态门；性能数值、源身份与同产品迁移守恒证据保留在 `.artifacts/tmp/cpu-program-assembly-20261013` 与 `.artifacts/tmp/material-test-convergence-20261013`。benchmark各轮临时App/HOME/样本由现有runner清理；限量保留最终日志、数值和必要像素；唯一517c签名App与一份 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData` 暂留给紧接的属性诊断/同源基线，诊断完成后退役。证据cache已到预算且无到期包，promotion待配额可用，不扩大配额或删旧唯一证据。

## 实施前设计（固定快照）

以下保留实施前原E1c裁决，SHA `9342b6646580a4ea0dfaa1e4c256f56873d8998755168ef104315696700d5b8a`；不是新待执行路线。

- **E1c：**把静态ABI/graph证明移到生成边界；live texture、function target、extent、epoch、pin仍核验，不跨commandBuffer缓存PreparedGraph/PreparedPass。**2026-10-13 CompiledVariant→帧Program裁决：**实际普通桌面CPU采样确认ProgramFinalizer→assembleCompiled→deriveCompiled重复静态投影，是成本线索，不是A/B收益。比较只复用pipeline identity、variant持有静态准备结果与缓存整Program，选第二种：在原variant admission的唯一factory一次准备validated layout、固定slot binding索引与shader/prepared/render-state identity；Finalizer只填当帧snapshot纹理/uniform/graph/output facts，原derivation仍核publication、purpose/content/sampling、device、extent、generation及graph-source对应；pipeline key消费Program已有identity，保attachment/sample/writeMask。沿原cache/capability/coordinator生命周期和typed局部失败回退，旧普通帧layout/sampler静态证明与身份重推导退出；TextureResolver及variant selection的现有消费者只读同一prepared slot→channelUse映射，sampler-name/binding证明留在原admission；raw assembly走同factory，不设布尔fast-path、第二cache/registry或跨帧完整Program。变量/资源改名、等价输入及相邻非法layout、stale publication、错device/purpose、缺slot、optional variant切换、失败后恢复和reset反例验证；既有最近门、Debug build、独立样本实际画面/下一帧及三份同条件基线/修后量测接管。无稳定收益只报告结构消融，不能放松动态安全证明。现有两个1322/7120行自有test入口先按完整case族/shared-helper职责迁移，保单fixture状态/lifetime、调用/清理顺序、所有行为断言及原/迁同产品输出；不按任意行数切块，未参与CPU新增case的原反例保持。
