# Mirage da4fa7b3 六域考证汇总裁决

> **历史证据 — 非现役入口**
>
> 截止日期：2026-10-01
>
> 类型：考证记录（`third-party-reference-pattern` 静态取证汇总裁决；对象为 `laobamac/MirageWallpaper` 钉定 revision `da4fa7b3ee33e9e94c59307f47098aa521f21aa6`，GPL-3.0 第三方项目，只做静态源码审查、未构建未运行）
>
> 独有价值：六域（render/particle/clock/property/camera/modules）59 条 findings 的逐条裁决分类（gap/corroborated/mirage-specific）、Mirage 证据行号、我方文档核对结论与置信度；以及"待 Scene 会话收编清单"与 mirage-specific 隔离记录归档
>
> 当前权威：**本文是历史证据留档、事实链最低位，不作现役合同。**现役事实按 AGENTS.md 第 2 节顺序核对（当前代码和可复现运行证据 → AGENTS.md → 长期架构合同 → 专题当前表 → 历史证据）。gap 条目的落点见"待 Scene 会话收编清单"，须由 Scene 会话按各目标文档自身格式收敛登记；本文不更新覆盖台账与运行证据。已直接落入白名单文档的条目，现役记载见 [Mirage 显示链路参考](../development/reference/miragewallpaper-rendering-reference.md)（§1.1 表、§3、§4、§5、§7.4、§8.2、§9.4、§10、§11.2、§11.5、§11.6、§12）与[资料来源索引](../development/source-index.md)（§1.2 PKGV 观察）。

## 一、逐域逐条裁决

裁决分类口径：`gap`=职责分层/状态/顺序范畴的真实记载缺口（算法数值细节不属此分类）；`corroborated`=我方已有记载与 Mirage 行为互证加强；`mirage-specific`=Mirage 特有实现选择，隔离记录、不入我方合同。行号均属钉定 revision `da4fa7b3`，不能跨 revision 复用。置信度基于双侧证据逐行复核；唯一未决点按"单源不升格"保守登记。

### 1. render 域（10 条）

| 编号 | 裁决 | Mirage 证据行号（@da4fa7b3） | 我方文档核对结论 | 置信度 |
|---|---|---|---|---|
| render-0 | gap | `SemanticTextures.cppm:9-12`（g_Texture0..12 宏）、:17-22（五伴随家族）、:24-48（`_rt_` 前缀 + 14 前缀 :26-40 + sr 自造 :43-48；`WE_EIGHT_COMPO_BUFFER_PREFIX` 串为 `_rt_EightBuffer` :30） | 我方现役语义文档无 14 前缀集中表、无"WE 内容/sr 自造"二分类；仅三条零散断言 + 历史审计 :688；`_rt_link_<id>` 名归 sr 自造与我方记为 Mirage 行为一致。已收敛进参考文档 §5 统一记载；官方语义面收编见清单②-1、尾注②-2 | 高 |
| render-1 | gap | `SceneCompiler.cpp:1633-1675` ParseSpecTexName 全分派（调用点 :1939 材质纹理 slot 循环内）；`SemanticTextures.cppm:210` IsSpecTex、:72 WE_CB_BLENDMODE、:219-221 GenLinkTex；全仓 grep 仅 SceneCompiler.cpp 一个文件命中、无测试引用 | 我方仅三个孤立端点（§11.5 光照表 castshadow/volumetrics 行、§11.6 `_rt_link_<id>`），其余分派行为零记载；已收敛为 §5 统一特殊纹理准入记载并替换零散表述 | 高 |
| render-2 | gap | `SemanticTextures.cppm:27-30`；`SceneCompiler.cpp:1657-1660`（四空体准入分支）、:3355-3410/:4953-4968（通用 effect FBO 注册）；`ImageLayerSpec.cpp:202-208`（compose 特例）；Tests grep CompoBuffer=0 | 我方 render-graph-shader-coverage.md:235 与 coverage-ledger.md:918 的 `_rt_FullCompoBuffer1/2` 为我方 fixture 自有命名、撞名非互证；官方 2.8.42 审计 :658-663 互证"官方资产自带 fbos 声明"。保留关系已入 §5；消歧见清单②-4 | 高 |
| render-3 | gap | `SceneCompiler.cpp:6203`（BuildBloomPostProcess）、:6216-6218（三 RT 屏比例）、:6220-6226（fboMap 双别名）、:6229（`__bloom`）、:6297-6317（参数）、:6512-6513（触发）；:1661-1666（`_rt_Bloom` 清空）vs :1652（`_rt_bloom_mip` 保留） | 我方 §8.2 已记载 Bloom graph（互证）；`__bloom` 名、fboMap 双别名、`_rt_Bloom` vs `_rt_bloom_mip` 命运差异已补入 §8.2 | 高 |
| render-4 | corroborated | `World.cpp:1443-1453`（EnsureLinkRenderTarget 惰性注册 allowReuse=false）、:1422-1437（EnablePlanarReflection）；`SceneRenderPlanner.cpp:196`（GraphLinkFinalizer::apply）、:213-221；LayerVisibilityRegression.cpp:155-179 | 我方 §11.6:476、§6.4:216、§8.3:298 已有一致记载互证；出处行号已按短引用格式补入 §11.6 | 高 |
| render-5 | gap（范围收窄） | `CompilePipeline.cppm:23-26/53-55/85-90/154-183`（四阶段签名）、CompatibilityProfile.cppm 恰 3 行；`SceneCompiler.cpp:5536-5560/5608/5617/5624/6041-6085/6087+/6198` | 我方 :170 已记 FinalizeScene 声明顺序=z-order（第 4 阶段核心语义在场）；真实缺口是四阶段框架、前 3 阶段职责边界与两入口文件，掩码实为 6 位（发现"8 类对象"措辞已按 6 位掩码+Shape 复用 Image 位+Camera 不受掩码写准）。已入 §1.1 表 + §3 表改写 | 高 |
| render-6 | gap（含 mirage-specific 侧面） | `ShaderLexer.cppm:26-28/:190`；`ShaderAnnotations.cpp:12-16/:224/:33/:167-172/:215-236`；`UniformSpec.cppm:13-15/:31/:83-84/:123-125`；`MaterialShaderCompiler.cpp:32-93/:1783-1787/:1816-1817/:132-149/:854`（过期指针，WPShaderParser_Pegtl.cpp 不在钉定树）；grep `[PASS]`=0 | 我方仅 source-index.md:77 与参考文档 :40 记 ShaderAnnotations 一角；三层分工与 schema 本体零记载，已入 §1.1 表（仅落 Mirage 参考文档、不进 forensics）；Mirage 不识别官方已证 // [PASS] 属其自身缺口，以官方 forensics §5.1 为准 | 高 |
| render-7 | mirage-specific | `MaterialShaderCompiler.cpp:1526-1532`（动机注释）、:1533-1571（EmitCBufferStd140）、:1554-1560（major 选择）；vendored glslang ShaderLang.cpp:921-922 | std140 packoffset 逐成员装配是 Mirage HLSL 前端绑定其 glslang HLSL 源路径的工程 workaround，属编译器装配机制细节；我方无 HLSL 前端、以 GLSL std140 装配，不构成可迁移合同条目 | 高 |
| render-8 | mirage-specific | `ResourceKey.cppm:41-59/158-242/205-214/216-223/296-303/322-324/408-414/596/619/630-647`（PipelineKeyWriter/类型 tag/FNV-1a/排序/版本 tag/attachment identity）；官方对照空串 | 纯 Vulkan 三级 GPU 资源缓存键字节格式属算法与实现细节，我方为 Metal 渲染器无对应物；Program identity/prepared digest 已有现役记载（coverage-ledger.md:832），不构成缺口 | 高 |
| render-9 | gap（收窄：主体 mirage-specific，唯一 gap 为 g_Texture3 缺省绑定生产职责） | `BlitPass.cpp:59-67`；`SceneRenderPlanner.cpp:213-221/233-245/264-269`；`BufferResolver.cpp:104-157/181/193`；`PreparePass.cpp:11-64`；官方 assets/shaders generic3.frag:53 等（g_Texture3 hidden 注释） | 我方 §5.5（scene-format-and-render-graph.md:195-206）已完整记载官方 copy 语义；CopyPass/改名 copy/缓存环等主体为 Mirage 特有；唯一收编项为 g_Texture3 hidden uniform 缺省绑定 `_rt_MipMappedFrameBuffer` 生产职责+"无消费者不生产"，见清单②-3（发现两处行号引用已按 :173/:186-192 订正） | 高 |

