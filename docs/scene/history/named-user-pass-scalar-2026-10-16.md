<!-- document-role: historical-evidence -->

# Named-user pass scalar：唯一脚本值与当前属性输入

> **历史证据 — 非现役入口**。含2026-10-16首片及2026-10-30后继。本记录覆盖effect pass有限Number的named输入；当前合同归[D4](../roadmap/batch2/script-component-api-design.md#named-user-pass-scalar)，状态归[输入覆盖](../capabilities/runtime-input-property-coverage.md)，选序归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

## 通用修复

原 binding reader 只容许 named-user Vec3，真实 scalar 在读取脚本前被 conflictingSources 丢弃；Scalar projection 和 material classifier 后续也不准入。现三处同一链补接 exact scalar：user 是原 property preliminary snapshot 的输入，Scalar VM 是唯一脚本值 producer，Program 只登记 sceneScript contributor。raw seed 保留在原 binding，resolved 当前值可与 seed 不同，身份仍核 object/effect/pass/path/source/user。无新 VM、缓存、frame writer、解析或 compositor。

无 animation 的 exact Number 首片不扩 scriptproperties 混合、数值 String、Bool、Vec2 或其他 host。缺失/错误/重复属性由原 compiler 诊断、不给有效 user instruction，仍可用原 authored/current fallback；不能把 owner 存在说成属性热改有效。无 exact VM target proof 保留 unproven attachment。

## 真实运行

原2932157836包SHA `59a9dae2a15ac582cd5be8c68249b95a7415882afe3bb1efe9504f2b09759cb9`。元数据与既有解包manifest核同：299/effect4/descriptor337/pass0/id217/node5 的 `speed → g_Speed`，slider范围[-1,1]、默认-0.25。旧最终拒绝为uniformScriptAttachmentUnproven；本片不放宽颜色域或忽略附件。

隔离原包使用自有非对称媒体封面与正常playback/title事件，未改作者源码、几何或显隐。启动覆盖值0.5真实进入Scalar callback；同窗口三次0→-0.5→0.5均accepted且surface/window身份保持，propertyInputApplied分别输出同值。53条scene-script exact-byte uniform消费涵盖三值；frame0/1目标均1材质、0拒绝、GPU completed、publication更新及compositorConsumed=true。实际窗口看见封面两个不同时刻方向改变；未宣称官方速度/方向数值parity。

本轮原生startupElapsedMS=32610.838、总46.190s、exit0、输入稳定，surfaces1→0且gpuDrained=true。这些时长只标身份与有界运行，不与旧不同状态启动比较性能。其他blur、文字、封面样式与整景问题仍保留；live系统媒体及普通daemon/原生面板完整流程未验。

## 验证与保留

Debug build22.851s、4278输入无漂移，Developer ID签名deep/strict通过；三处产品diff独立静态GO。最近Scalar VM 32/32与Material Template 7/7通过，最终输入无漂移；三组改名/等价式用真实parser→property state→VM验证当前输入变换，分离raw seed、default与prepared current，锁失败回退userProperty及唯一writer。Bool/数值String的wrapper输入仍拒绝，原VM输出数值转换保留；缺字段fixture与两次错误测试预期的失败收据保留，仅补相应fixture/预期，未为测试改产品。独立3743305891原样ready5.392s、总13.502s、exit0、输入稳定且GPU排空；实际窗口保人物/星体、日期时钟与频谱，仅作未参与修法的回归观察，不是完整parity。

证据目录 `.artifacts/tmp/named-user-scalar-pass-20261016/` 保存产品冻结、build/运行计划、测试收据、中性投影和必要原字节PNG；全局evidence预算已满，未重复promote或删除未知证据。原件只读，本轮临时执行环境在退出后清理，连续缓存仍只留原DerivedData。Windows VM按用户要求保持运行。

<a id="named-input-current-20261030"></a>
## 独立参数、current反馈与实际热更输入（2026-10-30）

真实3587571382的layer450/effect451/pass452把Number opacity同时绑定外层`newproperty4`与独立scriptproperties；它们分别是callback值输入和配置，不是竞争输出。原Parser/Scalar投影的三键限制先丢owner，Material又重复准入。现由原HostContract统一wrapper形状，保完整owner/path/source/user/definition对应；Material只消费准备期exact typed target，退出第二份wrapper规则。该资格不是VM执行成功证明，返回/失败与uniform bytes仍由原消费者裁决。

固定官方2.8.0.42（exe SHA `DAAC1EA7C991207FDB6098616757E3DAE393850F6862845DB55D04921B6BDA07`）自有八格板：无named、named、named+独立参数均持续累计到`.8`；重复外层输入应为`.25`，重复seed应为`.15`。两张完整四marker图按预注册ROI/ICC转sRGB后，named两路与同帧`.8`参考误差均0，constant参数与`.7`参考亦一致，身份/包内与loose源码独审通过。首载体HLSL标量splat失败，第二载体漏导出scriptProperties导致ReferenceError，二者失格保留；事前修订协议的V3才资格。不由此认热改优先级、init精确顺序、Vec3或其他host官方时序。

本机四入口候选仍把稳定user每帧盖过current，实际uniform及画面为`.25`。后继复用EvaluationTransaction已提交sceneScript值：material沿用callback current，Timeline仍优先，其他target保原user规则；LiveConsumers在实际outer typed输入改变且成功接受属性事务后，用原scoped快照重新播种，即时/deferred共用，不新建状态。真实热改随后又揭露outer未登记live输入：原Scalar/Vector准备入口现把已绑定值登记入原VM consumer集合，保nested独立target。旧CPU夹具人工补target只能证明数学，已删除人工授权并保旧收据边界；不在Host另造放行或第二uniform writer。

最终Debug基于`0776a9aea`加9产品文件，29.888s、签名0、输入无漂移；App `e8dd4204…56cb`/dylib `b87062ed…713e6`。自有原板旧named两路实图64灰阶/`.25`，最终204/`.8`；同窗drive热改`.4`后actual uniform `.45→.5→.8`，窗口不换。原358同源PCM由无音条/局部passthrough变为左下粉色音条；368条u_BarOpacity exact-byte消费记录由0推进`.94`，frame104 `.92408`→热改后frame105 `.42180`再趋近`.94`；静音27条全0且实图无音条。同run首帧0/1有GPU/可见发布/终端消费/次帧收据，正opacity自frame6起由同Program消费日志及最终实图关联；不冒同帧详细GPU证明。audio/silence分别冷启，未测同窗音频关闭后的fade曲线。独立3743305891人物、星球、时钟与频谱实图保持，其scalar binding=0，仅验粗构图，不作本能力独立consumer验证；最终四run FAIL[]、surface1→0/GPU排空。官方目录截图只支持音条构成，音源/viewport/phase不同，不比幅度和整景。

最近真实VM改名/等价式、外/内独立属性、返回转换与失败/Timeline邻例通过；修正夹具后Scalar/Vec3仅用实际live集合热改，3方法67.146s；transaction真实carry/Timeline/其他host/单target reseed/peer与未提交隔离1方法1.400s；Material最近2方法26断言通过，原独立assetVFSBoundaries=false不掩盖、不认全套通过。静态产品与官方测量独审GO，最终原图/日志另由独立Max只读审查GO。产品净−4行，无新VM/owner/缓存/帧解析；测试净增用于实际链，文档替换旧政策。无性能收益、全样本/整景、原生面板、普通daemon、HDR、多屏与官方同声源淡入淡出parity结论。

必要原图、官方自有板/失格载体、红绿/热改/字节日志、测试/构建身份归本机正式包`.artifacts/scene-evidence/runs/named-material-script-inputs-20261030/metadata/samples/0/runtime_evidence.zip`（25,790,922B、187成员、SHA `aa40cb09…082b2`，普通14天）；只留一份连续Debug缓存`.build-cache/scene-gravity-20261028`，临时App/HOME/样本与重试构建当轮清理。VM/官方主客户端保留运行。
