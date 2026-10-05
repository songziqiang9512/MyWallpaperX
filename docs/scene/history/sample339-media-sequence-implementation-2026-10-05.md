<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# 339 受控媒体序列与文字速度（2026-10-05）

> **历史证据 — 非现役入口**。当前证据见[运行摘要](../capabilities/runtime-evidence-current.md)，未完成项由[RF05卡](../roadmap/batch2/reference-evidence-implementation-cards.md)接管。

基线`001b06d3`。原Debug封面序列沿同一入口新增properties、playbackState、timeline；每项恰一个动作，1…8项、delay 0.1…60秒，字段与原收件箱同界。相同delay按数组顺序串行调用独立通道API，不引入原子媒体会话、产品producer或新owner；封面clear只清封面。

完整实际Swift入口与原Inbox的9个CPU行为方法通过，旧入口同3个正例失败；原Inbox与参数邻接3方法通过。candidate dylib SHA256 `f19bf08169c17debc5931af85769b6da82b942b4403a0df87295c09a593eb8d6`绑定media-cycle及文字快/慢三轮，均退出0、gpuDrained=true。

media-cycle八项均accepted=true。series0005为红封面与Alpha；显式空title/artist、state 0和封面clear后，series0010组及标题消失；后续Beta/state 1使series0017出现默认MF封面与Beta。该轮没有timeline重置，不把封面clear解释为全session清除。

文字对照使用相同3秒换曲事件与timeline position42/duration180，快/慢仅newproperty31为.01/.1；series0005慢组只到ABCDEFGH，快组出现更多字符，证明该输入下过渡速度响应，不推断所有文本长度或时间公式。

先前options-text/visual各八步接受，保存字体1/21、文字显隐/颜色/阴影、12h时钟/日期及背景/音频等有界画面；两轮App仍是前批`8a3882f3…`。36/39实际material GPU、13直接compositor属于options-visual既有触达，不计本次增长或正确率；样本粗估仍60–70%/低置信。

实际系统媒体接入与完整视觉仍开放。独立MediaRemote probe返回空，只记录当次结果，不判定原因或所有player能力；默认产品未接入该private API。设置UI、真实player事件、媒体来源切换、物理交互及官方逐像素一致性未由本记录验收。

主包`.artifacts/scene-evidence/runs/sample339-media-sequence-20261005/final/samples/3395777145/runtime_evidence.zip`，SHA256 `96714930662d7b5e3e20bd14aac09aa14ae563fe37b1fa1452ed55187f181154`，14,824,145 bytes/62 entries。广域及结构门保留范围外失败，见归档日志，不作全绿声明；基线归因以冻结独审为准。
