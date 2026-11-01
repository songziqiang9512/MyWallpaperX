<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。当前语义归[D4](../roadmap/batch2/script-component-api-design.md#prepared-dynamic-image-material)与[API覆盖](../capabilities/scenescript-api-coverage.md)，选序归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# 动态图片默认材质：准备、实例与透明度资格

> 2026-10-16；现役语义与停止条件由[D4](../roadmap/batch2/script-component-api-design.md#prepared-dynamic-image-material)维护。本文保存本批输入、行为证据和未验边界，不接管执行队列。

## 首错与通用修正

`2890473419`的13/82/124通过初始配置取得同一图片model后创建新层。当前四个所需API均存在，原六条not-a-function已经过时；fresh运行实际是三条catalog miss→null→写visible失败。纹理1504×3000已上传，但model默认材质含LIGHTING和metallic/roughness，原间接plain资格不支持；literal入口反而只准备纹理，不能证明它有完整材质执行。

原资源准备owner按canonical model生成不可变builtin默认材质fact，调用同一个LightingProfileCompiler，不借源层instance/effect/script/property或最终纹理。GPU已发布后，launch join以builtin fact、成功共享source Program或已准入的compositor lowering证明发布同一C/Swift模板；Program保留原provider/color/alpha表，动态实例按模板canonical路径查询默认profile并使用自己的矩阵。scratch、lit payload、resolved capture和pipeline预热共用该消费事实；普通帧不新增解析/编译/建图或资源加载。Puppet仍只保原plain默认几何，未知材质局部拒绝。

## 固定官方alpha资格

固定Windows客户端2.8.0.42，`wallpaper32.exe` SHA256 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`；交互Session1、原receiver PID5368及启动身份全程保持。只打开、置顶和关闭自有唯一标题窗口，实际client1210×786、屏幕范围与遮挡PID检查均通过，关闭后各自标题数为0，VM保持运行。

自有40×8 RGBA TEX提供alpha0/64/128/192/255，genericimage2+LIGHTING1、metallic/roughness0、单slot0、SDR正交白ambient。透明parent capture的自有effect一半保RGBA混合，另一半把采样alpha编码成opaque灰度，外区透明作正控；实验只改变source材质alphawriting省略/default/enabled。

- r1 enabled正控因model autosize=true将显式800×480覆盖为自然40×8，未命中预登记ROI，按停止条件退出，未运行其余两臂；不产生alpha结论。
- r2只把三个model autosize改false，其他场景、shader、纹理及ROI不变。enabled正控得到精确五档灰度和黑色透明外区，另一半出现中间透明度背景混合。
- 三臂各两图，全部预登记stripe与outside区域跨模式逐像素差0，同输入漂移0。整图另有左下窗口圆角49像素差，不能声称全窗口逐像素等价。
- 独审重算27份输入、freeze、guest manifest与全部ROI，均无输入漂移。仅此strict genericimage2 lit consumer接受default；plain/genericimage4 default、enabled及通用RenderState不扩大。

直接官方证据只覆盖上述光照/标量/SDR拓扑；其他有限metallic/roughness沿项目原alpha表达式不变是有界实现选择。中间alpha观察一致不证明完整混合、HDR、Puppet、custom/multipass/provider或全样本parity。

## 本机真实运行与验收范围

签名Debug App executable SHA256 `202ff3643eca53f0872872cf78d5dcf60fafa3bf37c082f3bd2903228f45c528`，dylib SHA256 `414aef3567dac1659e2618f8943310c1e6bc591df4f2339272f684f8ef8756cb`。唯一构建27.99秒，4331个产品/工程/辅助构建输入无漂移，deep/strict签名检查通过；计时不作为启动或性能收益。

原包fresh基线三null、仅三图片owner完成；候选三null退出，六图片owner均完成，各提交一个真实动态实例，GPU与最终合成持续执行，实际人物/相框图可见。四个默认hidden粒子脚本仍向未赋值shadowLayer写visible，是另一作者输入边界；未伪造对象或隐藏异常。原shadow模块默认Off，不能把无影计为缺陷。原Sound正常推进，退出surface1→0且GPU drained。

只在隔离副本将layer13模块Combo从String2改0，其他package entries与JS字节保持；指针往返使用现有debug输入，三次实际画面和owner提交单列。首次组合from-launch与trajectory被现runner拒绝，未启动surface，不作运行通过；移除冲突选项后正常运行。此项不代表官方完整阴影/交互parity。

自有三入口静态/动态对照使用literal、初始配置Object及registerAsset真实handle、同一lit默认材质、独立位置/姿态、red override源和unlit邻例。首轮载体把JSON radians与公共setter degrees混用，且静态230逻辑尺寸与动态1×1再scale的capture域不同，不能据图片差异裁定材质失败；保留该轮，校正输入后另验，不改容差。原PNG像素确认健康red/unlit邻例均保持，缩略图误读已撤回，未因此改资源owner。 校正轮在相同逻辑域与姿态下，三入口static→dynamic的预登记ROI逐像素误差0，亮度分别204/31/53、位置正控差151，red源255/32/32、unlit255及blue→green阶段witness全部符合预登记。实际handle唯一、count+3和同回调getters通过；三constructor无VM异常，GPU及唯一终端输出完成。

独立原包`3264246690`同一候选App无VM错误，实际人物/警戒带图及原loop声音保持，正常退役；其旧锯齿、点击及警戒带运动差异不据此关闭。本批没有CPU/GPU/RAM、启动或能耗收益声明。

## 证据与剩余边界

必要结果已按14天、单包32MiB归档至本机`.artifacts/scene-evidence/runs/dynamic-image-default-material-20261016/`，合计约18.19MiB；核心ZIP 684,510B、242文件，SHA256 `961a91ebd3fce2d2ce35b40eba8a8fa37c2cc43e7641db46d9270973249d87af`。内含自有输入、产品/门身份、失败载体、独审及中性执行证据；不含原Workshop包/脚本正文或完整runtimeInput。官方八张原始截图按哈希留在`/private/tmp/mwx-dynamic-image-alpha-20261016/`，不是产品资产。

本轮删除25个已退出隔离HOME/cache/sample目录及19份重复输出，并回收七个本轮失败后已修的定向门cache及六个已封存自有输入目录，合计释放864,624,050逻辑字节；两原样本逐文件哈希不变，四个精确guest fixture连同仅生成shader cache已回收，原receiver与VM保持。仅连续构建缓存`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`及小型收据保留；没有按根目录清理其他会话。

完整设备重建/多屏、physical HDR、任意model/material、所有脚本交互与官方逐帧golden未联验；default准入不推广为通用write-mask合同，1×1逻辑capture放大质量也不由本片验收。


<a id="shared-source-user-scalars-20261101"></a>
## 共享 source 的用户标量（2026-11-01）

原3812473896的layer35需创建63根音频柱，但model材质的brightness/power绑定用户属性。fresh旧App明确先在ColorModulationCompiler报neutral-scalar-values，继而source报dynamic-declaration-unsupported，创建后写alignment抛null异常；不是容量或shader不合法。其color user+WEColor脚本与Alpha user已有typed消费者，两标量的准备证明/producer接线缺失。

原Binding只新增material key→user property key的准备事实；原scalar解析合并Alpha/静态重复实现，保Alpha0…1及静态零scroll。PropertyBindingCompiler在prototype layer/material/pass/key生成typed producer，原source准备消费最终闭包，原snapshot→reflected float bytes→fragment buffer不变。任何动态brightness/power均保完整source Program，即使seed1也不lower，避免热改失联或compositor重复乘色。共享模型只求一次prototype Program，各clone沿原独立位置/publication消费；不加VM/renderer/clock/state owner。最终4产品净减2行；既有lowered color/Alpha入口检查保持，未收紧旧profile。

同一冻结5测试文件对旧f54四产品跑26tests、54个新增subassert失败、0 errors，候选同门26/0/0；输入均稳定。实际preprocess/schema角色证明、原属性compiler/原snapshot/整段原source admission及预上传float bytes参与，Power在原/改名两变体均编码.5/2/8；用户域0…10不另夹shader注解0…6。正反例含两组等价/改名、brightness/power单独/组合、seed1、Alpha/color混合，未知wrapper/script/Timeline、scroll、host冲突、多纹理/重复alias等；静态证明不代GPU。独立review无本批新增finding，另发现的静态host默认值lowering旧缺口单列队列，未借本片扩动态接口。

普通签名Debug构建41.16s，4416产品输入中一项并行SILInspectorView漂移，4Scene变更及其余Scene输入稳定；故只授本批Scene身份，不称全App最新源快照。exe SHA256 `e6b960f154a4597f818444153d5b97d5e9a605965b0476174c676ea1f92d9754`。无编译warning/error，签名deep/strict通过；后继UI/Library并行修改未混入本批结论。

自有v1载体因autosize覆盖作者size、clone另有scale而几何不一致，且matrix的hover输入误启无关交互门，5run均不称PASS；只修输入生成v2（统一scale、撤错误hover预期），先neutral资格后跑四配对，未移动预登记ROI或改产品/容差。v2五项PASS：prototype/clone的固定内区逐像素相同，RGB分别neutral67/63/52；Brightness.5→1.5为36/34/28→98/92/75；Power1→.5为67/63/52→103/99/90；.5→8至5/5/5，再8→1回67/63/52。静态source与builtin邻区始终53/101/153、26/204/51；四次live编辑同window/surface，无重建。该组证明配对热改，不称一个连续多步进程或官方数值parity。

原381当前init/update产生63个dynamic实例，完整source在frame1以prototype35一次编码、consumers64、4×4 target，音频generation2非零后真实红色柱条可见；原null异常退出，color脚本亦完成。独立原2890473419六图片owner及默认lit动态人物/相框保持可见，四个hidden粒子向未赋值shadowLayer写visible的旧错误仍在，不记整景完成。两原包均5s，v2五run及两原包正常退出/surface1→0、GPU drained；未做官方同phase、原生属性面板、HDR/多屏、长稳或性能收益验收。

必要代码/fixture、红绿、v1资格失败、v2输入与ROI、原包日志/PNG、构建和独审归`.artifacts/scene-evidence/runs/shared-source-user-scalars-20261101/metadata/samples/0/runtime_evidence.zip`（普通14天）。普通source动态标量缺口从队列退出，其余未知shader/user texture/脚本标量等仍是未准入范围；纹理成功不授完整材质或任意模型兼容。
