<!-- document-role: historical-evidence -->
# Default 2D camera 输入与画布适屏

> **历史证据 — 非现役入口**。截止2026-10-16。限定输入合同归[D4](../roadmap/batch2/script-component-api-design.md#default-2d-camera-inputs)，当前消费归[输入覆盖](../capabilities/runtime-input-property-coverage.md#3-scene-与-camera-输入)，未验视觉与后继归[队列U43](../roadmap/scene-open-breakpoint-queue.md)。不将正常比例裁切、作者留底与引擎输入缺口合并裁决。

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

## 证据去留

当前修复收据根`.artifacts/tmp/default-2d-camera-inputs-20261016/`，中性运行投影`candidate-runtime-summary.json`；本轮已结束环境/副本及raw诊断精确删除540,298,540逻辑B，日志回读验证gzip，仅保三张必要实图和冻结/测试/独审/执行收据，低于32MiB，见`cleanup.json`；旧图沿用已保留的`.artifacts/tmp/vec3-vec2-arithmetic-20261016/candidate304/scene-after-window.png`。169资格及官方同aspect基准分别在`.artifacts/tmp/169-screen-fit-qualification-20261016/`、`.artifacts/tmp/304-screen-fit-qualification-20261016/`，仅保必要实图、压缩日志和身份收据。

唯一连续构建缓存保留`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`供后继迭代，用户原件只读；此记录不含CPU/GPU/内存/启动收益结论。
