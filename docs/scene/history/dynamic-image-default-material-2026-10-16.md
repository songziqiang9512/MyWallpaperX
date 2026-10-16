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
