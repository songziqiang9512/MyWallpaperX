<!-- document-role: historical-evidence -->
# 材质视频资产接入既有媒体 owner（2026-10-12）

> **历史证据 — 非现役入口**。已收尾的设计与批次记录。 稳定合同归[运行架构](../capabilities/material-video-assets.md)，开放范围归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。以下设计先于代码保存，验收结果在文末。

开工目标：含视频payload的作者TEX作为材质asset/fallback时，沿原视频解码、时钟、资源发布和合成链连续播放。3039882306只启用公开选择器、filepicker留空的当前运行已证：资源存在但静态asset入口拒绝，背景不出现；sample/slot/路径仅是证据身份，不是运行规则。后继顺序仍归P路线与断点队列。

## 范围与取舍

扩展现役SceneVideoTextureSourceRegistry的typed layer/asset职责；catalog只准备不可变资源需求与媒体声明，激活由session同一registry创建或复用source。catalog自建播放器会重复时钟、暂停、seek、重建与stop，因此拒绝。静态TEX/图片、atlas及现有独立图层视频保留原职责。

首批只开放现有video输出能够严格发布的premultipliedColor资产。data/normal/flow等未证明用途局部拒绝，不把MP4文件名当opaque/alpha证明。WebM准备复用既有公开容器边界，不新增转码器。视频采用现役明确linearClamp采样；不未经合同消除未知TEX flags或声称全部视频采样metadata已兼容。

## 准备、身份与数据流

1. asset catalog在原resolver/loader识别媒体payload，保存URL、稳定SourceKey、设备及请求purpose的声明；准备期不启动AVPlayer，不将视频冒充静态RGBA。
2. registry保留layer-owned独立播放；asset-owned源按canonical SourceKey/device/session复用，多个材质、逻辑路径与surface共用该物理源。purpose是发布合同，不产生第二播放器。asset没有虚构layerID，不进入layer脚本snapshot/控制命令；两者都受session全局生命周期管理。
3. 请求的asset identity与实际source incarnation、epoch和content generation均保留。逻辑别名不能把旧帧贴到新source；source revision/device变化新建source，旧source停止并撤销迟到安装资格。
4. 已准入的媒体声明可提供prepared-provider launch合同，以准备合法的pipeline与颜色边界；它与decoded frame ready分开，不能把pending改写为ready。只有此typed声明允许等待实际帧，普通未知pending仍沿原launch拒绝。声明承诺只发布被实际frame alpha/purpose/content检查接受的结果；未知/straight alpha不伪造PMA。
5. 现有SceneFrameContext.timing传入asset FrameProvider与source.prepareFrame；静态、atlas及video状态沿同一SceneFrameTextureRegistry.beginFrame(assetStates:)发布。无新时钟、注册表、compositor或帧内解析/建图。
6. video decode/publication仍在各surface提交后由共享registry统一commit；单surface失败只撤销该屏未提交资源，不回退已被健康屏GPU使用的源。FrameProvider的atlas cursor保持原commit/discard。
7. fallback resolver仅接纳与请求、source incarnation/epoch、purpose、完整publication及实际采样均匹配的asset-video；禁止宽泛接纳所有provider或降级成假静态纹理。pending沿已有最小局部失败半径，已ready的last frame复用由原video owner决定。

## 选择、失败与退出

selected still ready时按现有优先级选still；空值/reset选作者video fallback。切换不伪发asset layer stop/seek，也不影响普通视频层；只要potential demand仍存在，维持原Scene-clock相位。最后需求退休、source变化或session退场才停止。此批不另建active-demand分析器，不声称解码能耗已优化。

asset acquire参加原begin/completeSurfaceRebuild集合；保留same-source复用、移除未重新取得源及全局pause/resume/stop。坏payload、解码失败、取消和不支持用途局部不可用；停止撤销准备/seek/observer/item，迟到完成只清自己的临时文件。GPU所用pixel buffer/texture仍由既有submission租赁保持到完成，不改变资源安全边界。

## 验收与停止条件

自有两色短MP4/TEX：empty fallback→selected still→reset，实际texture/generation→原resolver→compositor像素；两消费者/两surface同物理源、独立layer控制；pause/resume/rebuild/stop及迟到取消。变量/属性/资源目录改名、等价路径与相邻非视频/坏payload/错误purpose/alpha/陈旧source反例。原静态/atlas、普通视频及typed registry近门；Debug build；303实际背景连续帧，另一个未参与修复样本真实画面。