### 2. particle 域（10 条）

| 编号 | 裁决 | Mirage 证据行号（@da4fa7b3） | 我方文档核对结论 | 置信度 |
|---|---|---|---|---|
| particle-0 | corroborated（补强引用） | `WallpaperEngineRuntime.cpp:1822-1824/1572-1591/1101-1107/1111-1115/1232/1218`；`ParticleSystem.cpp:235/257-270/510-513/467-468/583-589`；`ParticleEmitter.cpp:210-213`；ParticleCompiler.cpp:583-599 | 我方 particle-component-coverage.md:160(G18)/:375(X10)、coverage-ledger.md:1051 三处同构互证；一处文件归属笔误（trail 采样累积器在 ParticleSystem.cpp 非 ParticleEmitter.cpp）已按订正行号补入参考文档 §11.5 host-pause 段 | 高 |
| particle-1 | gap（Mirage 单源不升格） | `World.cppm:2110-2113`（ParticlePlaybackState）；`ParticleSystem.cpp:237-267`（SyncPlayback/Tick early-return）；`SceneCompiler.cpp:3934-3936/4121/4155/4174-4188`（child 共享 + root 四回调） | 我方 G18/X10 仅登记 host 级；对象级播放门（play/pause/stayPaused/isPlaying、reset_sequence 归零 Refresh、play 为重置非续播、child 共享 root state）无记载；我方 SceneParticlePlaybackState 同名异义。待收编见清单②-5 | 高 |
| particle-2 | corroborated | FieldBindingSpec.cpp:114-160/:56-64；ParticleLayerSpec.cpp:270/:297-305；`SceneCompiler.cpp:4189/4191/769-825/821-824`；`World.cpp:833-839/1393-1404`；`WallpaperEngineRuntime.cpp:1206/1217` | 我方 runtime-input-property-coverage.md:220/:224 已登记"粒子节点 Timeline presence-only 限制"，与 Mirage 消费节点级四曲线的差异在案且无相悖断言；实现细节留隔离记录，不改我方记载 | 高 |
| particle-3 | corroborated | ParticleLayerSpec.cppm:41-46（缺省 + "default matches WE behaviour" 自述）；ParticleLayerSpec.cpp:57-65/:192-197；`SceneCompiler.cpp:1381-1390/3942/4071-4080/1369-1370`；WallpaperParticleGeometry.cpp:698-717/:341-343/:575-577 | 我方参考文档 §11.5:453 数值一致、particle-component-coverage.md R04:256/R11:263 一致；:453"本轮未全字段重证"措辞已按重证结果收敛替换，R04 谨慎措辞不升级 parity；互证引用待收编见清单②-10 | 高 |
| particle-4 | mirage-specific | ParticleLayerSpec.cppm:119-135；ParticleLayerSpec.cpp:12-41/:90-91；`ParticleSystem.cpp:78-102/350-374`；ParticleCompiler.cpp:413-414；`SceneCompiler.cpp:1558-1569/4058-4061` | 我方 CH04/coverage-ledger:1151 已记同 pattern（父死回收、CP 取模）；particle_idx 簿记/spawn_sequence 映射为 Mirage 自有重构动机（:92-94 自述）且与我方 no-CP eventfollow 准入刻意不同；**不得据此关闭参考文档 :454 "eventfollow、CP identity" 待验项** | 高 |
| particle-5 | corroborated（主干） | ParticleLayerSpec.cpp:82-86；ParticleLayerSpec.cppm:76-80；`ParticleEmitter.cpp:106-128/229/273`；`ParticleSystem.cpp:568-575`；`World.cppm:2908/2417`；`WallpaperEngineRuntime.cpp:1174-1205`；`SceneCompiler.cpp:4122-4127/1553` | 我方 §11.2:408/:410、particle-component-coverage.md:9、coverage-ledger.md:296 互证；audioamount 命名差异属 Mirage 自选 schema 集，与我方 E15 官方 schema 断言分属两域、非冲突 | 高 |
| particle-6 | corroborated | `ParticleEmitter.cpp:22-57/59-70/210-211`；`SceneCompiler.cpp:1548-1555/4134`；`ParticleSystem.cpp:104-131/506/510-513/378-382`；SetRateSource 定义 World.cppm:2273 | 我方 IV05/E07/E08/E09/E12（particle-component-coverage.md）语义互证；timer/floor/fmod 公式与 sort=false+CompactInstance 数据结构为 Mirage 内部实现；两处行号勘误已记录（one-per-frame 在 :12/:179 与 runtime-systems-reference.md:91；instantaneous 即 E08:175） | 高 |
| particle-7 | corroborated | `World.cppm:2115-2131/2142-2148`；`ParticleSystem.cpp:53-56/104-130/208-216/272-316/406-414/477-503`；46f54105 提交 | 我方 R04/G03/X09 与 64227db5 实现（每粒子 8 槽 SoA 环形历史）机制同构互证；容量/采样间隔参数为各自实现选择；一处措辞精度已记录（容量=m_trail_length，interval 只是采样间隔） | 高 |
| particle-8 | corroborated | `ParticleCompiler.cpp:240-250/502-542`；`World.cppm:1976-1979/2028`；WallpaperParticleGeometry.cpp:79/:164 | 我方参考文档 :444 与实现（SceneParticleUnaryOperatorPlans.swift:10-11、SceneParticleSimulator.swift:756-765）逐字互证；跨 f504958/da4fa7b 两 revision 语义逐字节相同，互证更强；无需补条目 | 高 |
| particle-9 | mirage-specific（我方自有行为无互证对象） | `SceneCompiler.cpp:1549/1571-1588`；WallpaperParticleGeometry.cpp:341-343/:575-577（唯一排序=spawn_sequence）；ParticleCompiler.cpp:660-705（仅两种 emitter）；grep layerimage=0 | 我方 64227db5 两项（发射图 alpha 加权、半透明条件排序）为项目自有 bounded 质量修复、无 parity 宣称；非 conflict/gap/corroborated；附带观察：particle-component-coverage.md E03 行仍写二值化等权实现、未同步 64227db5，属我方内部文档滞后，可在后续文档批收敛 | 高 |

