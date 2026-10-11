# 普通静态图片自动尺寸（2026-10-12）

> **历史证据 — 非现役入口**。能力归[SceneScript API](../capabilities/scenescript-api-coverage.md)，后继归[断点队列 N06](../roadmap/scene-open-breakpoint-queue.md)。

## 通用语义与实现

普通静态图片的model `autosize:true`使用原资源自然尺寸；false/省略时保留作者显式尺寸，层尺寸真正缺席才使用model宽高，model宽高也缺席时为1×1。准备后的同一sizeWH供脚本getter、cursor和绘制消费，原始initialConfiguration仍保留作者输入。不能将显式但暂不支持的尺寸形式、视频或动画图集误当普通图片缺省。

沿原DeviceResourcesTask工作线程先发布资源头部尺寸，再继续原GPU准备；原launch最终GPU join保留。TEX读取原容器尺寸，PNG/JPEG读ImageIO属性，不解码图片或上传GPU；元数据保留在既有PreparedBaseImageResources.Entry，metadata-only不表示纹理已ready，后续deferred结果仍由原入口接纳。隐藏图片继续按原需求延迟准备，没有为了取得尺寸全量预加载。读取前后校验既有source identity；普通帧不新增IO、建图或尺寸算法。设计见[D4](../roadmap/batch2/script-component-api-design.md)。

本片没有新增路径、hash或固定源码形状的视觉分派例外。资源发现既有限制没有扩大；零/负尺寸、动态包装、特殊clone与动画帧尺寸另列队列，不按本片合同猜测。

## 官方与真实输出

官方客户端自有200×100普通图片：autosize true/false/省略与层显式120×60/缺席组合，getter和实际矩形一致；补充model宽80高40的六组合，true均200×100，false/省略显式时120×60、缺席时80×40。研究只消费公开/自有输入和黑盒输出，批准收据绑定确切输入/截图/测量，不含私有实现。

原生基线eedce273中true显式格仍120×60，缺层尺寸格不可见。最终TEX九格、变量/资源改名及等价size访问的PNG九格、model宽高六格，首帧和后续帧实际白像素包围盒全部符合上述尺寸，容差1作者像素；缺层/model尺寸的false与省略格恢复1×1。不是只检查profile或getter。

未参与实现选型/调参的3804441338与3232289987原包隔离前后运行：前者镂空轮廓、文字、雨与底部频谱保留；后者人物头发位置、背景发光及频谱区域保留，未见本片布局回归。这两份的旧U07/U18修复不计本片成果；动画相位、时间和频谱变化不是逐像素等价。279个可解析包的有限首纹理普查只说明大量作者已显式填写自然尺寸，图集差异不能当作缺陷数量或受益数量。

## 验证与边界

最终产品七文件身份cb25815d542b0f249b8d340b025da1dcaf24fb3dc141f46711b218c5ce947f71，Debug构建及签名校验通过，五组原生运行均ready、exit0、GPU drain完成。CPU回归覆盖资源/变量改名、等价表达式、缺字段与显式异常字段、video/sprite/Puppet近邻、metadata-only到ready与取消/早失败；最终具体门及独立审查由冻结收据记录。direct Host只证明隔离真实渲染，不等于普通App→daemon入口、性能、全样本或完整官方parity。

证据根`.artifacts/tmp/static-image-autosize-20261012/`：`product-build-identity.json`、`native-pixel-measurements.json`、两份官方approval及`official-width-height/neutral-contract.json`。必要输入/截图/日志按收尾收据保留；唯一连续构建缓存仍为`scene-constructor-runtime-20261011/DerivedData`。本片完成普通静态尺寸范围，下一步优先核对真实样本的文本wrapper首错；特殊clone与间接资源发现仍开放。

收尾：57项CPU回归、103项路由/设计测试、15项结构门与4项最终App延迟属性集成通过；集成覆盖实际ROI、取消和窗口身份保留。临时HOME与shader转储已清理。正式提取仍被既有1GiB总预算拒绝，未提高预算或删除未知证据；最小证据留原目录。已有218B的`.mimosa`按未知归属保留，residue门仍有该finding，不记为通过。
