<!-- document-role: historical-evidence -->
# Default 2D camera 输入与画布适屏

> **历史证据 — 非现役入口**。截止2026-10-16。限定输入合同归[D4](../roadmap/batch2/script-component-api-design.md#default-2d-camera-inputs)，当前消费归[输入覆盖](../capabilities/runtime-input-property-coverage.md#3-scene-与-camera-输入)，未验视觉与后继归[现役队列](../roadmap/scene-open-breakpoint-queue.md)。不将正常比例裁切、作者留底与引擎输入缺口合并裁决。

## 通用修复

旧路径仅有Combined Timeline向`.camera(.origin/.zoom)`写值；无动画的default path基值及direct Slider zoom未接，origin脚本虽成功却落到普通`.layer.origin`，相机仍用identity。现准备期在合法正交画布、唯一default path中按字段确定输入，静态值、Slider zoom、原Vector返回值与原Combined共用definition、resolver、事务和camera frame；普通帧不重解析或重找path，不修改cover公式或作者布局。

Vector输出迁入camera时显式保留源层identity，thisLayer/thisObject、peer副作用、Cursor/Media/Puppet配置与退休仍归原owner。只有origin真正准入才退出旧层writer；不支持的origin完整保留原层owner、definition、getter/setter、current和world路由，zoom可独立准入。静态独审发现的字段退旧过早及peer身份丢失均在冻结v3前修正。

camera origin handle setter仍按原preflight整owner包拒绝；此片只支持返回型origin，不开放ICamera JS handle、任意动画、多camera/native selection。Combined准入、clock与composition不变，非法值和冲突沿原局部失败/撤回，不新增VM、相机、时钟或renderer fallback。

## 304：倍率输入恢复与真实输出

原包project SHA256 `f352e73bf06c9772d33758a61e597281a0d6ba77883e3bf45242c4a929331537`，pkg `3a374f008b1b2497902620cf874a7f35e4c9f3aaf83d97ec5cfa915bb50dc791`。白名单metadata显示3840×2160画布、唯一default camera层2847；origin为init-only wrapper，基值`0 0 500`，direct zoom对应Slider默认0.73，范围0.73…1。没有读取作者脚本表达式。

旧App原样图四周放大裁切；候选原包的camera origin回调1次completed，typed输入/输出均(0,0,500)。根代理实看默认0.73、热改1、恢复0.73三图：塔底、海平面及星光进入画面；改1时再次放大，恢复时构图回到默认。两次live update均accepted，同一window43201/1surface。该入口是隔离Debug属性更新，不冒充原生面板操作。

候选PID23684，ready98.821160s、总106.796802s；首帧及下一帧各58条graph-execution succeeded，surface GPU completed。exit0/noTimeout、inputDrift=[]、ownedGroupGone、停止后surfaces0且gpuDrained。冷shader环境与旧暖缓存不同，时长不作性能对照。layer544原event异常及其他视觉/交互仍保留，不关闭整样本。

官方2.8.0.42以公开CLI单独窗口打开原包，actual client1512×982，与候选3024×1964同aspect；根代理实看塔底/海平面及主体尺度相近。官方窗口右侧约120px被客户端库窗口遮挡，pointer/动画相位未同步；不是全四角或逐像素parity。目录旧官方截图还包含窗口边框，实际内容aspect约1.832，与当前1.540不同，不能整张PNG直接比较。

## 169：露底资格与正常比例差异

原包project SHA256 `bdcc40ce74fbb2b763c7c47f03ea893d0c82e4ab75f33e227f3fe70da336210d`，pkg `05f2d04e22307cc092818a51cf70e20e729b4ee8a22dee24ff6650c48c39e01a`。作者画布4000×4268，背景同尺寸、origin(2000,1200,0)，没有脚本/default path；静态数据所得顶部世界间隙98.942，对3024×1964预期74.8px。原样原生实图为75px灰带，背景源alpha全255。

官方同aspect actual client1512×982也有约35–37px灰带，占高3.56–3.77%；原生为3.82%，差不超过预先限定1个百分点。只证明此比例双方均留底，不证明作者意图、所有比例或完整视觉。没有改背景origin、canvas、cover或强制拉伸遮灰。

169原生PID17287 ready7.0774s/总16.597345s，exit0、GPU排空与输入稳定。官方仅操作自有playInWindow窗口，按exact title关闭后数量0；169与304 guest副本/helper均精确清理，用户原壁纸/设置未改，VM按要求保持运行。

## 验收与独立输入

产品冻结v3覆盖27个Swift及layout manifest，SHA256 `d90aad3c14d7e3aa4fc8b026597644fd6def9ef79bd5acddf5cbe843c9105cac`。独立静态GO，28路径前后无漂移；记录`independent-review-prepared-puppet.json`。Debug build PASS33.854544s、4281inputs/drift[]，deep/strict签名PASS；exe SHA256 `778e07f054ec858a1533360870d03a6cc9035ca2f1398a0af0dc6e218ebdc09d`，dylib `324f1152ecfe84cad0c5f779726bdcc5c681bafaad842125d355845088e309a2`。

新真实parser/descriptor/property/Vector C owner/resolver/camera-frame门3/3 PASS88.298s、155inputs/drift[]。63事实全true，改名/等价表达式两变体的origin跨三帧保持(120,-40,620)，zoom0.73→1→0.8；健康peer下一cadence、origin-Z0完整旧链、非法shape/zoom/重复path/native、camera setter及throw整包撤回通过。前两次fixture失败分别来自value-only观察器及未传production preliminary base，修正测试编排而未降低数值断言；原失败日志保留。既有Combined原method另1/1 PASS10.620s、52inputs/drift[]；首次0test编译失败来自旧user DTO/resolver缺正式Contract，仅将注册替换为现正式family，原SCENE_FIXTURE和方法AST与HEAD相同。

未参与修法的3147346398使用同一候选App：PID24703，ready4.307510s/总12.285260s、exit0/noTimeout、inputDrift=[]、ownedGroupGone、GPU排空。首/后帧graph及surface均completed；根代理实看火光/砖墙、时钟日期与music line保留，不证明音频/完整parity。跨比例数值与暂停resize后继分列，不以单物理屏两样本证明全部适屏。

## 不同比例核验与暂停尺寸后继

普通播放尺寸主链独立只读审覆盖canvas/camera、point→backing调用、source逻辑/物理extent、MVP、末compositor与等尺寸display mapping，未发现额外fit或二次裁切。居中cover跨比例裁掉一轴属正常；偏置/旋转/视差且没有足够overscan可露clear area，不私自移动或拉伸。screen anchor加非零camera XY仍须官方自有组合资格，不由helper缺参直接改公式。

最近CameraFrame四方法PASS2.559s；Anchor两方法PASS，含真实Metal像素覆盖，未重复。首组合invocation中Camera旧载体因已退役的空Snapshot initializer而编译受阻，Anchor两门已通过；仅将两处`.init()`改正式`.empty(frameIndex:0)`后重跑受阻四门，原方法/输入不变。原日志及18inputs稳定收据在`aspect-review/summary.json`。

独立小探针直接编译生产CameraFrame/Projection八源，六profile共34事实全true，compile/run2.152s：1920×1080、origin(120,-40,620)、zoom0.8在960×540/1260×540/540×960/1920×1080的visible half依次(1200,675)/(1200,514.286)/(379.688,675)/(1200,675)。中心/边界NDC正确、像素X/Y等比例、z=0平面两种投影XY一致。304的1512×982与3024×1964、zoom0.73均为half(2277.934,1479.452)，每100世界单位像素约33.188→66.376。只证明投影密度等价，不冒充AppKit Retina切换、真实跨屏或完整pointer事件。

普通SDR暂停resize另有已复现的首错：实际drawable尺寸变化后未通知原`.surface` invalidator，已停driver继续保留旧图。camera-v3签名App基线28.888192s，App exit0/GPU排空/ownedGroupGone/inputs稳定；两次resize accepted，暂停内零resize导出、零VM更新、零capture queue拒绝，恢复后两图才导出且均为原3024×1964。原HDR clear=false/reflection分支已reset通知，不能用它代表普通SDR。

局部修正仅在原size owner的普通changed分支通知一次原invalidator；HDR/reflection仍走原allocation reset，同尺寸静默。Session原异步weak/exact-surface调度复用暂停snapshot，以当前extent重算camera，不在resize内同步render或新增driver/VM更新。两文件独立静态GO/sourceDrift=[]；候选SDR门PASS24.893s，两PNG均暂停内完成，实际1512×982→3024×1964，白卡边界缩半/恢复且VM witness不更新。原HDR门PASS36.463s，暂停内两次mapped GPU completion同frame49、allocation2/3，原像素断言通过；第二张PNG异步导出到resume后，不称两HDR文件均暂停内完成。两次inputs稳定、ownedGroupGone，deep/strict签名PASS。不将等比resize称为跨比例App运行。

候选Debug build PASS25.296641s、4281inputs/drift[]；exe SHA256 `837719b32c80c380abc56368a803d9ec1ad9cabe35e8489670df56f343a5a941`，dylib `aa0f7d5cab4afc01db03d2ca771f7c975fa98ca55a4ae0825bbbdcb006d11256`。独立原包314再跑PID29036：ready4.297019s/总12.273675s、exit0/无timeout/无输入漂移/ownedGroupGone/GPU排空；根代理实看火光、砖墙、时钟日期和music line仍在。全部时长仅为验收身份，不认领性能收益。暂停修正收据根`.artifacts/tmp/paused-drawable-resize-20261016/`，`candidate-summary.json`与`independent-runtime-summary.json`绑定实际结果；已精确删353,820,166逻辑B临时环境/副本/raw诊断，日志gzip回读通过，保必要基线/候选PNG与收据约17.0MiB，见`cleanup.json`。

屏幕anchor与camera XY自有官方资格在零组即失败：固定客户端实际1512×982窗口全黑、无card/文字正控，并出现0xC0000005/read0崩溃提示。按预登记停止，X/Y未执行，没有相机符号或anchor行为结论，不据此改项目投影。输入/窗口/原图及失败身份仅保`.artifacts/tmp/camera-screen-anchor-qualification-20261016/`；共享receiver的精确窗口关闭受阻时保最小gueststage，不强杀用户客户端或关闭VM。原U43已证输入缺口/暂停resize修复及169露底资格退出待修队列；更宽golden缺失只保能力边界，不冒充新视觉缺陷。

## 证据去留

当前修复收据根`.artifacts/tmp/default-2d-camera-inputs-20261016/`，中性运行投影`candidate-runtime-summary.json`；本轮已结束环境/副本及raw诊断精确删除540,298,540逻辑B，日志回读验证gzip，仅保三张必要实图和冻结/测试/独审/执行收据，低于32MiB，见`cleanup.json`；旧图沿用已保留的`.artifacts/tmp/vec3-vec2-arithmetic-20261016/candidate304/scene-after-window.png`。169资格及官方同aspect基准分别在`.artifacts/tmp/169-screen-fit-qualification-20261016/`、`.artifacts/tmp/304-screen-fit-qualification-20261016/`，仅保必要实图、压缩日志和身份收据。

唯一连续构建缓存保留`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`供后继迭代，用户原件只读；此记录不含CPU/GPU/内存/启动收益结论。
