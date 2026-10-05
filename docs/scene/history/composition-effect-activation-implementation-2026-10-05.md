<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# Composition 初始关闭效果激活（2026-10-05）

> **历史证据 — 非现役入口**。目标见[D1设计](../roadmap/batch2/composition-render-target-design.md)，稳定职责见[运行架构§8.2](../architecture/runtime-architecture.md)，当前证据见[运行摘要](../capabilities/runtime-evidence-current.md)。

基线`83cfff0e`，真实3395777145的`crt`、`newproperty8`、`newproperty11`各单独live更新均被拒绝；启动前开启时，相同的278#284/322、338#341、392#499四个stage已能实际GPU执行。普通tint模式原本可热切，不计本批新增能力；首断点是utility composition的初始关闭effect未进入准备需求，不是新shader算法。

原standalone fullscreen inactive admission保留，新增SourceRoute与普通层级准入共同验证的无父子、无依赖、非passthrough root composition。复用原Program、stage activation passthrough、capture计划、typed snapshot与唯一compositor；运行更新不重编shader或重建graph。provider/named消费、父子及未登记真实child继续拒绝，script-owned也不绕utility依赖；真实Program准备失败不提供live effect consumer，整键仍要求所有消费者就绪。

旧产品新增CPU正例在copybackground true/false两route均失败，其他24方法及30个utility反例通过；修复后25 CPU与134相邻CPU通过。copybackground=false仅CPU准入证据，未作GPU或官方结果声明。

自有childless composition复用已有dim shader、冻结App/输入身份及Metal像素runner：effect false→true→false的背景RGB 255→128→255，后方绿peer不变；missing-fragment两次整键拒绝，白底与绿peer保留。两项GPU门通过，fixture只含自有model/shader/像素，不读官方私有实现。

最终App dylib SHA256 `8a3882f30c950b3874f32fa0e46975f45a8e9305911cb051f23b50065511bc0a`，Debug build成功。真实同序列旧options-live为29/39实际material GPU、12直接compositor；candidate-options退出0，36/39、13直接、零graph失败。actual须同run succeeded+completed+materialNodes>0，direct另须compositorConsumed；新增7个触达中核心新准入是278:0/1、338:1、392:1四effect，其余是整键解锁后已有背景/封面分支。392:3、338:2/4三个fixedfalse未执行。

四步live均accepted=true，同PID85626/window312477/runtime `e06e41ff-ff50-4bf1-bc61-08b45b765dd1`。ready→series0003出现CRT暗化颗粒，series0005背景绿，series0010恢复灰背景/亮度，波形与底条持续；after.png只属首更新后，不作最终恢复图。主包`.artifacts/scene-evidence/runs/composition-effect-activation-20261005/final/samples/3395777145/runtime_evidence.zip`，SHA256 `dddc61b58c48337512021535b9e7809ef2e073d14e8db6c531c97b50e118e18e`，13,062,746 bytes/80 entries。

未验nested group effect、dependency/provider effect激活、设置UI操作、物理多屏、copybackground=false GPU及官方逐像素一致性；执行计数不作正确率，样本粗估仍60–70%/低置信。后继转同样本媒体输入及剩余交互，RF05整卡仍开放，旧底部音频记录保持其冻结边界。
