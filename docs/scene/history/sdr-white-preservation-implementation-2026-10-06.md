<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# SDR 正常颜色恢复（2026-10-06）

> **历史证据 — 非现役入口**。当前权威：[D2输出设计](../roadmap/batch2/hdr-tonemap-edr-design.md)、[执行卡](../roadmap/batch2/reference-evidence-implementation-cards.md)。

基线 `7e73f423`，目标与取舍见 [D2 阶段 B](../roadmap/batch2/hdr-tonemap-edr-design.md)。用户报告的默认变暗存在明确终端原因：旧项目 shoulder 将普通白点 1 压为 0.75。本批保持 authored HDR 合成/Bloom 与显示 EDR 的区别；不声称官方最终曲线一致或 Display HDR 完成。

## 修改与画面收益

唯一 `SceneDisplayMappingPostProcess` 的 SDR 导出改为有限 RGB 饱和到 `[0,1]`，正常范围恒等，非有限通道归零，alpha 保留。所有使用该路径的场景都生效，无样本或资源分派；非 HDR 路线不变。删除仅测试引用的重复 CPU 曲线，实际颜色由 Metal 输出验证。raw16F、超白 Bloom、反射源、原始历史、资源生命周期及最终呈现 owner 未变。

这是明确的 SDR 取舍：普通图像亮部和白点恢复；超过显示范围的通道最终同白，但超白在裁剪前仍贡献 Bloom 光晕。未来曝光/保高光或 EDR 需显式输出合同，不恢复无条件压暗。现役 HDR Bloom 参数与 Display HDR 缺口仍待后继。

## 验证

证据根 `/private/tmp/mwx-sdr-output-20261006`，修后 App dylib SHA256 `580fcec269a67b883a14396b43ca53745d1da89cf87665a6f47048a2fa17308c`；运行与输入身份、日志和必要截图保留供独立复核。

- 修前真实 GPU 四项颜色断言失败；修前签名 App 对作者输入 `(1,0.25,0.5)` 输出 PNG `(191,64,128)`，实际白点压暗复现。
- 修后 Bloom/显示 GPU 13 项通过；真实 raw/history/reflection owner 5 项通过。验证正常灰/彩色逐位保持、有限裁剪、局部非有限处理、alpha、Bloom 后邻域增亮保留且不写回 source；多帧与半透明 raw 累积、取消/重置/旧 completion、暂停与精确大尺寸目标保护继续成立。
- 过程中修复旧 Bloom standalone fixture 缺外围 composition pin 类型导致的编译失败（该不使用的路径显式 trap），并更新两处 history 旧肩部曲线 oracle。新 halo 夹具最初在低分辨率/高强度下整幅过曝，改用低强度使可测邻域位于 SDR 范围；产品 Bloom 未调整。初次混合测试失败记录保留，最终通过分轮记录，不将旧失败日志称为全绿。
- 签名实际 App 四项通过：清底、持续累积、首次绘制后隐藏仍保留、暂停缩放且 VM 不前进；颜色恢复 `(255,64,128)`。一项“剔除 mapping 函数的派生 App”故障测试本批未跑，GPU 既有 pipeline/encoder 故障与恢复门仍通过。
- 真实 `2684431262` 原包隔离副本在修前/后各运行 10 秒，均正常启动/退出且 GPU drained、allocation failure=0。相同 PCM 夹具下青色/橙色/白色环与文字亮部恢复，光晕仍保留；动态相位不是逐像素锁定，不声明官方 parity 或性能改善。修前后均有25个material effect实际GPU完成、10个末端consumer进入合成；这不是整样本正确率。
- Debug 构建、代码健康、依赖、设计、防御、文档与目录布局门通过。结构 inventory 的 `shape-derived-analyzer-fleet` 66/65 是基线已有失败，本批未修改其 family 或放宽基线。文档路由31项中30通过，1项因四条历史README/机器索引权威不一致失败；`git show HEAD`与本批差异逐项相同，新增记录一致，未扩改旧文档职责。

## 后继

地球 `3437487219` 的 HDR slider 绑定 `general.bloomhdrstrength`，当前只消费标准 Bloom 参数；下一批先接通真实 HDR Bloom 配置与 typed 更新，验证其可见响应，再处理显示 EDR 和重型样本启动。此处为已读作者字段及当前消费者的静态缺口，不冒称运行已复现或修复。339 样本维持回归，完整兼容估计仍 70–75%（低置信），不因本批共享输出修复机械上调。