### 3. clock 域（9 条）

| 编号 | 裁决 | Mirage 证据行号（@da4fa7b3） | 我方文档核对结论 | 置信度 |
|---|---|---|---|---|
| clock-0 | gap | `FrameClock.cpp:11-72`（busy CAS/双帧时/5 帧窗口/15 FPS）；FrameClock.cppm:12-14；WorkerTimer.cppm:3/:10/:31 | 我方 docs/scene 零记载（grep FrameTimer/ThreadTimer/ClockModule=0）；已入参考文档 §11.2 帧时钟家族 bullet，不改我方 SceneFrameTiming 合同 | 高 |
| clock-1 | gap | `WorkerTimer.cpp:20-88`（SetInterval 原子 revision/重探测/deadline 追赶不补帧/Stop 断言）；ClockModule.cppm 4 行纯 re-export；`WallpaperEngineRuntime.cpp:25/:1040`（唯一产品消费者，全仓 grep import sr.timer 证实） | 我方零记载；已入 §3 表 sr.timer 行 + §4 排程语义段；与官方 2.8.42"到期每帧至多执行一次"（runtime-systems-reference.md:352）及我方 :485 同向；数值细节（interval/8、1ms 下限、15Hz）不入条目正文 | 高 |
| clock-2 | corroborated | `WallpaperEngineRuntime.cpp:1133-1134/1223/1232/1324`；`World.cppm:2929-2933`；`FrameClock.cpp:33-38`；`WorkerTimer.cpp:27-36/74-89`；grep elapsingTime 唯一累积点 | 我方 §11.2:405 与 runtime-systems-reference.md:29/:485 同向互证；fi.frametime 字面 speed 二次乘（≈speed²）属 Mirage 实现细节，与 dt 语义结论无关 | 高 |
| clock-3 | gap | `ControlChannel.cpp:79-102/84-88/19-20/180-198`；RendererController.swift:22-32/:2479-2518 | 我方 runtime-systems-reference.md:55 reason-set interruption coordinator 职责分层同形对照；已入 §1.1 表；不更新 coverage-ledger 与运行证据 | 高 |
| clock-4 | gap（待收编） | `WallpaperEngineRuntime.cpp:1818-1824/84-91/1572-1591/1593-1595/1101-1109/1506-1509` | MainStop/MainPauseAudio 路径零记载（grep=0）；我方 runtime-architecture.md:491 暂停合同留有"由既有行为合同决定"空位；帧停同步立即 vs 音频延迟 fade+generation 门作废，与 commandGeneration 迟到事件语义（coverage-ledger.md:222/:224）模式同构。见清单②-6 | 高 |
| clock-5 | corroborated | RendererController.swift:511-521/:1300/:1336-1363/:1365-1374/:1404-1432/:1459-1473/:1486-1516/:1573-1593 | 我方 scene-launch-responsiveness-contract.md:20/:143/:152 与九相位一一对应互证；:143 的 standby 保全要求正是 Mirage 可见性 guard 的对照语义。七段行号锚点挂引见清单②-7；枚举命名属 GPL 内部形状、我方保持自有命名 | 高 |
| clock-6 | mirage-specific | RendererController.swift:574-578/:1227-1232/:1343-1346/:1380-1382/:1390-1400/:1595/1426/1535/:48-50 | 两段式 desired-state 重放是 Mirage"每显示器一进程+IPC 指令流"的派生物；我方以属性快照 identity/newer-wins/提交时复核（responsiveness-contract 4.1/4.2）结构性覆盖同保护语义，重放操作无法映射进单进程 Metal 主链 | 高 |
| clock-7 | mirage-specific | RendererController.swift:593-601/:1659 起 schedule*Timeout 系列/:1248-1252 | 相位超时数值（75/300/3/8s）与相位驱动结构是 Mirage 客户端实现选择；我方有先例规则排除同类客户端常量（client-runtime-static-forensics.md:257 末句） | 高 |
| clock-8 | mirage-specific | PlaylistRotator.swift:180-188/:162-173/:198-207/:209-240/:242-251 | 我方无 playlist 轮换功能（代码与 docs 零命中）；整条为 Mirage 特有产品功能实现；附带：官方 changelog 附录 :1600 印证官方存在视频播完触发轮换的可见行为，未来立项可作行为规格参考 | 高 |

