<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。当前覆盖归[SceneScript API](../capabilities/scenescript-api-coverage.md)，后继问题归[断点队列 N06](../roadmap/scene-open-breakpoint-queue.md)。

# 动态图片创建几何（2026-10-12）

## 通用语义与边界

基线 `770df323` 忽略 create 配置的尺寸、角度与透视，字符串 origin/scale 也不能沿已有向量读取入口消费。普通动态图片发布时又用物理纹理尺寸覆盖层的逻辑尺寸，因而作者要求120×60或省略尺寸的副本都可能被画成200×100。本片复用既有配置读取、C record/journal、Swift候选事务、descriptor和image publication；不新增投影算法、资源加载器或最终合成路径。

模型JSON的 `autosize` 是尺寸规则的输入，不能由任一同资源作者层推默认值。准备期从原TEX容器或PNG/JPEG解码结果保留自然尺寸，再将同一份template交给既有脚本域和Swift动态层runtime。自然尺寸与降采样后的GPU纹理尺寸分开；普通帧不读包、不解码、不重建模板。`autosize:true`使用自然尺寸，false或省略时使用显式尺寸，省略尺寸为1×1。getter、候选几何与publication使用同一结果。

在普通资源已经成功准备/准入的条件下，正尺寸String、Vec2、标量与不含动态绑定的value包装经现有入口消费；plain对象/数组不会因具有相似结构而冒充Vec2。构造字段perspective按已证配置语义取Boolean，所测非Bool为false；它不复用setter的拒绝规则。构造angles沿序列化弧度输入转换至现有runtime角度单位。已准备输入的变量名、资源名和等价值表达式不选择分支，没有新增路径/hash视觉例外；既有资源发现的源码形状限制本批显式登记，不宣称任意嵌套或间接表达式均可完成准备；登记规则见[开发工作流](../development/development-workflow.md#compatibility-exceptions)。

零/负尺寸在官方属于合法几何，但当前publication/capture/cursor仍要求正extent。本片将此未支持create局部返回null，避免提交不可发布层，也不抛错撤回同owner其他合法操作；不是宣布这些官方输入非法。包含script/user绑定的size包装同样不伪装已执行。作者getter/Proxy真正抛异常仍进入原owner回退，不能吞成普通null。完整text包装、动态初始配置、模型width/height优先级、任意强制类型转换、Puppet/composition clone仍未闭合。

## 官方对照与验证范围

官方2.8.0.42，自有200×100纹理、1210×786画布、显式FOV95：模型autosize true的静态/动态String、Vec2和省略尺寸都实际200×100；false及省略模型字段时，显式120×60、省略1×1。最终18格实际bbox与getter相符。constructor true/false各与同输入静态参照ROI零差异，二者之间有39414像素变化。 补测String资源路径、Object仅image与registerAsset Handle三种重载，模型false/省略时即时及frame30的size与实际bbox均1×1，true均200×100；自有模型未设置width/height，不外推这些字段。早期目视“构造true空白”已被原图哈希、逐像素和单图复看反驳并撤回，没有据此添加兼容分支。

原生同字节普通材质矩阵实际9个动态格通过：autosize true保持200×100，false及省略模型字段的String/Vec2恢复120×60、缺省恢复1×1。后两者修前都错误绘制200×100；不是只检查getter或profile。静态参照仍有已知autosize偏差，单独留队。最初utility solidlayer探针修前后均无prepared动态资源；修前Swift拒绝owner，现提前局部null。它没有被换成“通过”，后继普通资源等价探针也不证明utility已支持。

原生String origin/scale普通资源探针的String/Vec2输出在预定2像素尺寸、2%面积容差内一致，缺省尺寸仍为1×1。构造true/false各与同输入静态参照在3,625,776像素ROI内零差异，两种投影有245,950像素变化。

首候选的真实回归拦截了3792817546：基线63动态层变0，候选受控音频画面未见频谱，create返回null后访问alignment异常。原因是准备期已有每owner的authored→canonical资源映射，但新增提前metadata查询没有接入，晚于它的原Swift规范化无法救回create。基线使用静音，因此不能声称同音频条件下频谱由可见变消失。该候选没有提交。修正将原owner准备好的映射送入同owner的create查询；C不新增命名空间算法或全局别名，后续journal与Swift权限仍消费同一canonical身份。真实VM反例覆盖两个owner的相同literal分别解析到不同资源/尺寸、资源与变量改名、直接canonical、错owner及未知资源、异常回退和提交后的完整更新。独审进一步用资源改名复现非ASCII大小写、组合/分解等价键在C字节比较处丢失原Swift身份语义；修正由唯一VM domain安装纯native规范化入口，将既有Swift小写和规范等价身份编码成统一字节键，alias/catalog/create共用并保留原canonical资源拼写，无C casefold备用路径。真实VM还验证了小写后键增长以及作者改写String.prototype不影响该身份入口。最终重建中，该owner恢复63个动态层、无创建异常；同受控频谱输入下，实际截图右侧重新绘出有色频谱条。它证明本批回归被修复，不证明真实系统音源或整样本parity。

追加官方九格overload探针在native未通过：text.content owner无静态图片，原资源准备需求未从String owner进入；参数path及registered handle也超出现直接literal发现能力。三模型/material虽进descriptor，GPU prepared entries与dynamicImages均0，9次create均null。现/HEAD准备路径相同；旧版晚拒绝仅静态追链，未对该新fixture实际运行旧HEAD，不能宣称无回归实测。此失败保留，不以另换输入抹去，也不将官方九格默认合同写成native九格通过。

真实2887542690原包与仅触发作者shadow选项的副本均完成往返鼠标运行；25个普通图片加3个text候选进入动态链，但后者wrapper效果未闭合，6个特殊资源clone失败仍在，阴影大面积黑色遮挡未解。未参与实现选型/调参的2890473419也完成原包和同类触发副本：中心人物/发光框及两侧动画实际可见，3个动态候选进入；仍有3个特殊资源null和4个undefined.visible，未宣布整样本通过。shadow副本只在隔离包修改作者现有静态选项，不冒充未修改默认输入或产品属性交互。

原生同输入与真实样本后验见本批证据根的运行收据和像素量测。未锁定的动画相位不能将所有前后差异归因于修复；受控音频不证明外部音源，内部direct Host不证明普通桌面dispatch、长稳或发布版本。

本批57个focused用例按相应冻结候选通过；最后Unicode源重跑真实VM/Boolean邻接21个，其余36个为未变消费者此前验证，不宣称整套测试都在最后源码重跑。Debug构建与签名校验、15项结构门、103项设计/路由门通过。最终二进制的8个几何ROI与此前已量测输入逐像素一致；独立审查分别核源码、变体/反例和真实画面，收据按下述路径绑定。

## 身份与后继

证据根 `.artifacts/tmp/dynamic-layer-dimensions-20261012`。`official-handoff-review.json`批准中性合同，官方原图、输入与纠错保留在 `official/`；实现上下文不消费私有实现。`implementation-source-freeze.json`与`product-build-identity.json`绑定产品源码、Debug App和签名，运行命令与退出状态见各launch收据。最终CPU/治理、独立审查、提交后核验及清理按同根收据查询。

静态层autosize仍有实际偏差，不记成本片修复；排序合并与跨callback绝对索引陈旧目前为静态反例，须真实VM和draw复现，不能直接归因为阴影遮挡。后继按真实输出首断点选择，资源克隆保持原geometry/graph职责。