## HDR Bloom 参数与重建后继

基线 `8c7a1591`。HDR 五个作者字段此前未进入配置与 live consumer，Earth 三次 HDR slider 更新均拒绝。现在通过现役 Document → descriptor → property Program/typed snapshot → 唯一 Bloom owner 消费 strength、threshold、scatter、feather、iterations；按 authored HDR profile 选择预编译管线，不按16F格式或样本选择。标准 Bloom 保留，显示 EDR 未开放。

画面收益是高亮按作者参数产生并调节光晕，含零强度恢复；调节不重建场景。中间使用归一的多尺度凸组合，公共倍率在末端与强度/染色一起恢复；修正大扩散、小强度在半精度中提前截断造成的暗化。实际 GPU 反例原输出约19、修后约130（8位量化）；这只验证本项目重建算术，不是官方极值合同。预算替换先释放过期缓存引用，在途纹理仍沿现有 lease；所有中间 pass 完成才一次加回，失败保留原图。没有新增资源、时钟或输出 owner。

### 官方对照及边界

研究上下文只消费自有中性色块和官方客户端黑盒输出，没有读取私有实现表达。固定 WE 2.8.0.42、Steam build23967692；五字段分别省略的对照确认缺字段等价值为2/1/1.619/0.1/8，另有可区分替代值。均匀场约束用于排除递归累乘过亮，两组未参与推导的输入确认候选预测。13项固定均匀场GPU门在8位误差≤1内通过，不声称公式唯一或全图一致。两源像素的首级预滤改善阈值0、scatter2、8层等空间对照，基础/feather仍有局部误差，保留原始图与指标。

官方 iterations=0/1 出现与强度无关的全图 transfer，尚未解释；当前作者值低于2局部跳过 Bloom，保留源图且不编码，不猜全图gamma。物理层数被小图尺寸限制为1与作者请求1分别处理。精确空间核、该边界、EDR屏幕输出均未完成，后继继续研究；本批不是完整HDR兼容。

### 最终验证与身份

最终产品/测试 diff SHA256 `b7b345ed2b2f1847f2322755d8273ed04e598ca0b89c4dbcfc6f6436d5123349`；签名 Debug App dylib SHA256 `ff9eecf8aace979aa96f2fdded5971bf31ffea64e8b367abd7ce16de724d11a4`。本地证据根 `/private/tmp/mwx-hdr-bloom-20261006`，官方根 `/private/tmp/mwx-hdr-bloom-official-20261006`。

- 最终GPU19项通过：真实参数方向/量化对照、源alpha、每个编码失败及下一帧恢复、0/1局部退出、巨大层数、受限预算替换、大有限参数和零染色。独立审查发现的大scatter反例保留红证，再验修复；此前“加法混合必溢出”猜测被真实GPU反证，未为该猜测增加实现。
- descriptor/default/Codable18项、属性链72项、真实raw/history/reflection5项通过；后者在凸组合边界修正前运行，输出owner未再修改。最终Debug构建通过。独立只读审查逐路径核对冻结SHA，无剩余P1/P2。
- 最终签名App自有五字段三组更新全部接受，PID55157/window323041不变；周期截图分别呈现无额外光晕、宽光晕和窄光晕。截图完成日志有异步延迟，未将ready/after文件名等同参数采样时刻。先前非HDR profile反例三次拒绝HDR更新，未冒认消费者。
- 最终真实Earth `3437487219`：PID55090/window323028，hdr=0.25/1/0.5三次接受；地球轮廓、云层、银河、时钟可见，周期截图有随参数变化的发光差分。3个material effect GPU完成，2个终端消费，均与基线相同，不计为新增效果正确率。启动约10.1秒只描述本次隔离Debug入口，不能外推普通产品入口或全部重型样本启动修复。
- 最终真实 `2684431262`：PID55204/window323058，17层/25效果准备，青色/橙色/白色环、文字和粒子可见；保留实际声音/动态输入，未锁相位，不作逐像素或性能对照。三次最终App均exit0、surfacesAfter=0、gpuDrained=true。