### 4. property 域（10 条）

| 编号 | 裁决 | Mirage 证据行号（@da4fa7b3） | 我方文档核对结论 | 置信度 |
|---|---|---|---|---|
| property-0 | mirage-specific | UserProperty.cpp:26-34/:40-51；`WallpaperEngineRuntime.cpp:306-319/152`；PropertyEditor.swift:266-270 | wire 字符串二次 JSON 解析/typed patch 是 Mirage 自有 App↔renderer 协议；我方解析层不做二次解析且 :130/:300 已有 consumer 侧分层与缺口记载，不构成值得补的 gap | 高 |
| property-1 | gap（收窄，待收编） | `WallpaperEngineRuntime.cpp:169-175`（CanonicalUserPropertyKey 唯一规则）/`:878-891`（显式 canonical 键总是终胜，归一键间首键胜出）；Runtime.cpp:152/:154-158；Kernel/UserProperty.cpp:38-40 | 我方全 docs/源码零命中；runtime-input-property-coverage.md 5.2 已有 schemecolor L1 立场但无 key 归一层记载；官方生态有 scheme_color 拼写旁证（SceneStockAssets project.json key 全为 schemecolor + ui_browse_properties_scheme_color token），但 scenerenderer.scheme_color 在 Mirage 仓库无生产者、无官方对照。见清单②-8 | 高（中高：官方拼写指向为间接旁证） |
| property-2 | gap（待收编） | `WallpaperEngineRuntime.cpp:847-876/1637/1673-1679/1686-1697/1731` | 我方 SceneDocument.swift:96-116 语义同构（effective values 解析期生效）互证但加载顺序无直接记载；scene-format-and-render-graph.md:115 有官方"首次加载调用一次"可挂靠。见清单②-9 | 高 |
| property-3 | corroborated | `WallpaperEngineRuntime.cpp:1326/:1330-1348/826-844/1351-1355/1357-1363/1369-1371` | 我方参考文档 §4.1(:118-127)/:116/:125/:412 覆盖更广且同向；两处粒度差异（我方 visibility 分级更严格、17 步序列为 Mirage 函数组织）均不构成 conflict | 高 |
| property-4 | mirage-specific | `WallpaperEngineRuntime.cpp:1535-1554/1716-1717/1727-1728/1692-1697` | 双路径是 Mirage MainConfigure/RenderInit 双消息循环特有窗口绕行；我方事务/submission barrier（runtime-input-property-coverage.md:135/:137）+入口 Bool guard 已覆盖防丢语义 | 高 |
| property-5 | gap | `DocumentModel.cpp:78-83/275-282/294`；SoundLayerSpec.cppm:41-44/:54/:80-83；MiscLayerSpec.cppm:96/195/256；`ImageLayerSpec.cpp:110/:137-138` | 我方 PKGV 记载均为 census/pkg 布局口径，字段级版本语义零记载；已收敛登记进 [source-index.md](../development/source-index.md) §1.2（三点边界随条目）；发现 :99-100 行号笔误已按 :275-282 订正 | 高 |
| property-6 | gap（待收编） | VisibilityRule.cppm:24-45/:47-69/:71-94；MiscLayerSpec.cppm:15/:64-75；grep 泛化调用点 ImageLayerSpec.cpp:314/:318 | 我方 :129 仅覆盖 conditional Combo；visible 双职责（布尔初值含 object.value-boolean + user 绑定载体 string 简式/{name,condition}）零记载且我方实现同语义互证（SceneDocument.swift:293-301、SceneUserPropertyBindings.swift:230-250）；int 范围门属算法细节不写入。见清单②-11 | 高 |
| property-7 | mirage-specific（隔离） | `Visibility.cppm:16-58`（含 bool↔"1"/"0" 交叉匹配）；`World.cpp:1135-1155`；LayerVisibilityRegression.cpp:47-62 | 我方严格 string==string（ScenePropertyBindingProgram.swift:82-88/:130-137）与 Mirage 宽窄不同属同主题不同谓词，不构成矛盾；补进合同有"行为等同"误读风险，隔离即可。"与 App 编辑器侧 JS 求值分离"的编辑器侧背景未能取证 | 高 |
| property-8 | mirage-specific | PropertyEditor.swift:26/:215-217；WEConditionEvaluator.swift:37-48/:92/:103/:118；WEProject.swift:202-208/:250-262/:150-154/:300-307/:156-161 | JS 求值+超时退役/查表回退/旧版 string 迁移为 Mirage 编辑器侧实现（发现两处行号跨文件错挂已订正）；我方受限文法解析器+直接 humanize 结构不同、无相悖断言 | 高 |
| property-9 | mirage-specific（表面冲突不成立） | `SceneUniformBinder.cpp:20-30/569-584/599-607`（AverageResample64 均值投影 + std140 16 字节打包） | 我方 forensics:606 是三层断言（官方算子未钉死/峰值仅推断性旁证/黑盒实验唯一定案），Mirage 均值选择不进入其论据域且恰为"均值也是一种存活实现"的反向旁证；17f34bac 峰值项目策略不受影响，不回改；黑盒柱高比实验仍必须执行 | 高 |

