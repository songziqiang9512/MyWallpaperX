<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。剩余问题归[断点队列](../roadmap/scene-open-breakpoint-queue.md)，稳定职责归[终端材质合同](../architecture/runtime-architecture.md#terminal-material-raster)。
# Named solid源尺寸修复（2026-10-12）

## 首断点与实现

3761619125的11层裙摆把named纹理按源尺寸比例重复采样；旧资格排除全部externalPrimary，工作纹理随屏幕放大，1954输入2048×700代替作者1180×403，形成大片重复矩形。provider47的1188×403 publication和Resolution编码本身正确，不能伪造uniform去补偿。

本批只扩原Capability→FramePreflight→GraphExecutor→terminal receipt→MainPass链：原owner已准入的single raster externalPrimary，普通正交、normal source-over、可见非publisher、简单color链、target-pixel顶点证明，且**不要求provider graph output**。保留`!requiresGraphOutputProvider`；它检查consumer依赖的provider，不等于consumer自身publisher。graph-final依赖、external文字/透视/高级混合、geometry、aggregate、同层/secondary与复杂图仍走旧路径。独审发现的文字/透视/advanced误扩已用原preflight两处none条件收窄，不新建算法或owner。

原FrameInputs/PreparedLedger仍核对provider/slot/epoch/object/content并持有真实纹理；terminal ticket与已验证依赖向量的消费事实一致，Compositor返回同一事实，避免重复legacy blend。普通缺图局部passthrough、完整性错误拒绝、同buffer/one-shot、真实写后读冲突的原copy/pin均保留；不修改shader、采样器、provider尺寸或普通帧解析。

## 官方有界合同

官方2.8.0.42：完整合法原包保持命名关系，增加两个自有single-effect solid消费者；原内容先暖机15秒通过正控，再以自有shader编码Resolution。1280×720下consumer scale1/2、640×360同输入、provider scale2→1三组实验，g_Texture0/1.xy/zw均RGB(74,25,0)，与1188×403兼容且排除倍增。常量正控(64,128,191)、真实named内容正控(255,183,204)，36个预声明5×5 ROI零spread。4秒未加载完的黑图不作证据。

每档约16.06像素，不能区分1180与1188，也未测GPU实际allocation、原多wave后缀或复杂FBO。中性合同SHA `ed0affb70192c19522a4d67f423ebdaf2f355cd798e2bede95a1a97120ff77ac`，官方manifest SHA `0d4a797bc2dfada33c98f91b5abf9062f106991e37c563bacdad127cb5dcafdc`；未读私有实现。guest精确自有窗口/副本已清理，未改用户桌面与全局设置。

## 实际收益与验证

最终Debug App executable SHA `1ce2f50ff17ac8df531d05d24cb80884a093b8d7736c2cbb0f435ef2415432c8`、dylib SHA `7d2167d0a3417006112d8fcd3fd31a7515de11904013092c32c6b91434adaf4c`。原包SHA `73cbda2910b51043b2beacd6f669e1a0c7d725e59399124dafe986d14cbd784f`，隔离direct Host原始属性运行。11层裙摆重复矩形在截图中消失；含3肩部层的14层均实际terminal replay、GPU完成、合成及next-frame成功。1954回到1180×403，1959回到668×339，非手改作者参数。源尺寸减少这些层的中间像素工作量，但本次诊断运行不证明普通桌面FPS或能耗提升。

7×3 named与10×10工作纹理的真实GPU门：最终active条纹转换数7；尾段inactive/局部失败时HEAD7→candidate127，原覆盖冲突需1次bypass copy＋1次slot0 snapshot/1pin；active零副本，named21像素和尺寸不变。wrong buffer/reset及正负文字倾斜overflow保持。6方法通过；同最终Harness/Support/linked sources的旧HEAD对照仅3named子例红。GPU后加强Python转换数断言并按相同输入SHA重放，未把重放说成新GPU运行；初期setup/超出carrier颜色合同的失败不作产品红证。

真实submission receipt8方法/23行为通过：四raster binding内部接缝、flag伪造、missing局部fallback、epoch/content/foreign buffer/one-shot/append失败。这里手工binding不代表graph-final已获产品准入。旧FrameCommit同输入5红例明确拒绝合法ready并误放伪false。

自有App raw provider播放2秒后删除：solid消费者先经24×24源尺寸terminal，中心蓝色255→白色fallback；健康绿色peer保持，下一帧GPU继续、退出排空。原带graph-provider删除case另作旧路径回归，不将它等同新增terminal准入。缺provider不会把完整场景冻结。

最近capability/runtime bridge原19方法中18通过，一项旧copy/history测试support未跟上effectDrawAlpha/color及pool stub；同步neutral字段、复用完整publication support替换后，完整19方法及seal反例全部通过。修测试适配，不改产品行为或弱化原像素断言。Debug build、结构/依赖/防重复owner/设计/代码健康门通过；residue唯一既有`.mimosa`（218B）未知归属保留，不声称全仓全绿。

## 保留与下一项

最小结果暂存`.artifacts/tmp/effect-resolution-20261012`，原证据缓存已满且上批prune无到期候选，未抬预算或删除未知证据；收尾保留官方合同/截图、GPU与receipt红绿、最终App日志/截图/身份及独审，临时HOME/样本/编译缓存和重复产物删除。持续开发只复用`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`一份构建缓存。用户原媒体只读，本批无push。

本次“裙摆named源尺寸”专项11/11层闭合；整样本仍有头部deformer466缺可选slot1尺寸的独立断点，未给完整正确率。下一批先核该中性尺寸证明：不得默认填1或伪造资源；若需扩大分析器，只在原prepared shader proof中处理真实无效分支与辅助函数依赖。graph-final external扩域留队列，需可见需求及同帧发布/缺图证明后复用现链实施。