### 后继与产物

下一批沿同一输出合同验证真正的显示 EDR：屏幕headroom、颜色空间、开关及SDR回退，再从普通产品入口复现星球/三体启动。当前HDR/SDR专项粗估约60%（工程里程碑判断，非样本正确率）；正常SDR白点和通用HDR Bloom已落地，EDR与剩余空间/边界未闭合。339完整视觉估计不因本批上调。

官方VM完整配置已恢复，哈希 `17B5CDBA85037555465F2330C90EF00B6346E5FCB5793823D2D63370E64DC7C1`，恢复最初suspended状态。最终日志、身份、必要图与反例整理为本地有界证据包，保留至2026-10-20；真实用户包不改。已停止的本轮App、样本副本、HOME和重试构建删除，只续用 `/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d` 一份构建缓存。


## 可选 EDR 实际显示后继（2026-10-06）

基线 `8490d789`。沿现役唯一 terminal mapper，将 display-referred sRGB 解码到固定的 extended-linear-sRGB/16F surface，普通颜色保持显示亮度，超白按所在屏幕当前 headroom 限制。设置新增“Scene HDR 显示”，默认允许支持的屏幕使用；作者 HDR/Bloom 与用户显示意图独立，关闭只回到普通亮度，不重建场景。potential 决定是否请求 EDR，current 决定帧上限，避免 current=1 阻止首次启用。屏幕通知和暂停重绘复用原失效入口，没有新增计时器、历史或输出 owner；线性导出失败拒绝提交，不呈现未解码 raw，不提升历史。诊断 PNG 转回普通 sRGB 预览。

### 验证与边界

- Metal 对照 ColorSync 的独立 sRGB/extended-linear 转换，普通色、超白、多档 headroom、非法 headroom、源及 alpha 保留均通过；连同既有 Bloom 共20项。真实 terminal helper/coordinator 的清底与累积模式分别注入 blit、encoder、pipeline 失败，确认拒绝发布且下一帧恢复，5项通过。capture 最初使用非法预乘夹具失败，改为产品不透明边界后1项通过，原失败日志保留。
- 签名 App 清底、持续累积、绘制后隐藏保留、暂停缩放且 VM 不前进，4项通过；普通色仍为 `(255,64,128)`。派生缺 mapping App 测试1项未运行；不替代真实 GPU 故障门。此轮集成构建早于后继调试菜单/暂停入口，渲染产品路径未变。
- 最终 Debug 构建 dylib SHA256 `32a83226e3c99627cc97eba17c43de94e49415fb297ceaf25794896323ce5770`。真实 App → coordinator → client → daemon 路径点击实际设置，前置构建（dylib `8992fb` 前缀）运行中 OFF/ON 同 PID62486；最终暂停测试 parent63915/daemon63918 两轮 OFF/ON 同帧313、同 raw allocation/member/sourceSubmission，`authoredDraw=false`、timer inactive，最终恢复 ON。全程仅一次 first-present，resume 成功、exit0，没有重载场景。测试入口补装现有主菜单并复用有界暂停参数，仅 DEBUG 产品入口生效。
- 本机支持 EDR 的内屏实际 surface 为 extended-linear-sRGB、rgba16Float，开关控制 `wantsExtendedDynamicRangeContent`，current headroom 随平台由1.2变化到约9.82。关闭为1。自有输入实际GPU读回峰值超过1；这确认扩展值进入真实呈现链，不是物理亮度测量。
- 真实 Earth `3437487219` 最终候选保留地球轮廓、云层、银河与时钟，实际显示纹理读回峰值1.708008；3个material effect完成、2个终端consumer继续执行。PNG仅SDR预览，不能展示或证明屏幕EDR峰值。单次隔离Debug Host入口启动约10.3秒，不能外推普通入口或重型样本问题已解决。

当前 HDR/SDR 专项工程进度粗估约80%，不是全样本正确率。已落地普通SDR颜色恢复、通用作者HDR Bloom与可选EDR实际输出；剩余精确空间核、iterations=0/1官方行为、多屏/SDR设备与物理亮度验收继续开放。下一批按用户优先级从普通产品入口复现星球/三体启动失败，定位最早阻断并修共享责任。339估计不随此批上调。