### 5. camera 域（10 条）

| 编号 | 裁决 | Mirage 证据行号（@da4fa7b3） | 我方文档核对结论 | 置信度 |
|---|---|---|---|---|
| camera-0 | mirage-specific | `SceneUniformBinder.cpp:271-284/34-78`；SceneUniformBinder.cppm:89/:115/:125-128；grep official=0 | 我方 :349/:351/:527 已双向记录"Mirage 查表+beat 插值 vs 官方单相位解析求值"（forensics:379 官方定案）相悖；隔离即可，无需修正 | 高 |
| camera-1 | gap（行号订正+细节增量） | `SceneUniformBinder.cpp:105-123`（MouseInput）/:80-101（FrameBegin）/:92-94（NaN guard）；SceneUniformBinder.cppm:118-121 | 我方 :346/:351、runtime-input-property-coverage.md:155、runtime-systems-reference.md:29 一致；:343 引用区间 :262-333 已随 revision 漂移为 shake 区间，已订正 §9.4 为 :80-123 并补 MouseInput 实时回退句；delay 平滑/NaN guard 既有断言不变 | 高 |
| camera-2 | corroborated | `SceneUniformBinder.cpp:307-341/270-285/335` | 我方 :347-348/:351 与 forensics:375 同口径互证；Mirage 读 base camera 正是我方已显式标注的官方差异点（官方读 shake 后 working camera XY） | 高 |
| camera-3 | gap | `SceneUniformBinder.cpp:433-441/152/96-100/320-338`；`SemanticTextures.cppm:176` | 我方全 docs 无 PARALLAXPOSITION uniform 条目；现役实现代数等价（SceneResolvedMaterialUniformEncoder.swift:87-95 等）；uniform 通路语义已扩写 §7.4；runtime-evidence-index.md:1958 句尾补注见清单②-12 | 高 |
| camera-4 | gap | `Visibility.cppm:8-58`；`World.cpp:1087-1126/1135-1155/1206-1211/1238-1249/1251-1264`；`WallpaperEngineRuntime.cpp:819-824/843-844/1346-1348`；ScriptRuntime.cpp:4315；Node.cpp 82 行零命中 | 我方 §11.6 仅结论级记载；判定链（纯函数解析/四类消费入口/pending→Commit 顺序/用户驱动 vs 脚本 tick 区分/light 只改 runtimeVisible）已补入 §11.6 | 高 |
| camera-5 | corroborated（引用补强+机制订正） | `World.cpp:1070-1085/1112-1124`；`SceneRenderPlanner.cpp:453/462/534-560`；SemanticTextures.cppm:48 | 我方 :216/:476/P1:581 三处一致互证；发现"被采样隐藏层不进集合"转述不准确——隐藏层无论是否被采样都进 visibility_elidable、由消费端 !linked 守卫保证不消除，已按准确机制书写进 §11.6；条件改名 copy 属 Mirage 特有不入合同 | 高 |
| camera-6 | gap | `WRDesktopInputForwarder.mm:5-8/39-52/90-111/115-138/140-158/162-209`；`WebRendererEngine.mm:494-508`（__wr_dispatchMouse :498） | 我方第 10 章零记载且产品有 +InputForwarding 三文件同构对应（非 Mirage 孤立分支）；已补第 10 章职责分层对照；60Hz/<5px 等数值细节不入合同 | 高 |
| camera-7 | corroborated | `MacDesktopHost.mm:527-568/662-678/665-671/346-370/634` | 我方 §10.1:355-359 一致且对 v1.0.3 快照行号自洽（:287-327/:377-413/:394），漂移属跨 revision 坐标系差异且被文档自我声明覆盖；复核括注已补 §10.1，input_hz/240 等数值不单独入条目 | 高 |
| camera-8 | gap | `DisplayRegistry.swift:50-52/58-75/137-160/162-169`；`MacDesktopHost.mm:56/280-284/346-370/530-555/596-610`；`WallpaperViewModel.swift:68/158-159/328-341` | 我方 §12.1 零记载、多屏同为开放边界（coverage-ledger.md:396/:1050、forensics:646）；职责切分对照已补 §12.1；DisplayKey 派生格式为 Mirage 细节（亦归档于清单②-13）；发现行号 ±5 内偏移已按实测记录 | 高 |
| camera-9 | corroborated | `WallpaperEngineRuntime.cpp:778-795/798-816/840-841/1343-1344`；SceneUniformBinder.cppm:118-121 | 我方 runtime-input-property-coverage.md §3 表八字段与 Mirage delay clamp≥0 直接互证；"每帧 live property 更新"措辞已订正为"运行时 live property 消息路径"；两入口调用点属 Mirage 消息架构内部实现 | 高 |

### 6. modules 域（10 条）

