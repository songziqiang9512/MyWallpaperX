<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF11 shared HDR graph目标计费纠正（2026-10-02）

> **历史证据 — 非现役入口**。原设计决策见[窄设计](rf11-shared-graph-pair-budget-design-2026-10-02.md)，顺序由[RF11卡](../../scene/design/reference-evidence-implementation-cards.md#rf11-frame-target-budget)决定。本文只记录本批执行证据；稳定计费职责由[架构§3.3](../../scene/design/runtime-architecture.md#33-保留事务安全不扩大视觉失败半径)接管。

## 基线与首断点

基线`006390390bda2d4a5940aa242cc3f16ca734e684`。上一批[F3记录](d3-pbr-map-emission-implementation-2026-10-02.md)保留完整3662790108新旧App同预算失败：首次required805390384/budget794569728/residents29，后续required801766144/residents26，没有GPU完成帧或PNG，候选自行timeout并drain。输入与单surface配置、宿主显示环境相同；没有实测完整包drawable尺寸。该失败不是F3新增回归证明。

本批只读作者scene entry，SHA`faea17adcce6b09b40c1a722c08b53bc4f3588c3189873986c754517a9500cc5`，确认general.hdr=true。实际producer沿descriptor的rgba16f格式进入pool及shared target plan。首错是`SceneLayerGraphTargetPlan`总费用按实际槽格式计，shared排除部分却保留8位格式常量；allocator实际借用shared pair而不分配私有pair，pool还会按真实格式完整计费，因此graph私有费用含虚构重复量。不是把budget调小或猜测跨graph可随意复用得出的结论。

## 真实Swift红证

证据根`/private/tmp/mwx-rf11-target-budget/`，`red-source-manifest.json` SHA`045232927ccc518f9b3c7c259c957bcb0b13d0db9a251a0bcb77b083ddc628f6`冻结32个实际产品源码、harness与编译命令。初次沟通误报36个，独审按清单纠正为32；清单未追溯修改。探针为CPU值操作，没有创建设备或command buffer。

64×32、合法单pass、无作者FBO：

| 格式 | pair归属 | 实际graph resident | 独立期望 |
|---|---|---:|---:|
| SDR | owned | 16384 | 16384 |
| SDR | shared | 0 | 0 |
| HDR | owned | 32768 | 32768 |
| HDR | shared | 16384 | **0** |

`red-result.json` SHA`12f84435373baff0a6122b9356d53d08d9ebf7e325b1a5c3a8732205182b9c32`明确保留HDR shared项false。编译/探针退出0仅代表完成采样，不表示纠正门通过。

正式行为测试随后以`test-red.py`/`test-red-identity.json`冻结，`pool-red.log`为1方法失败、8个失败subcase（9.257s），覆盖两尺寸的HDR shared direct/r8/history及真实pool同/异尺寸准入。SDR、owned及少1 byte负控没有失败；这是实际产品编译后的行为红，不是编译或脚本错误。

## 设计释放与验证状态

独立设计审查ACCEPT绑定全文SHA`210c7c7d0f9bfa8bcee81ecc79324c2e9ffe5578aa7b05653a130c8f39c2f40d`；仅状态从待审改批准后的SHA`cdfcaa829406b7ec23d39291b81cdc3c914d1bb634f5321e0cd4e5748722e967`。精确释放一个产品文件`Rendering/Targets/SceneLayerGraphTargetPlan.swift`。无产品consumer的重复成本getter只有旧测试读取，随行为测试迁移删除；不为测试保留未用产品入口。

一个产品文件改为仅累加实际私有槽，并删除无产品调用的重复getter；无新增guard、owner或分配政策。首轮全pool模块28方法通过（9.751s）。补强测试v2因fixture调用旧clear helper标签编译失败、0方法/1ERROR；该记录保留，不归因产品。修正后的v3同28方法通过（9.325s）。独审要求补shared巨大pair在真实pool拒绝且factory零调用、pending成本拒绝：最终v4同28方法通过（9.966s），明确为API边界注入。重复运行不相加计数。

最终源码/测试清单`final-source/manifest.json` SHA`9e1d52aba1dd31833be451af1bf21b927fbd65a5db8e8670bada69149efb1d77`；产品SHA`6965933b3e2cccb12727473c6ede953053fc60cfbf2a3cd78503dd8e6c349bde`，测试SHA`0b68d2646035293b79398ce5b7378638f7e4168cf8dc2c95f512d469d0e95ff5`。Debug构建输入由`source-v1/manifest.json`冻结（SHA`b33e92d0acb8d06dc345382f52155745d9c5c3aab47760db16ed128f25dd4efb`）；v4仅增加测试，产品及构建依赖未变。

## 实际App与同输入回归

`source-v1.app`通过Debug构建及严格codesign验证。`app-prerun.json`在运行前冻结，`app-postrun.json`逐项复核不变：

| 工件 | SHA-256 |
|---|---|
| executable | `c7ea5b8664aaa96a759582403787d86f391328d81fb4860a19aeb008f807481f` |
| debug dylib | `b2443684fff624af154743c434316ac51bc5fb47dfa8e65ff3f2c76cbddd05b8` |
| metallib | `179deadfc387b3d310e1f50d43c69db0e3138a1ea41344847649143623d930b0` |

`whole-comparison.json`比对上一批失败输入：project SHA`516bf3721903ceb9ae25e5239274f789c1a5566c07f82c4d63dc0450ca65d1e9`、pkg SHA`06db4dc21ca78724f37e513776d0beb10ac587367897fab4051ead94dc1f3ec8`相同。runner仅改证据输出目录及App参数；保留单surface、首帧后6秒窗口和150秒外部上限。预算policy/pool产品源码未变、无override；成功路径没有另打印数值预算，不能假称重新测得该值。

原包847对象、344 image、70 effects于89.671s ready；surface帧0/1/2均GPU completed，58条graph publication/terminal compositor consumed/completed记录跨frame0/1，零budget-blocked，exit0且gpuDrained。两张3024×1964 PNG为作者“Live Solar System v4.0 / SYKM / 山雨客眠”开场字卡；root与实施者实际查看，字卡由ready到after变暗，84219个RGB字节变化。字卡ROI是运行后观察，不能冒充预先独立数值oracle。旧展示fixture的中心/greenPeer字段对完整场景不适用，原值保持，未改成虚假PASS。

这闭合本计费错误导致的首帧阻断及下一帧提交，不证明后续太阳系全景、全场效果正确、官方视觉parity、长时稳定或性能改善。慢准备另有边界，不能由一次89.671s推导性能结论。

## 门禁、移交与保留现场

pool最终28方法、target-table9方法、resident-budget3方法、额外pair-plan1方法通过；mapped effect graph/executor另17方法通过（77.273s）；共57个非重复方法，加独立pair-plan1方法。code-health、scene-defense、design-gate均exit0。文档门初跑25方法中1失败：新设计漏登记discovery.additionalPaths；补登记后25方法通过（1.964s），属于文档接入错误。退役时历史角色仍放design目录导致第二次文档门2失败，已按既有发现/索引合同迁移到history目录并同步导航、补齐历史声明，不改测试预期。最终文档门结果见`docs-final-v3.log`。

独立产品终审ACCEPT绑定最终源码与App身份，记录`product-review.md`。实际shared/owned与格式职责交稳定架构，窄设计归档、窄登记退役。D3整体设计仍在，下一批按RF10落实2D材料用户属性，再处理明确环境输入与阴影。三份受保护权威未改；并行`script/scene_source_layout.json`不属于本批、不暂存。

保留本批App、红证、错误fixture日志、冻结源码、原包输入身份及PNG，与F3/F2对照App一起供后继使用。共享DerivedData不清理，真实样本只读，进程已退出。未推送。
