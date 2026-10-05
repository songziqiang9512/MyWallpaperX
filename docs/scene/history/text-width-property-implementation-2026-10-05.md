<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# 文字宽度属性原位更新（2026-10-05）

> **历史证据 — 非现役入口**。现役能力见[运行输入属性](../capabilities/runtime-input-property-coverage.md)。

基线`0b0acaad`。真实3395777145的newproperty28/29各绑定两个文字对象的maxwidth；Host和动态文字store已有宽度consumer，raw binding parser/Program遗漏该字段，合法修改因此走rebuild。补齐现有typed target投影，复用原snapshot、每层后台raster、纹理/尺寸原子publication及唯一compositor；不扩font或limitwidth开关。仅固定limitwidth=true、无script/animation冲突的width wrapper；slider域、fallback需在现有1…16384预算内，默认值在slider域内，避免静态0无限宽被运行时夹成1。其余形态保留重建路径。

原件只读。pkg SHA256 `f766d3875637c1847c468664b854eb8770bc13d3c02928287e85f3a08fd44b1c`，project `017d48a481c87d026ee726aa2ef0eaeabe7b927fed6fd008c57d143b11a37494`。原App dylib `2a5fad6391ce16cd6f20912ba7529938eb42ead54b26e219748ddad9f28e4421`，候选`13fe785696aefa34215e66c38b9f09bfe9bfaeeb1e52fc673f46e1fd9e12aac1`。同一长歌名/歌手注入、700→1200→2001序列：旧false/false/false，新true/true/false，同窗口312104、单surface、一次Scene ready。

raw wrapper→compiler→live state行为门证明363/220与488/222四target同步；旧源三个正断言失败，新源通过，错误值/缺consumer原子拒绝，非文字、未限宽、冲突来源、缺定义/非slider和越预算等十类拒绝。真实series0002→0005的标题/歌手高亮ROI右界从799/734增至1239/1100，0008坏值后保持；这是局部像素位置证据，不声称整图逐像素不变。363/488 effect输入宽度frame67的745/688到frame131的1127/1006，GPU及compositor成功；220/222为白色子文字。首次publication诊断只记每层一次，不能从缺后续日志推断未重栅格。

Debug build、签名、30项binding/16项live/3项新行为测试、依赖/代码健康/防御/设计门通过。此配置39个作者effect中25个实际material GPU执行，11个输出直接合成；未触发项不计失败。未验系统媒体来源、普通设置UI拖动、物理多屏或官方文字像素一致性，不据此给整样本精确正确率。

本机证据：`.artifacts/scene-evidence/runs/text-width-property-20261005/final/samples/3395777145/runtime_evidence.zip`，SHA256 `b639e033d6f5ee1e2dd6573fb787d1bf1a3a33672012a49e598763231cddbfbc`，7928672 bytes；含旧源反例、两App日志/配置、四截图及身份，不含原包/App。单份迭代cache/App继续使用，其余本批隔离副本在审查后清理。

后继先复现本样本newproperty23底部音频：371可由公开bool开关显示，其隐藏395 provider当前被依赖准入拒绝。本轮开关关闭，该静态候选不算已证可见故障；需要非零音频及最终输出反例后再修。