| 编号 | 裁决 | Mirage 证据行号（@da4fa7b3） | 我方文档核对结论 | 置信度 |
|---|---|---|---|---|
| modules-0 | corroborated（可补强引用） | RendererController.swift:23-26；ControlChannel.h:10/:20-23；ControlChannel.cpp:84-89；GlobalSettingsService.swift:330-878 | 我方 runtime-as-built-map.md:102（不变量 16）同构且更严（明文禁止 Host 反向监听）；对照引用挂引见清单②-14 | 高 |
| modules-1 | mirage-specific | SceneRenderer/Tools/SceneWallpaper、WebRenderer/Tools/WebWallpaper、VideoRenderer/Tools/VideoWallpaper 各自 CMakeLists；RendererController.swift:745-1041 | 进程编排不在参考文档 §1 范围声明内；我方 daemon 合同 §2 已显式裁决不采用独立 tool target（单二进制 daemon 模式），无相悖断言 | 高 |
| modules-2 | mirage-specific | RendererController.swift:511-521/957-958/998-1000/1336-1363/1389-1432/1434-1473；VideoWallpaper.mm:351-439 | 四处同构互证（newer-wins 世代/首帧 present 门/事件身份过滤/失败保留旧输出）我方已有显式记载（daemon-contract:46/:61/:78/:105）；九相位进程级事务是 per-display 进程模型派生物，我方单 daemon 多 surface 为显式裁决 | 高 |
| modules-3 | gap（未定义面，待收编需 owner 裁决） | VideoWallpaper.mm:39-81（MirageParentWatchdogMain：EVFILT_PROC/NOTE_EXIT + getppid 轮询兜底）/:83-156（stdout 非阻塞 + 事件行 PIPE_BUF/256 字节钳制） | 我方生命周期合同只有 client→daemon 单向职责（daemon-contract:77/:105），daemon→client 反方向（父死自终）与事件行分帧完整性两处未定义；产品代码 grep getppid/EVFILT/NOTE_EXIT=0。见清单②-15（不引入数值） | 高 |
| modules-4 | mirage-specific | VideoRendererEngine.mm:499-544；VRTranscoder.h:14-18/:24-26；VRTranscoder.mm:399/673/686-693；RendererController.swift:596-613/1257/1268 | 转码职责在我方产品不存在（grep=0），非记载缺失；我方失败路径职责结构同构（daemon 判定报告/App 投影）；VP9/AV1 兼容若立项属能力级改动须先过设计门 | 高 |
| modules-5 | mirage-specific | RendererController.swift:615-621/802-806/845-851/977-978；WallpaperViewModel.swift:116/270-276 | spawn 点复核与 Mirage 独立 WebWallpaper 进程架构绑定；我方 App 内宿主无 spawn 动作，以受控 scheme+双凭据+frame 门约束同一风险；"第三方代码执行前用户确认"若认定必需属能力级改动走设计门 | 高 |
| modules-6 | gap（待收编，命中设计门③） | WebRendererEngine.h:11-23/:33；WebRendererEngine.mm:699/541-552/806-808 | 我方管住"页面从哪加载"（current-state.md:46）与"主框架去哪"（:75），页面脚本出口流量（fetch/XHR/WebSocket/子资源）无宿主级策略，现状仅由 :86 §4 间接覆盖；egress 命中设计门③须按设计门定案。见清单②-16 | 高 |
| modules-7 | gap | WRURLSchemeHandler.h:8-19；WebRendererEngine.h:38-60；WRAudioTap.h:8-14；WebRendererEngine.mm:194-200/340/346/915/1130/1145-1166/1111-1118 | 我方 Web renderer 对照空白而产品有三职责同构对应（current-state.md:18/41/46、runtime-as-built-map.md 不变量 18、SystemAudioSpectrumService.swift）；三维度对照已补参考文档第 10 章；__wr_* 函数名/30Hz/128-float 等按隔离附注不进条目 | 高 |
| modules-8 | corroborated（行级细节归档） | SteamService/Program.cs:45-92；Protocol.cs:26-58；SteamServiceManager.swift:31-32/186-188/215-216/226/238-240/349-352；SteamWebAPI.swift:12-19/33-41 | 我方 scene-steamkit-migration-plan.md:66/:68/:75/:111 完全同构互证；:501/:532 已有概括层参考记载（"零记载"表述过宽已修正）；迁移计划 :47/:269/:278 引用的 SteamService/Program.cs 是我方仓库自有 helper，防混淆。行级细节归档见清单②-17 | 高 |
| modules-9 | mirage-specific | SteamWebAPI.swift:10-41；Mirage-Wallpaper-Info.plist:5；.github/workflows/build-macos.yml:136 | 我方 :121 目标合同+SK0 探针（:551 该路由禁用）不被第三方结构证伪；Mirage 内置 key 恰印证"该路由需 key"事实；路由选择为已裁决设计差异；镜像端点中转风险支持我方立场 | 高 |

计数核对：gap 24 条（render-0/1/2/3/5/6/9、particle-1、clock-0/1/3/4、property-1/2/5/6、camera-1/3/4/6/8、modules-3/6/7）、corroborated 17 条（render-4、particle-0/2/3/5/6/7/8、clock-2/5、property-3、camera-2/5/7/9、modules-0/8）、mirage-specific 18 条（render-7/8、particle-4/9、clock-6/7/8、property-0/4/7/8/9、camera-0、modules-1/2/4/5/9），合计 59 条。

## 二、待 Scene 会话收编清单

拟落点不在本次修订白名单内、或涉官方语义升级的高置信条目。均须由 Scene 会话按目标文档自身格式**收敛式**登记（替换/扩充既有条款，不新开章节），新增内容标 `third-party-reference-pattern` 与钉定 revision，官方语义升级须经 official-client-behavior-research-workflow 定案。

