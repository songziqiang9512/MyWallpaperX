<!-- document-role: historical-evidence -->

# 编译结果与帧材质准备收敛（2026-10-13）

> **历史证据 — 非现役入口**。稳定所有权归[代码地图](../architecture/runtime-as-built-map.md)，后续成本与验收归[性能卡](../roadmap/performance-convergence-card.md)及[E1](../roadmap/engine-refactor-program.md)。

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

静态独审已接受最终所有权、安全与fixture迁移，最终实际证据另以冻结packet审查。已通过11项静态门；性能数值、源身份与同产品迁移守恒证据保留在 `.artifacts/tmp/cpu-program-assembly-20261013` 与 `.artifacts/tmp/material-test-convergence-20261013`。benchmark各轮临时App/HOME/样本由现有runner清理；限量保留最终日志、数值和必要像素；517c签名App在下述后继验收后退役；保留后继77a1候选与一份 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData` 给紧接属性诊断，完成后退役。证据cache已到预算且无到期包，promotion待配额可用，不扩大配额或删旧唯一证据。

## 静态准备后继收敛（2026-10-13，已收尾）

删掉 Finalizer 每次构造、但 UniformInputs 没有消费者的 `texturePhysicalSizes` 字典及字段；实际 texture resolution/UV 仍由原 UniformEncoder 从当帧 slot 的 candidate 读取，publication、device、extent、generation 及采样校验不变。只退役重复无用数据，不新增 cache、规则或算法；优化编译器可能已消掉部分成本，未作稳定性能、温度或画面收益承诺。

追最近 GPU 门时发现上批 fixture 迁移遗漏七个消费者，仍依赖已退出的 Python `HARNESS`/`SUPPORT_HARNESS` 字符串，导致 import 失败。已让实际 Swift support 与单 Fixture/shared state 接管，原 Harness 只作唯一入口，所有直接消费者编译这些原单元，不恢复巨字符串、拆源码形状或复制算法。旧 raw variant 构造改走既有唯一 throwing factory，原输入、错误与输出断言保留；三个新增实际 fixture 接入原选门，包含其直接消费者。该问题是本地验证入口回归，不能用上一批两入口或构建通过覆盖。

原270项断言 AST、七消费者多行输入及166初始化次序保留；七消费者、原两入口及 texture transform 分组及定点重跑累计78项成功，含实际 GPU 纹理、alpha 与颜色 ABI。最大fixture889行；证据与冻结聚合 `f05cbe502dab6111e64b2c98c19429469f1bf272412312ea1c46c10d724b502d` 归 `.artifacts/tmp/material-fixture-consumers-20261013`。初次 core 门保留 Finalizer 入口缺 `try` 的编译错误，其余三项成功；修正调用后单独复跑 Finalizer 34项成功，不能把初次日志称为全绿。独审已接受产品与夹具，11静态门通过；签名 Debug -O App SHA `77a19bd212c6a5423a15d5f8b2f2a8a5454d0c86b4fbec312129e6ea2a4b9635`，1111构建输入前后身份相同。独立304副本经正常 App→client→daemon→桌面，owned window23310的14:59与15:01两帧，时钟、人物/星星与谱条实际变化、光束保留；右侧封面仍只在边缘部分可见，未闭该裁切或属性异常。初次浏览进程退出后被界面工具无参数重开，未计入验收；正确重启的App84070保隔离root/suite及HOME/CFFIXED_USER_HOME，daemon84077和像素对应，二者已退出。上述只证有界输出保留，不宣称稳定FPS、功耗或温度收益；后继过程与最终证据保留 `.artifacts/tmp/cpu-unused-uniform-inputs-20261013`。

## 实施前设计（固定快照）

以下保留实施前原E1c裁决，SHA `9342b6646580a4ea0dfaa1e4c256f56873d8998755168ef104315696700d5b8a`；不是新待执行路线。

- **E1c：**把静态ABI/graph证明移到生成边界；live texture、function target、extent、epoch、pin仍核验，不跨commandBuffer缓存PreparedGraph/PreparedPass。**2026-10-13 CompiledVariant→帧Program裁决：**实际普通桌面CPU采样确认ProgramFinalizer→assembleCompiled→deriveCompiled重复静态投影，是成本线索，不是A/B收益。比较只复用pipeline identity、variant持有静态准备结果与缓存整Program，选第二种：在原variant admission的唯一factory一次准备validated layout、固定slot binding索引与shader/prepared/render-state identity；Finalizer只填当帧snapshot纹理/uniform/graph/output facts，原derivation仍核publication、purpose/content/sampling、device、extent、generation及graph-source对应；pipeline key消费Program已有identity，保attachment/sample/writeMask。沿原cache/capability/coordinator生命周期和typed局部失败回退，旧普通帧layout/sampler静态证明与身份重推导退出；TextureResolver及variant selection的现有消费者只读同一prepared slot→channelUse映射，sampler-name/binding证明留在原admission；raw assembly走同factory，不设布尔fast-path、第二cache/registry或跨帧完整Program。变量/资源改名、等价输入及相邻非法layout、stale publication、错device/purpose、缺slot、optional variant切换、失败后恢复和reset反例验证；既有最近门、Debug build、独立样本实际画面/下一帧及三份同条件基线/修后量测接管。无稳定收益只报告结构消融，不能放松动态安全证明。现有两个1322/7120行自有test入口先按完整case族/shared-helper职责迁移，保单fixture状态/lifetime、调用/清理顺序、所有行为断言及原/迁同产品输出；不按任意行数切块，未参与CPU新增case的原反例保持。


## Encoder 静态证明后继（2026-10-14）

PreparedAssembly已验证不可变layout/slot并建立同源shader identity，Encoder仍每pass构造名称Set、字段投影、slot数组/排序/Set。本批删除这几项重复证明，直接读取同一shader slot identity；实际uniform字节与padding、buffer index、sampler名称、纹理publication/device/extent/purpose/generation、target反馈、PreparedPass owner/reset及terminal replay仍按原路径验证。没有新cache或信任标志，也不跨帧持有Program。

冻结生产Encoder的完整prepare局部-O短筛，两种输入交替实际texture对象与uniform值，20次warm/120次计时，计时外核当前绑定与编译次数。pilot后3对C/B、B/C、C/B：1slot/1作者uniform（总2字段）p50 2.708–2.750→2.333–2.375µs，配对下降中位13.636%；8slots/16作者uniform（总17字段）9.167–9.875→8.250–8.833µs，中位12.663%；两形状p95均下降。7拒绝/恢复反例通过，计时窗无新增PSO/library编译；只证局部墙钟，不外推App CPU/GPU/功耗。v0夹具误把总字段当作者字段、漏host字段，计时前失败；保留原失败且修正夹具，不修改产品准入。

同一已编译候选默认完整GPU门137事实全真，含terminal replay、reset/stale、格式/角色、target/command身份与像素输出，复用binary不再编译。独审确认唯一factory及private initializer无绕过路径；证据归`.artifacts/tmp/encoder-static-admission-screen-20261014/proof/`。优化诊断与Debug各一次构建通过（22.740s/16.350s），4294输入无漂移；C App为91fe54e3，另含Host pending仲裁窄修，稳态窗口无属性编辑，该分支不执行。B为bae53b53，真实304同媒体/3024×1964/60FPS/静音/无execution observations，各96s、30s暖机及约64.5s有效窗，期间无构建/测试/profiler。CPU时间率800.447→812.103ms/s（升1.46%），准备p50 4.703→4.647ms、CPU帧p50 8.704→8.711ms，未见整App收益，停止扩测；GPU p50 12.241→10.490ms和footprint峰值989841112→830817936B的下降未归因，不认领GPU/内存/温度收益或稳定非目标验收。两边零GPU失败，原particle loading incomplete仍FAIL；每帧36主/109离屏/33 source capture/2 copy与26902272复制字节不变。只按删除已有静态证明的重复工作保留，不增报专项完成。304两幅原图人物、星空、建筑、云与时钟保留，动态相位/时钟不同，不要求逐像素等价。

独立Bunk只补C实际渲染，复用同输入/矩阵的bae53b53基线；夜间房间、树木、家具、灯光与时钟保留，27项旧FAIL逐项相同。C退出31/31 owner quiescent、surface归零及GPU排空；304同样71/71正常退出。完整GPU门的crossDeviceExercised=false，未覆盖跨设备、HDR/多屏或长期切换。当前91fe54e3 App与共享连续DD留给下一轮；编译试错缓存、重复转储及退出的临时App/样本精确清理，原始报告、必要画面与失败收据保留。