产品/测试15路径冻结SHA逐项通过独立只读终审，无阻断P1/P2；代码健康、依赖、防御、设计、文档和测试断言门通过。证据根 `/private/tmp/mwx-edr-output-20261006`，最终日志、必要图、身份、失败夹具记录及复验输入整理为 `runtime-evidence.zip`，保留至2026-10-20；既有集中证据预算不扩大。已结束的候选App、真实样本副本、临时HOME和重复截图清理；连续迭代只续用此前登记的构建缓存。真实用户样本未修改，未推送。

<a id="ldr-bloom-spatial"></a>

## 2026-10-09 LDR Bloom 采样尺寸纠正

基线 `2f4ab514`。U12 `3477054430` 关闭 Bloom 后，窗区与官方同机位 sRGB 平均 RGB 差不足0.4/255；开启时仍约(+9.91,+10.56,+4.67)/255。首错属于既有 LDR Bloom 空间处理，不再改模型材质或发光输入。保留原四 pass、权重、阈值、强度、alpha 和唯一终端合成，明亮提取与两个方向 blur 改按真实 completed-source 尺寸计算采样间距；第二张中间纹理由1/16改为1/8，沿原预算/缓存准备。没有新增视觉分派或 owner，HDR 分支不变；4K BGRA8 中间存储增加约0.37 MiB，未宣称性能提升。

官方2.8.0.42自有灰128/白255矩形，在1210×786和800×450观察到光晕宽度按实际像素保持、横纵接近。使用嵌入 ICC→sRGB、无缩放视口与原始截图，未消费私有实现。只改采样间距的候选仍有白色剖面最大12/255误差；连同1/8目标后，三个输入两轴各64个边外像素的最大差均≤2/255。单张JPEG捕获的相位/压缩精度不支持精确核或任意分辨率parity。早期以顶层 brightness=2制造白源的输入在官方仍为灰，已排除该组能量结论；最终白控使用实际255纹理。该 brightness/profile 输入差异保留后继，不据此修改HDR或增益。

验证与身份：

- 新GPU剖面门在旧产品上31处反例；修后整 Bloom module 21项通过，含三个输入×两轴×七距离、中心及alpha、HDR、零贡献、缓存与失败恢复。另现有容量/阴影共存7项通过。
- 隔离checkout的签名Debug build成功，4240项产品/项目输入构建前后不变；dylib `b709223a458b8032459cbf88d11fd8fc1138439983714ce44ae4e293474543ff`。产品Swift SHA `5145347881d7938c2b1280c8dbe5dfd1a0b540285376b79292f70c01d1f5d8c9`，Metal `7899a573257ad4611579398d1c96e000704c622de798ad0b2dab59210ddf1140`。并行Web在途代码不属于该App身份。
- U12保持前批作者原camera path，只关闭shake以固定机位；baseline/Bloom-off/Fog-off三次实际App均含resize、首/后帧和排空退出。开Bloom窗区差降至(-.08,+.07,-.23)/255；关Fog窗区差从(9.64,10.26,7.97)降至(-.08,.11,-.45)。五个固定ROI在开雾基线下平均差绝对值均<.6/255；关Bloom五ROI修前后逐像素相同。真实App自有白色开/关也验证，1210视口光晕复现GPU剖面。
- 243包只读声明扫描：19个默认LDR Bloom，17个标准参数静态可解，2个strength动态；这只是潜在覆盖，不是19个画面验收。对U12猫身/耳机仍有可见受光差异，头部姿态/时间也未冻结；下一批先分离这些变量，再沿现light/material消费者修复。完整文字/媒体、交互、普通UI→daemon与长期性能不在本片验收范围。

本机收据 `.artifacts/tmp/u12-window-residual-20261009`：`official/official-observables.json` SHA `5ec819dbd1ddc30c8ee0a647733d7f6d559a33c263e35cf217c21712becbb5e7`、`bloom-regression-results.json` SHA `7ae2a7c0b8c4ba4a877a394a57f7361e750b04d7036106f209154c4fdb05343b`、`u12-final-comparison.json`、构建/运行及独审记录。官方临时窗口和自有guest目录已清理、VM已暂停；未知归属`.mimosa`218B保留，仓库residue门仍报告它，不把此存量说成全门通过。