| # | 来源 | 内容 | 建议落点 | 约束 |
|---|---|---|---|---|
| 1 | render-0 官方语义面 | WE 资产引用的 `_rt_` 命名空间全集（14 前缀，含 `_rt_EightBuffer` 非 EightCompoBuffer 的命名事实）作为系统资源身份一次收编；历史审计 688 行"不应作为普通相对路径打开"语义升级现役条文 | scene-format-and-render-graph.md §5.3 既有资源辨析清单（:180 所在列表） | sr 自造名（effect_pingpong_a/b、bloom_mip、_rt_default）仅作 Mirage 隔离记录，不入该清单；官方行为规格须经行为研究工作流定案 |
| 2 | render-0 尾注 | g_Texture0..12 上界与 MipMapInfo 伴随家族（我方现记载上界 8、缺 MipMapInfo） | shader-prelude-and-backend-abstraction.md | 与 shader uniform 清单职责对应；不与本表其他条目合并 |
| 3 | render-9 | 官方 g_Texture3 hidden uniform 默认绑定 `_rt_MipMappedFrameBuffer` 的生产职责（mip 链快照）+"无消费者不生产" | coverage/render-graph 检查清单 | 官方证据为 assets/shaders 格式 metadata 注释；属职责分层/顺序范畴 |
| 4 | render-2 消歧 | render-graph-shader-coverage.md:235 与 coverage-ledger.md:918 的 `_rt_FullCompoBuffer1/2` 为我方 fixture 自有命名、与 WE/Mirage 前缀语义无关 | 两文件相应证据条目内消歧说明 | 消歧不改写既有证据、不追加新节 |
| 5 | particle-1 | 对象级粒子播放门（play/pause/stayPaused/isPlaying 四回调、reset_sequence 触发模拟时间/trail 累积器/slot 归零并 Refresh、play 为重置非续播、child 共享 root playback_state、playing=false 时 Tick early-return 且 child 传 dt=0） | particle-component-coverage.md G18:160/X10:375 边界注记 | 标 Mirage 单源不升格（无官方对照）；我方 SceneParticlePlaybackState 同名异义须注明防误判已覆盖 |
| 6 | clock-4 | 暂停时帧与音频两条生命周期线的时序分层：帧停同步立即（fade 期间无人驱动帧）vs 音频暂停延迟 fade+generation 门作废 | coverage-ledger 时钟/生命周期条目或 runtime-architecture.md:491"由既有行为合同决定"空位 | 与 commandGeneration 迟到事件语义互引（coverage-ledger.md:222/:224）；消息结构/detached 线程/fade_ms/fps>=5 数值不入合同 |
| 7 | clock-5 | Mirage RendererController.swift@da4fa7b3 九相位七段行号锚点（511-521/1300/1336-1363/1365-1374/1404-1432/1459-1473/1486-1516/1573-1593） | scene-launch-responsiveness-contract.md :143/:152 挂引 | 仅引用级补强，不改条款语义；枚举命名不复制 |
| 8 | property-1 | scenerenderer.scheme_color→schemecolor key 归一（唯一规则）+显式 canonical 键终胜/归一键间首键胜出 | runtime-input-property-coverage.md 5.2 schemecolor 行缺口栏 | 标无官方对照单源（Mirage 全仓库无生产者）；Normalize 实现与 wire 描述符属 mirage-specific 不入 |
| 9 | property-2 | Parse 前注入用户值供可见性剪枝 + 首图前逐键应用保持首图单次构建 | runtime-input-property-coverage.md §1 固定求值合同处补顺序事实 | 我方 owner 为 SceneDocument.swift:111-116；可挂 scene-format-and-render-graph.md:115 官方"首次加载调用一次" |
| 10 | property-3 半条 | R04:256/R11:263 补 Mirage 缺省 subdivision=1/segments 4 互证引用 | particle-component-coverage.md R04/R11 | 保持 R04"按固定官方客户端字段准备为 1"谨慎措辞，不升级 parity 宣称 |
| 11 | property-6 | objects[i].visible 字段双职责：布尔初值（含 object.value-boolean）+ user 绑定载体（string 简式/{name,condition}）；text/pointsize/color/alpha 各字段独立 wrapper | runtime-input-property-coverage.md §2 :129 合并记载 | int 范围门不写入（算法细节）；object.value 数值形态我方保持默认、待官方正例裁决，不在条目内断言 |
| 12 | camera-3 半条 | runtime-evidence-index.md:1958 句尾补"该值经 ×mouseinfluence、NDC→0..1 变换后作为作者 uniform g_ParallaxPosition 上传" | runtime-evidence-index.md:1958 | 收敛式补注，不新增节 |
| 13 | camera-8 细节 | DisplayKey 派生串格式（uuid:/vms:/idx: 前缀、#index 后缀）归档——Mirage 特有实现细节非官方规则 | 已在参考文档 §12.1 标注；多屏立项（coverage-ledger.md:396/:1050）时可回查本文与该标注 | 不构成对我方现有合同的修正 |
| 14 | modules-0 | app-owns-policy 外部互证对照引用（RendererController.swift:23-26、ControlChannel.h:20-23） | runtime-as-built-map.md 不变量 16 处 | 注明同构实现把五类策略全收归主 App、渲染进程只收 run/throttle/pause 结果命令 |
| 15 | modules-3 | (a) 父进程死亡（含主 App 被强杀）时 daemon 侧应对职责归属未定义，需裁决 daemon 自守护或依赖 transport 生命周期；(b) daemon→client 事件写入的行分帧完整性保证（超限行为）未定义，需与 DaemonNewlineFrameBuffer owner 一并裁决 | scene-runtime-daemon-contract.md §4"崩溃/断连"既有条目内收敛补充 | **需 owner 裁决**；不引入 PIPE_BUF/256 字节/wedge 2 秒等数值作为合同 |
| 16 | modules-6 | Web 页面出口流量（fetch/XHR/WebSocket/子资源到任意主机）当前无宿主级策略——受控 scheme/loopback 凭据与主框架导航合同不约束页面脚本自身远程访问 | docs/web/current-state.md:86 §4 条目内精确化 | egress 命中设计门③（用户数据风险），须按设计门定案后方可实施；Mirage 三档机制仅隔离参考 |
| 17 | modules-8 | SteamService 行级细节归档：hello 自报 version/maxConcurrentDownloads=3、spawn 三管道、Keychain token/guardData、内置 WebAPI key 与镜像端点属 Mirage 特有 | scene-steamkit-migration-plan.md :66/:68/:75/:111 同构处如需引用 | 迁移计划 :47/:269/:278 引用的 SteamService/Program.cs 是我方仓库自有 helper，引用时防与 Mirage 侧同名混淆 |

## 三、mirage-specific 隔离记录归档

以下 18 条按裁决纪律隔离记录、不入我方合同；核心理由见第一节对应行。

