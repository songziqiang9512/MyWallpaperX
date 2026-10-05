<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# 媒体封面五色输入（2026-10-05）

> **历史证据 — 非现役入口**。职责与未完成验收见[媒体输入设计](../roadmap/batch2/system-media-input-design.md)，当前选题见[RF05卡](../roadmap/batch2/reference-evidence-implementation-cards.md)。

基线 `390afbac`。真实339系统封面已显示，但原producer只提交图片，五色缺失由事件桥转成零。新增无状态有界提色值，System后台decoder仅处理新字节，Music后台事务新图提色并复用原缓存；producer把颜色与同来源/曲目的封面绑定，Inbox同锁原子发布。显式颜色输入、纹理decode/upload及唯一compositor不变，普通帧不提色。

公开MediaThumbnailEvent要求归一化RGB、文字足够对比与黑白最高对比色，未公布排序或提取算法。项目独立32px sRGB、alpha加权16级色桶及4.5:1文字门详见设计；不宣称官方调色板逐值一致。坏图/越界局部清色，全透明合法图用黑主色和白文字/对比色。

Swift6/MainActor环境下，Palette8、Music/System来源8、Provider/Inbox5、原纹理store2方法通过。真实自有PNG覆盖原色、比例、半透明、透明、sRGB转换、预算与对比度；来源测试证明新图进入Snapshot、缓存命中不重提色、错来源/曲不复用、坏图仍保metadata；原子竞态检查图片、五色及其他通道同代。

最终Debug dylib SHA256 `7d81b5e662fda517580424b72e58fb14f63a8cd39f48918ac399c0dbc6113f8f`。本轮最初发现旧staged App的glslang仍是adhoc签名，deep验签并不证明每个helper同Team；该次before不作为对照。随后复制旧源baseline并将全部Helpers签为同一Developer ID Team，再以同规则签新候选，两轮没有helperSignatureInvalid，所有helper身份单独保存。

baseline与candidate的series0005均显示Write Your Name / Yelawolf同封面：旧版右背景灰白、事件五色0；新版右背景红棕，primary约(0.01668,0.00613,0.00928)、secondary约(0.46296,0.16029,0.09825)、text/highContrast白。505及549颜色参数由原VM事件进入typed uniform，graph完成并由原合成链呈现。两轮均27个实际material GPU身份、12个直接终端消费、0 graph执行失败，退出0/gpuDrained=true；不计效果触达增长。截图与typed链证明确实颜色联动，不等于官方色值或完整视觉验收。

两轮仍使用audio fixture。radial_blur的varyingUnsupported为338#343固定visible=false的准备诊断，未计为执行失败，也未由本批修复。真实音频、其余交互/可见组合及HDR仍开放；样本主观约70–75%/低置信，旧36/39触达不代表完整正确率。

本机证据 `.artifacts/scene-evidence/runs/media-artwork-palette-20261005/final/samples/3395777145/runtime_evidence.zip`，SHA256 `ea0bf993900ef1897143f0973e660c69391cdeabcfc89388b5e6dff11d54a010`，6000489 bytes。独立冻结产品审查无新P1/P2；布局、依赖、设计门通过，旧广域结构偏差未由本批修复。只保留当前候选、一份checkpoint缓存及持续样本副本/着色器缓存，清理已归档的旧候选与临时HOME。
