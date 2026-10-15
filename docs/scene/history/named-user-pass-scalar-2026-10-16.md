<!-- document-role: historical-evidence -->

# Named-user pass scalar：唯一脚本值与当前属性输入

> **历史证据 — 非现役入口**。截止2026-10-16。本记录只覆盖 effect pass 的有限 Number `script/user/value`；当前合同归[D4](../roadmap/batch2/script-component-api-design.md#named-user-pass-scalar)，状态归[输入覆盖](../capabilities/runtime-input-property-coverage.md)，选序归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

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