- **render-7**：std140 packoffset/cbuffer 装配与矩阵 major 选择，绑定 Mirage HLSL 前端+glslang HLSL 源路径与 MoltenVK/SPIRV-Cross 的工程 workaround。
- **render-8**：PipelineKeyWriter 三类 GPU 资源缓存键字节格式（类型 tag/FNV-1a/排序/版本 tag），纯 Vulkan 自有工程结构、官方对照空串。
- **particle-4**：child/CP eventfollow 的 particle_idx 簿记、压缩死亡迁移、spawn_sequence→CP 映射、type 自由字符串不校验；动机自述为保持 Mirage 自身重构前行为，不得用于关闭 eventfollow/CP identity 待验项。
- **particle-9**：我方发射图 alpha 加权与半透明条件排序在 Mirage 无互证对象（sort 恒 false、无深度排序、仅两种 emitter）。
- **clock-6**：visibility blocker 与 desired-state 两段重放，是"每显示器一进程+IPC 指令流"的派生物；我方以属性快照 identity/newer-wins 结构性覆盖。
- **clock-7**：切换相位超时数值预算表（75/300/3/8s），我方有先例规则排除同类客户端常量。
- **clock-8**：PlaylistRotator 播放意图门控与切换锚点，我方无 playlist 轮换功能。
- **property-0**：wire 字符串二次 JSON 解析/typed patch/无 schema 包 descriptor，Mirage 自有 App↔renderer 协议。
- **property-4**：prepared-私有 scene 直应用双路径，双消息循环特有窗口绕行。
- **property-7**：渲染侧可见性窄标量相等含 bool↔"1"/"0" 交叉匹配，与我方严格相等属同主题不同宽窄谓词。
- **property-8**：App 编辑器侧 JS 求值（超时/退役/缓存）、排序过滤、查表+humanize 回退、旧版 string 迁移。
- **property-9**：64→16/32/64 档均值投影与 std140 打包；反向旁证价值已记录，不改变我方峰值策略与黑盒定案途径。
- **camera-0**：shake 8 方向×3 系数查表+beat smoothstep 插值+线性 speed×2，与官方 2.8.42 单相位解析求值定案明确不同族。
- **modules-1**：三类壁纸独立 CMake 工具可执行+devFallback+VK_ICD 注入，我方已裁决单二进制 daemon 反路线。
- **modules-2**：每显示器一渲染进程九相位事务+window-server 双向确认协议，per-display 进程模型派生物。
- **modules-4**：视频转码决策/执行在渲染器进程（libav+AVAssetWriter、临时文件验证、原子替换），我方无转码路径。
- **modules-5**：Web 信任门唯一 spawn 点进程级复核，绑定独立 WebWallpaper 进程架构。
- **modules-9**：Steam Web API 浏览查询 App 内单例（内置 key/官方-镜像端点切换），我方合同显式弃用该路由。

## 四、corroborated 证据行号归档

以下 17 条为我方已有记载与 Mirage 行为互证加强的条目；证据行号（@da4fa7b3）归档备查，多数无需我方文档改动，引用级补强已按需落白名单文档或列入清单二。

- **render-4**：`World.cpp:1443-1453/1422-1437`、`SceneRenderPlanner.cpp:196/213-221` ↔ 我方参考文档 :216/:298/:476。
- **particle-0**：`WallpaperEngineRuntime.cpp:1101-1116/1232`→`ParticleSystem.cpp:235/510-513/583-589`→`ParticleEmitter.cpp:210-213` ↔ G18:160/X10:375/coverage-ledger:1051。
- **particle-2**：FieldBindingSpec.cpp:114-160、`SceneCompiler.cpp:4189/4191`、`World.cpp:833-839` ↔ runtime-input-property-coverage.md:220/:224。
- **particle-3**：ParticleLayerSpec.cppm:41-46、ParticleLayerSpec.cpp:57-65 ↔ 参考文档 :453、R04:256/R11:263。
- **particle-5**：`ParticleEmitter.cpp:106-128`、`World.cppm:2908`、`WallpaperEngineRuntime.cpp:1174-1205` ↔ 参考文档 :408/:410、coverage-ledger:296。
- **particle-6**：`ParticleEmitter.cpp:22-57`、`ParticleSystem.cpp:510-513` ↔ IV05:318/E07:174/E08:175/E09:176/E12:178-179。
- **particle-7**：`World.cppm:2115-2148`、`ParticleSystem.cpp:53-56/477-503` ↔ R04:256/G03:145/X09:374。
- **particle-8**：`ParticleCompiler.cpp:502-542`、`World.cppm:1976-2028` ↔ 参考文档 :444（对 f504958 与 da4fa7b 两 revision 均成立）。
- **clock-2**：`WallpaperEngineRuntime.cpp:1133/1223/1232`、`World.cppm:2929-2933` ↔ 参考文档 :405、runtime-systems-reference.md:29/:485。
- **clock-5**：RendererController.swift:511-521 等七段 ↔ scene-launch-responsiveness-contract.md:20/:143/:152。
- **property-3**：`WallpaperEngineRuntime.cpp:1330-1348/826-844/1351-1363` ↔ 参考文档 §4.1/:116/:125/:412。
- **camera-2**：`SceneUniformBinder.cpp:307-341` ↔ 参考文档 :347-348/:351、forensics:375。
- **camera-5**：`World.cpp:1070-1124`、`SceneRenderPlanner.cpp:453/462/534-560` ↔ 参考文档 :216/:476/P1:581。
- **camera-7**：`MacDesktopHost.mm:527-568/662-678/346-370` ↔ 参考文档 §10.1:355-359（v1.0.3 行号自洽）。
- **camera-9**：`WallpaperEngineRuntime.cpp:778-816/1343-1344`、SceneUniformBinder.cppm:118-121 ↔ runtime-input-property-coverage.md §3 表。
- **modules-0**：RendererController.swift:23-26、ControlChannel.h:20-23 ↔ runtime-as-built-map.md:102 不变量 16。
- **modules-8**：SteamService/Program.cs:45-92、Protocol.cs:26-58、SteamServiceManager.swift:186-352 ↔ scene-steamkit-migration-plan.md:66/:68/:75/:111/:501/:532。

---

本文由 2026-10-01 资料库修订批生成；仅汇总当时六域侦察与核实结论，不构成现役合同，也不授权任何实现批次。后续 revision 变化时不得把本文行号静默套用，须按固定 revision 重新取证。