官方同输入对照不足时明确未验，不由非黑/route/ready代替结果。先完成一条真实fallback播放链；若普通material launch仍有独立边界，保留同一资源发布链和明确后继门，不加另一套视频算法。达到当前链验收后将稳定合同归运行架构、结果归证据台账，本设计归档；未验证用途与完整媒体控制继续在原队列。

## 文档预算决定

这是原layer-only视频owner向asset发布入口扩展的首份有界设计，需在实施前记录异步launch、身份、复用与多屏提交边界。仅为本设计新增实际正文预算，不扩现有权威；完成后按上述退出条件归档。

## 实际结果与证据边界

原c8817fa5的3039882306默认隐藏本地层，不是默认背景缺失。公开选择器5启用1084、picker留空时，原catalog把存在的TEX视频资源列unavailable，实际黑底。此批沿原媒体owner补asset声明/激活/typed publication；后验还找到原DrawRequest的solid采样只接静态file/current封面，遗漏videoAsset，使已decoded、published opaque的帧仍不显示。最终在同一采样准入补接，原纹理/颜色/输出链保留；没有新增视觉算法或样本特判。

最终17产品文件freeze v3 `f567a3606e6954f3345ab82c33e481265d27ad28357954a2fe8315b8b6aa6437`，实际Debug 303空picker恢复红舞台人物视频与前方时钟，8秒commit216代；媒体本身含三纵向重复栏，不据此改采样。完全自有无effects场景实际红视频可见，选择静态PNG后绿色可见。未参与实现/调参的3811216799原包继续显示人物视频，12秒commit691代；四运行均exit0/ready/GPU排空。实际照片、App/helper/hash收据在 `.artifacts/tmp/n04-fallback-followup-20261012/actual-accepted-observation.json`。普通桌面产品入口、实际filepicker热切/重置、多屏与官方同状态逐像素仍未验，不记整样本完成。

开发中两次Developer ID构建因Apple timestamp服务失败；命令行ad hoc Debug后，CodeSignOnCopy使编译器helper被原团队校验拒绝。这两次画面不计兼容验收。最终隔离App的helper恢复原Developer ID团队签名且timestamp=none，outer App仍ad hoc；strict/deep和helper指定team验证通过，未改安全检查/仓库签名配置，不证明Release签名或公证。有效签名v2的真实黑画面及opaque帧证明采样断点，v3实际修复；临时逐帧phase观察随后删除，仅保既有frame commit收据。

自有门修正了先前绕过DrawRequest的盲点，沿生产采样准入与compositor uniforms再做真实GPU像素；两套变量/属性/layer/资源改名、extensionless与.tex别名、sampler/varying及等价采样中间值变体通过，32/31帧均经实际颜色读回。每套34项检查涵盖still/reset、静态tint、共享源、独立layer控制、pause/rebuild/stop及text/provider/purpose/epoch邻近反例。最终新模块2项通过；其他最近门8模块37项为实际v1/v2身份，不冒充所有门在v3重跑。末轮删除随guard改名而失效的旧源码文本准入测试，资源换代拒绝由真实registry/AVPlayer反例接管；断言基线只收紧241→240，Source与本门再次通过。DrawRequest也登记进原资源验证组。没有路径、hash或固定源码形状的新例外；媒体路径、SourceKey和byte identity只参与资源查找/生命周期。

## 两项队列纠正

3815761795日期字形的窄疑点已经受控复验：官方截图10-11是“日”，运行10-12是“一”；只换完全自有返回字的两份同包输入，其他67个entry逐字节相同。独审比较官方“日”与实际“日”得到相同黑外形、亮色日框与两个分离黑孔；不能将周一字形当漏字。没有修改字体/颜色。上部黑帽、布局和glyph metrics仍未裁决，记录在 `.artifacts/tmp/text-date-glyph-20261012/controlled-observation.json`。

3666041758当前138由SceneScript实际visible=false，没有graph不构成可见缺失证明；190两段Blur frontend-envelope及141.visibility invalidSource仍开放，不能以新的磁流体算法填补。该原包仅作现状复验，不参与本次媒体修复或独立回归；证据在 `.artifacts/tmp/n05-visible-source-followup-20261012`。

## 文档归属与退出

开工有界设计已从Batch2待实施目录退出；唯一稳定媒体合同归材质能力文档，架构只留入口与接线。该公共资源入口需要记录prepared与ready分域、共享提交和身份退出，用短合同替代现役设计，按实际正文登记预算；不扩其他旧合同来绕门。后续未验purpose、普通material组合及完整桌面/长稳仍按原队列推进，不把设计批准、profile命中或几份截图当全库正确率。
