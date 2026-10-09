<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# 文字宽度属性原位更新（2026-10-05）

> **历史证据 — 非现役入口**。现役能力见[运行输入属性](../capabilities/runtime-input-property-coverage.md)，文字布局合同见[运行架构](../architecture/runtime-architecture.md)，当前验收见[运行证据](../capabilities/runtime-evidence-current.md)。

基线`0b0acaad`。真实3395777145的newproperty28/29各绑定两个文字对象的maxwidth；Host和动态文字store已有宽度consumer，raw binding parser/Program遗漏该字段，合法修改因此走rebuild。补齐现有typed target投影，复用原snapshot、每层后台raster、纹理/尺寸原子publication及唯一compositor；不扩font或limitwidth开关。仅固定limitwidth=true、无script/animation冲突的width wrapper；slider域、fallback需在现有1…16384预算内，默认值在slider域内，避免静态0无限宽被运行时夹成1。其余形态保留重建路径。

原件只读。pkg SHA256 `f766d3875637c1847c468664b854eb8770bc13d3c02928287e85f3a08fd44b1c`，project `017d48a481c87d026ee726aa2ef0eaeabe7b927fed6fd008c57d143b11a37494`。原App dylib `2a5fad6391ce16cd6f20912ba7529938eb42ead54b26e219748ddad9f28e4421`，候选`13fe785696aefa34215e66c38b9f09bfe9bfaeeb1e52fc673f46e1fd9e12aac1`。同一长歌名/歌手注入、700→1200→2001序列：旧false/false/false，新true/true/false，同窗口312104、单surface、一次Scene ready。

raw wrapper→compiler→live state行为门证明363/220与488/222四target同步；旧源三个正断言失败，新源通过，错误值/缺consumer原子拒绝，非文字、未限宽、冲突来源、缺定义/非slider和越预算等十类拒绝。真实series0002→0005的标题/歌手高亮ROI右界从799/734增至1239/1100，0008坏值后保持；这是局部像素位置证据，不声称整图逐像素不变。363/488 effect输入宽度frame67的745/688到frame131的1127/1006，GPU及compositor成功；220/222为白色子文字。首次publication诊断只记每层一次，不能从缺后续日志推断未重栅格。

Debug build、签名、30项binding/16项live/3项新行为测试、依赖/代码健康/防御/设计门通过。此配置39个作者effect中25个实际material GPU执行，11个输出直接合成；未触发项不计失败。未验系统媒体来源、普通设置UI拖动、物理多屏或官方文字像素一致性，不据此给整样本精确正确率。

本机证据：`.artifacts/scene-evidence/runs/text-width-property-20261005/final/samples/3395777145/runtime_evidence.zip`，SHA256 `b639e033d6f5ee1e2dd6573fb787d1bf1a3a33672012a49e598763231cddbfbc`，7928672 bytes；含旧源反例、两App日志/配置、四截图及身份，不含原包/App。单份迭代cache/App继续使用，其余本批隔离副本在审查后清理。

后继先复现本样本newproperty23底部音频：371可由公开bool开关显示，其隐藏395 provider当前被依赖准入拒绝。本轮开关关闭，该静态候选不算已证可见故障；需要非零音频及最终输出反例后再修。

<a id="glyph-bounds"></a>

## 通用文字边界与末行截断（2026-10-09 后继）

基线`7f591c8d`。U12同字体、28点、maxwidth550的长艺人文字，官方第二行`ONE TWO`，原生拆成两行，后文提前丢失。固定官方2.8.0.42、自有输入与原包派生长短文本证明换行阈值与原生默认advance不符，且最后允许行继续保留下一单词前缀；`FOUR FIVE SIX`在1行显示`FOUR FI`、2行显示`FOUR / FIVE SI`，硬换行1行仅`FOUR`，无限行保持正常word wrap。研究只消费黑盒截图和公开CoreText接口，无私有实现表达。

既有RowLimit/TextureLoader共用CoreText的`lineBoundsOptions/useGlyphPathBounds`；末行使用原生cluster break，省略号按同一边界回退组合字符。Geometry仅在准备时量化作者像素字号，下采样复制已解析字体连续缩放；绘制关闭再次subpixel量化，解决无padding时首字边缘损失。未增加换行算法、provider或合成owner，也不按字体/样本身份分派。

官方单字体宽度阈值：24点为(462,463]、28点为(536,537]、29点为(555,556]，36点仅证≤693。原生连续advance不能解释这些结果；整数准备字号与glyph bounds在一作者像素内接近，但29/36边界仍有平台差异，不声明恢复了官方通用字宽公式。换行内容、字体raster和阈值分别记录，不把一项容差推广为全部字体逐像素一致。

旧生产代码在自有Arial可见边界反例中错误拆行。新增实际纹理门验证边界前后、末行与literal前缀/ellipsis的几何及ink统计一致；初始/动态像素一致由既有留白与装饰门覆盖；既有padding九锚点、硬换行、2048下采样、装饰、动态宽度/世代门保留。跨作者尺寸各自取整/缩放的装饰比较，两个轮廓欧氏差为√2：绿色质量差0.064%/0.076%，边缘至多1px，原1.25px门未准确表达每轴一像素对角。仅该比较改用√2，其他装饰1.25px、质量2%与边缘1.25px不变；独立审查认可，未改产品来压低指标。

最终隔离签名Debug dylib `68842a6a227444c58031e182b9aaa9e78941c4e44c53a2d6791b715516ad91c7`；3个改动源与构建输入逐文件一致。U12短/长、末行控制、24/28/36点控制、29点控制各10秒，1210×786 viewport，均exit0/GPU drained。U12长文为`ARTIST / ONE TWO / THREE / FOUR FI`；15个对象准备，44:0与83:0两effect实际GPU完成并进入compositor。末行六组控制可见内容吻合；29点原生555已一行而官方556才一行，36点原生694才一行而官方693已一行，保留这一作者像素阈值差。小号蓝标签另以实际Loader CPU读回核查12个非空字符均在，未复现缩略图所疑缺字。未验全部字体、普通App派发、多屏或完整样本逐像素parity。

最终文字5模块50项通过；设计、结构、依赖、代码健康、防御与断言门通过。全局文档门受并行Web未预算/入口链接改动影响，未把它们归入本批。证据包`.artifacts/tmp/u12-text-wrap-20261009/text-layout-evidence.zip`（12,890,679 bytes，SHA256 `4c95603decf32ae3576dfb111aa8ed27e9f151903e6045f751b8dfa28405ca9e`）保留官方黑盒、最终原生运行与失败反例；媒体包见其独立记录。总证据缓存已触及1 GiB、无可到期项，本包暂留本机任务目录，不抬高上限、不删除未知证据。9次已退出运行的副本/HOME/cache及编译模块缓存清理162,898,307逻辑bytes；只保留既有单份Debug迭代cache。
