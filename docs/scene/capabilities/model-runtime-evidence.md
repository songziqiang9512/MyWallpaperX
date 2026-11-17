# 模型运行证据

<!-- document-role: current-state -->

<a id="scope"></a>
本页是 Direct/StaticModel 的命名输入、材质、相机深度和局部合成运行范围的唯一证据正文。目标与当前能力归[模型合同](advanced-object-coverage.md#models)，待办只归[开放队列](../roadmap/scene-open-breakpoint-queue.md)；其它系统及通用限制见[运行证据索引](runtime-evidence-current.md)。每项结论绑定具体构建与输入，较早的限定运行不授当前未执行组合。

## <a id="nested-model-albedo"></a>模型两级颜色供货

3557068717 原project/pkg、3024×1964、当地18:57:13，旧签名exe `4b8b07a5…5da9` 与新 `6720e5d0…48fc` 的F972均完成、零截断并排空，metallib相同。旧237无draw，新424先供420，420发布并绑定237，选中帧237进入主目标。1280×831终端图的北美、南美区域暖色像素0→1982、0→603。日面见[点光衰减](runtime-evidence-current.md#point-falloff)。原生夹具的原名/改名、运行中退役直接上游与旧独立供货均通过，独立3470948192 F972保93发布、115绑定和draw。Debug构建、最近计划与自有shader四方法通过；相邻43项中两条几何/父层候选断言在未修改HEAD同样失败。Windows参考为18:57:00且画幅不同，仅作视觉参照。定格遮挡基线保留。收据归`.artifacts/scene-world-model-first-20261109/evidence.zip`。

## <a id="world-model-sample-triage"></a>星空样本定向复跑

3455121165原包普通预览 `a7b5879d…2f04` F953已编码107/199→main，GPU完成/零截断；296淡入uniform近1不证明glyph/投影。原收据归`.artifacts/scene-evidence/runs/scene-world-followup-normal-20261109/`。3453730450旧 `359404fb…c9e3` F967平灰；2026-11-14现役签名Debug `e4cc1a67…daf57` 唯一20s/after17低观测场，3024×1964的F964/request1捕获与seal同CB/纹理，GPU完成/零截断并排空，1280×831 PNG见受光月球、轨道、星点、标题与时钟。未授parity；证据/独审归`.artifacts/scene-terminal-345-20261114/`。

## <a id="model-screen-reflection"></a>静态模型屏幕反射

[材质及历史合同](advanced-object-coverage.md#static-model-screen-reflection)。3470948192原包、同画幅3024×1964及固定墙钟，签名exe `a7b5879d…2f04`→`316b1116…6959`，新metallib `5dac46d7…f8a2`。自然场景时间F970→F960，93先供115，模型14在同一主画布读取F959完成的环境颜色，GPU完成、零截断并排空。1280×831终端图上沿luma 0→20.56、尖端0.06→112.11、暗心0→2.42，星线仍被遮挡。独立3455121165 F972双跑，84反射强度为零且保持绘制，太阳397保持。原生开关、零强度、改名、尺寸切换首帧与稳定帧、模型深度和原图像历史邻例通过。官版2.8.0.42在原设置的一字节开→关→开证实灰紫轮廓随反射改变，输入相位和尖端强度未配对。收据归`.artifacts/scene-world-followup-20261109/evidence.zip`。

## 命名背景图的局部尺寸 <a id="named-background-source-extent"></a>

按[局部供货合同](render-graph-shader-coverage.md#named-geometry-local-raster)，原FramePreflight非solid分支用已准备的graph-output provider角色选择layer-local source extent；只有普通非named终端继续按原world列长量化显示密度。原captured matrix/Resolution、source raster、2048等比上限、graph/named发布及主合成不变；退出共享纹理按世界缩放膨胀的目标选择，无新owner/状态/缓存，唯一产品净−4行。

旧同App控制的384×192红绿16条带原位健康，加X100/Y.007后中心混成70/30及约50/50，实际像素红；首失败后未运行旧父层变体。当前3场（原位、缩放、等价父层+ID/资源/变量改名）47.713s通过，6完整PNG逐字节相同、条带为字面100/0交替，实际source/effect/publication/model皆384×192，同main/seal/GPUcompleted/trunc0与健康阴影。另普通canonical/fragment-raster及visible parent的一图供主合成/child/external三方法53.613s通过；raw无效果、Geometry前分支未改，复用其原有效资格，不冒本批新跑。当前build28.259s且源/project/锁不变、签名与原helpers通过；execcc41f51…db99/dylib1c90195e…eff4，metallib仍cd47906e…30b4。

原347同project/pkg及固定控制、实际1512×982稳定帧，93的3840×1920源从2048×10恢复为2048×1024 graph/named并供115，画面由稀疏宽软变细密线条，水滴和钟日/公式保留。201=.2、模型14原环境反射与主画布/seal/GPU完成、零截断并排空；resize仍保原4fail，仅授成功终端。自然相位和ICC未严格配对，不将全图RGB差、官方截图或现在的反射外观冒成全水滴一致；后续默认HDR响应见[模型发光](#model-hdr-emissive-gain)，外晕与细纹仍归队列。独立原343原三摘要、五秒PASS，地表/云/暗面/大气/星空与钟日完整；不授原全视角或所有visible provider锐度。控制/源/构建及独审归`.artifacts/scene-named-background-extent-20261116/evidence.zip`，真实终端归`.artifacts/scene-evidence/runs/scene-named-background-extent-20261116`。

## <a id="model-startup-366"></a>静态模型接口冷准备 · 3662790108

原三摘要，签名优化App `b00688c6…384d7d`→`95c835c6…d3dca0`，metallib字节相同。旧准备线程采样743栈点中560在静态模型材质绑定编译（539在接口证明），顶点读取13。相同原包351个模型pass只用1份合同与8组完整combos。两对串行无采样实测，默认model-build 7.039→2.736秒、首GPU（从accepted）10.998→6.861秒、Ready 11.670→7.566秒。关闭作者片头的同设置对照分别7.493→2.690、11.540→6.687、12.202→7.348秒。四次570条material pass描述完全相同，含341接纳、10回退与8个默认slot0。原生绑定11项和取消门通过。相同SceneTime3，四次捕获均实际编码相同10个模型层，片头RGBA一致，正文仅右侧控件一条窄区不同。独立3589454154同原三摘要，11个模型材质接纳，土星环462与陨石479到main。五次按各自请求/Surface/CB核封口、GPU完成、零截断与排空。原采样在`.artifacts/scene-model-startup-3662790108-20261109/evidence.zip`，无采样、截图与绑定收据在`.artifacts/scene-model-interface-reuse-20261109/evidence.zip`。未测长稳FPS、能耗或交互。

<a id="model-subtree-raster"></a>
## 模型的局部 source、深度与父组显隐

[原局部合成合同](advanced-object-coverage.md#model-subtree-raster)沿 nearest MainPass 的保 Z/W VP、XY 绕序及 pass depth 执行，world/normal/light/shadow 与输出 owner 不变。父组动态准备退出单 prepared leaf 例外和重复初始 visible 门，普通帧无新增检查/状态。该批签名Debug CDHash4067ed05…ac05、exec5fc7e94e…b021、dylibfc01c2f7…94cb、metallibc83cb6aa…ca45，4413构建输入稳定。原完整身份、失败、收据与独审保于 `.artifacts/scene-model-parent-visibility-20261107/`。

五个同输入自有App控制的15张PNG/75固定ROI误差0，覆盖父组热显隐、ID/资源/等价表达式改名、冷Bool、父visibility回调及外部peer.origin setter；child false与健康peer保持。旧暖组关闭/冷Bool开启被拒，外部setter缺父source/Program/tail且为[204,25,51]；当前沿model→200×120组source→capture→e0/m0/n0/slot0→group/tail→main/seal/GPU为[102,153,51]，与独立字面reference一致。父自身回调旧已正确，只作回归。每场同window/Surface、一次激活，request/CB和stream/generation匹配，bracket≤.267124秒、零截断并排空；cold早期depth cohort为空，不授冷深度。67项最近原生方法与三场原model App的7图/71ROI通过，保near/far、nonwriting半alpha、独立组depth、局部坏child、Project非均匀/镜像单面与model自身显隐；坏model/image同key仍整笔拒绝，source无Program保真实容量拒绝。独立3437487219/3477054430同三摘要四秒回归均完整出图、实际模型到main/GPU并排空。这不授作者model-group正命中、全部cold/初始关闭effect、组内image终端共享depth、外部材质writer全场景、UI/IPC、官方像素或性能；其余组合归队列。

## 世界模型材质的实际消费 <a id="model-normal-map"></a>

2026-11-14按[原模型材质设计](advanced-object-coverage.md#model-normal-map)接通stock generic4静态surface的slot1，准备期保.normal/data、独立UV/sampler与typed TEX编码，实际TBN消费原切线/逆转置法线及镜像手性；退“有normal即拒reflection”，不改几何depth/caster/ambient方向。五产品净+89行，无新owner/cache/PSO；无图仍多32B uniform、varying和固定绑定，不授零成本或性能收益。普通Debug构建28.56s通过，五产品及project/锁文件构建前后一致；签名/原helper验证通过，exec6169cbdb…d1df、dylib6257b6c9…c099、metallibe451f575…2848。基础pipeline8项及相邻混合/发光/三灯阴影/来源15项通过，最终独审无阻断发现；新生产资源→原renderer/Metal门6方法、35实际GPU输入，覆盖五编码、相反方向、手性/镜像/旋转/斜切线非均匀、独立UV/采样、关闭/缺图/custom、环境、alpha/depth、反射色带与完整改名。原四轮载体编译/输入/相机失败保留，最终普通model的utilityLayer=nil及native投影资格成立；未放宽像素阈值。原包3453730450与3477054430修改前/后各5秒PASS：当前F143的53/77分别4096×2048 RG与1024² AG、F191的47为1024² RG实际绑定slot7→main/seal、同request/CB/Surface/GPU completed、零截断并排空。两张当前PNG可见月球/星空与猫/楼体，前后相位不同不授精确像素差。独立3437487219无normal保持完整地球/星空/时钟；3557068717晚相位156/270的2560×1440 AG及三反射进入main/GPU，但该构建424e0独立MSL varying编译失败，保两项CHECK，不记整景PASS；该断点后续资格见[相位供货](#model-mask-phase)。标准TBN/普通图片RGB为自有算法；动态MR、其它材质族/分量图与官方像素未授。App原报告/图/日志归 `.artifacts/scene-evidence/runs/scene-model-normal-20261114`，产品/载体失败与原生结果归 `.artifacts/scene-model-normal-20261114`；最终审查与相邻门结果同该包。

**加法颜色 <a id="model-additive-blend"></a>（2026-11-14）**：已解析additive沿原Frame选冷PSO的RGB one/one，alpha-over、depth/cull/caster不变；普通帧无解析/新pass。同payload旧三产品快照保8条像素失败，当前6方法/33GPU行通过：full红叠蓝由[255,0,0,255]→[255,0,255,255]，half由[128,0,128,255]→[128,0,255,255]，半蓝背景从[128,0,64,191]→[128,0,128,191]，深度逐值不变；改名、零覆盖、禁写及近挡远邻例保持。法线门6方法/36行通过，新增实际加法反射PSO在红64背景保R64/B23与原alpha/depth，未复制blend数学。首Debug构建检测源码漂移已作废；最终24.827s构建输入稳定，签名/原helpers通过，exece45781b8…98de、dylibb0b9e761…c5ec，metallib与上一法线批同字节。原包3477054430及独立3437487219各4秒PASS、PNG完整并排空；F190/request1的68实取32²颜色，以additive状态进入main/seal和CB532772587264/GPU完成、零截断，343 F153的112/114保translucent。星片实际为受光/雾后白色、alpha1，slot2空不授emissivebrightness10贡献；未配对逐星ROI，不认领黑天多数星点变化或整景增亮。反射和加法全场共存可连带准备一份未被具体part使用的组合PSO，固定有界，不称逐组合最小化。最终独审无阻断；源/8失败/69当前GPU行、无效构建及正式构建归 `.artifacts/scene-model-additive-20261114`，实际App原报告/图归 `.artifacts/scene-evidence/runs/scene-model-additive-20261114`；未授官方像素、性能或更多材质模式。

## 模型的测试与写深度 <a id="model-depth-state"></a>

模型沿[深度设计](advanced-object-coverage.md#model-depth-state)冷准备有效 test/write，原 Frame/四 stencil 消费，no-test 模型截断透明 image 重排；真实 opaque 的体积 camera-depth 按颜色绘制顺序复用相同测试状态。2026-11-14四产品净+20行，仅新增一份 always/write stencil，不增 PSO、池、owner 或热解析；默认与 disabled/false/off/0 别名保留。原48行/9方法及 point-volume21行/6方法的 normal 四态、alias/未知、改名、alpha0、加法及体积结果仍有效，原 translucent 写入预期由[当前对照](#model-translucent-camera-depth)替换。normal far write-only由红/nearDepth .51000011 变蓝/farDepth .48999989，no-test/no-write为蓝且保 nearDepth。真实 Frame 收集与 encodeVolumeOccluderDepth 的近/远原生相机控制中，远 no-test writer 的 color/camera depth 同为 .0000809322737；不写时两者保近 .000101142461，1e-7容差，非复制比较算法。PointVolume 的两新顺序控制同时验证实际散射截止，阴影灯空间比较不变。

旧 App 的两新方法分别因四区全红和错误重排而失败；候选两方法、四场实际 App 及8PNG通过。近红→四材质远蓝→中绿的四组合为 R/G/B/R，完整 model/material/texture/ID 改名相同；排序只切 model test，off 按511/512/513为[0,128,127]，on保合法512/513/511为[128,64,63]，均在事前 delta4 内。输入、源码与 App 身份固定，ready/after像素一致，同 request/CB/主目标/seal/GPU完成与排空逐图核对。普通 Debug 28.045s、四产品/project/锁文件前后一致，签名/原helpers验证通过；exec4525130e…c5a0、dylib907d2e01…9c5a，metallib仍e451f575…2848。作者3453730450/3437487219各5秒PASS，F165/CB532952090368和F156/CB533511734144的模型保持test/write=true、主景与同帧main/seal/GPU完整，零截断并排空，只授enabled原路径回归。独立产品/测试/图像审查无阻断；官方disabled语义、文字disabled排序、任意透明体积与性能未授。

自有输入、失败、原生/App像素、构建身份与独审保于 `.artifacts/scene-model-depth-state-20261114`；真实作者原报告、必要图与日志归 `.artifacts/scene-evidence/runs/scene-model-depth-state-20261114`。

### 半透明模型的相机深度 <a id="model-translucent-camera-depth"></a>

2026-11-15，3662790108同原资源、仅作者初始聚焦3的地球近景，旧App亮半球有密集斜纹，官方2.8.0.42实际窗口及独立观察无此纹。1665夜灯真实关闭仍有斜纹，分别关云1877或模型大气1881则消失；两者相同几何/半径，首错是透明面互写深度。以两份未改原MDL、自有近红透明/远蓝实体及健康peer构成六场，完整取景资格后，官方两顺序×写入存储位及后透明测试开关的颜色为蓝/蓝/混/混/蓝/混；旧Mac首场为红，其余相同。首版相机不一致导致裁剪的六场已排除，不作语义依据。官方记录为原生窗口人工观察，无本地截图文件，不授逐字节官方像素。

原 compileMaterialPlan 一次准备 translucent 有效 writesDepth=false，保 authored test、顺序、normal/additive 与独立灯空间coverage；唯一产品净+1行，无新热工作、状态、ABI、PSO或资源。最终同一原生门10方法/54输入，旧源6失败→新源全过；原48输入未改，只替换错误透明写深度预期并补六个变体。近红透明先画后实体蓝的实际RGBA从[128,0,0,128]→[0,0,255,255]，深度.51000011→.48999989；后透明开启测试仍被前实体挡住，关闭则混合。其余normal四态、改名/大小写空白、未知、alpha0、加法与volume邻例保持；本批不重授三灯map运行。

普通Debug25.151s输入稳定、签名及原helpers通过，exec `fbca5138…7256`、dylib `3fcdbcc8…13aa`，metallib与旧App相同。新App同六输入RGBA符合上述类别，首场逐像素等于旧关闭写入场，其余五场逐像素不变。相同作者地球输入5秒终端图斜纹消失，保连续地形/云及暗面城市灯；土星保完整受光球面与星环，独立原3477054430保猫、楼体、月球。各场同capture主目标/seal/CB与GPU完成、零截断并排空。前后自然相位未严格配对，不授原景精确像素差；太阳穿透、全部镜头、第二次标题及366整体官方一致仍开放。必要输入、旧红/新绿、实际图、身份与独审归 `.artifacts/scene-model-translucent-depth-20261115`；独立原作者报告归 `.artifacts/scene-evidence/runs/scene-model-translucent-depth-20261115`。

## 366逐焦点模型核对 <a id="solar-model-views"></a>

作者69个可请求视图包括总览、太阳、8行星、5矮行星、22卫星及32航天器，其中9个航天器没有作者MDL；73个模型对象不是同帧可见数。首15目标（含月球）两相反姿态均有15个实际稳定选帧，绑定当时faf7208/56558eed及metallib17c2ed96；A整轮因8次superseded截图FAIL，B采集PASS，不能将选中成功改记整轮A通过。原图/源身份及实际encoded后继main/seal/GPU摘录归`.artifacts/scene-solar-first15-audit-20261115`两份独立run包；A有独立模型审查，B未授完整独审。四矮行星的当前修正另归[径向证据](#spot-radial-falloff)，不沿用旧黑图授正常。

a58c06080同签名Debug（exe453a90b9/dylib8ebc6f49/metallibcd47906e），私有驱动沿原请求核火卫一/二及木卫一至四的135°/315°相反姿态，原847作者对象、1174非scene条目和project不变；intro/spin关闭且只冻结作者simulation，Date/原runtime继续。两轮采集均PASS，12目标各有strict实际focus/key/transition完成、READY→END HOLD、实际纹理model draw→同request/PID/CB/Surface/main/seal/GPUcompleted/trunc0及排空；四次父route单独收据不冒父模型可见资格。B六体地形/坑纹/裂纹连续，Phobos前景不规则岩体遮住后方巨大Mars；A为薄亮缘或完整遮星夜面，不将暗面判缺图。12原PNG与查看副本逐RGBA相同，独立实际审查f6fce8f3…3852b无新模型缺陷；未改产品、未补构建，不授全表面/全部视角/实际双击或官方逐像素一致。

卫星输入、12原图/原行摘录与独审归`.artifacts/scene-solar-moons-20261115/first6.zip`（15,382,045B，SHA236e0914…6db0），全成员校验后清理两轮运行目录和两个pkg副本；保重建配方与未解决UI最小原图。另见钟和右面板缺片，尚未证明与模型或既有文字排序同因，问题只归[开放队列](../roadmap/scene-open-breakpoint-queue.md#implementation-gaps)。

同7159签名App补沿原3秒请求的Saturn→Titan→Iapetus→Uranus→Neptune→Saturn，原847对象、project及1174非scene条目保持；只替换私有驱动的两处原字节跨度。109.819s整轮PASS、22原PNG无截图失败，6×5条请求/移动/匹配/READY/END实际记录闭合。6个HOLD均有同request/PID/CB/main/seal/GPUcompleted、trunc0及排空，5个不同球体未见新纹理/外缘缺口；移动候选仅小Saturn在画幅内，其余5体没有可辨轮廓，不授黄色/蓝色完整3秒同步或全部镜头正常。独审a32c6b57…c8944无该范围新阻断。8必要原PNG、30状态记录、12候选帧原事件和输入重建/身份归`.artifacts/scene-solar-atmosphere-views-20261115/evidence.zip`；未留569MB包或全日志。按用户最新顺序先转347水滴，余15卫星B及航天器继续留队列，不再作转向硬前置。

2026-11-16同15e4291c0签名App（exe3203f653/dylib65c79a02/metallibbfb78133）核六个航天器：TDRS-9、JWST、ISS、Tiangong、Hubble、LRO。原847对象、project和1174非scene条目不变，只在既有私有驱动的固定跨度送原作者焦点请求；近景沿原scalenum输入，实际type=spacecraft/globalsize=5持续6更新与1秒后再HOLD至少5秒。默认1×A、原生3024×1964的5×A(135°)/B(315°)各六帧均闭合实际模型→同request/CB/main/seal/GPUcompleted、trunc0及排空；默认场有5次superseded、1次teardown截图失败，两个近景场均PASS。默认小图只授模型出现，A/B细节与独审未见明确缺片或错误纹理；Hubble A高光饱和、JWST B暗镜面的受光仍未知。两近景JD相差571.801秒，不授纯角度/RGB因果、所有210条draw各自完整贡献、余17航天器或官方一致，9作者占位仍非MDL缺图。

18原PNG与3原report保于`.artifacts/scene-spacecraft-first6-20261116/evidence.zip`（177,569,361B，SHAb072461e…7158082），最终B正式原报告/必要载荷归`.artifacts/scene-evidence/runs/scene-spacecraft-first6-20261116`，四项同SHA别名不重复存储。封包后只删核过完整清单及无句柄的121个精确路径，5.62GB为逻辑大小，274个保留文件逐SHA未变；当前App/唯一DerivedData和用户媒体不在清单。该轮未建立新模型缺陷，按收益转向新的明确阴影反馈。

## 作者变换与大气的同帧消费 <a id="current-authored-transforms"></a>

按[变换合同](scenescript-api-coverage.md#current-frame-authored-transforms)，原callback journal增量供后继update入参/自身getter，准入TRS的canonical值进入本帧唯一world snapshot；init/主动返回归原journal，退出重复TRS返回map、pending初始化副本和angles诊断字符串吞错。passive Timeline保原投影，当前真实写入不被它盖回。十产品净+160行，无新owner/持久状态/cache；原Bool read scope收敛复用，不授性能收益。首次未声明TRS定义及C init getter的阶段仍未闭。

当前原生4方法的9回调顺序变体与6个init/timer/Timeline邻例通过，覆盖改名、当前input/getter、后返回/后setter、无update、坏返回/失败peer；旧同输入7项红保留。原20组实际输出严格不变，未将其冒为当前完整18方法重跑；C/Bool/返回诊断/timer最近门保实际原身份。Debug67.578s，十产品/project/锁文件前后相同，签名及原helpers验证通过；exe115ef63a…a2b0、dylibed363a0c…5ba4，metallib仍cd47906e…30b4。四同输入App控制各F77/request1完整到main/seal/GPUcompleted、trunc0并排空，红体与青标记质心距离从359.5–479.54降至0.539–0.542 PNG像素，低于事前1.5门限；绿色peer完整，未改输入/阈值或按相位拟合。

366私有同输入沿原Titan→Iapetus→Uranus母体→Miranda请求，intro/spin关闭、simulation冻结，原Date/runtime与实际transitionDuration=3秒继续；1.5只是脚本默认。低频两轮各5原图、零截图失败、wholePASS及App/input不变。早期请求后+.160/.158s的Titan F100/R3与Uranus F188/R5，3067/3180、1396/2908分别model/material/tail到同main/seal/GPU；后移窗口蓝体在实际+1.104s显著向左上移动并变大、顶部出画幅，可见外弧单一连续，未见旧双弧分离。黄色+.635s已出画幅，不能以draw提交授黄色移动同步。标记文字仍有原cadence延迟，不替代实际storage请求窗；不是密集序列、量速、完整过渡或官方像素对照，也未取得Miranda的5秒HOLD end。

独立原3437487219无覆盖值，当前F165/R1的112/114到同main/seal/GPU完成、trunc0并排空；1280×831原图见连续地表、云、暗面、大气、银河与time/date。必要控制、作者原图/实际行摘录、身份、失败分类及独审归`.artifacts/scene-current-authored-transforms-20261115`，独立原作者报告归`.artifacts/scene-evidence/runs/scene-current-authored-transforms-20261115`。黄色及其它星体的完整移动、余镜头和官方一致仍沿队列继续，不由本批局部通过关闭366。

## 夜光遮罩的相位供货 <a id="model-mask-phase"></a>

2026-11-14按[共享stage输入设计](render-graph-shader-coverage.md#implicit-fragment-varying)，原canonicalizer用顶点唯一数值型varying的完整类型/固定长度和片元精确函数体自由值引用补声明。顶层类型与局部类型在原binding facts区分，callee、uniform/全局值/函数冲突、显式接口及未知生产者保原结果；两backend共用准备输入，原诊断源码与缓存身份不变。两产品净+40行，新增的双stage词法分析只在冷准备，无新owner、Program、纹理或普通帧工作，不授准备期零成本。

旧源同输入5个phase变体均在真实strict link以未声明输入失败；当前8个CPU方法及4个GPU方法的分步有效结果覆盖完整12方法，5个实际纹理phase、2个局部/形参owner、3个原value-copy和6个原prefix共32条双backend Metal读回通过。四象限纹理的半宽移相得到字面交换结果，覆盖变量/helper/资源槽0→3及源文件名改名、等价式、混合局部作用域、局部struct类型与固定数组；14个边界维持真实compiler/原normalizer结果，不绑定旧错误码；原uniform词法身份与活varying资源ABI相邻两方法通过。首轮载体默认ES profile失败及旧stage-uniform同名失败保留；仅修载体profile/声明换行并重跑受影响方法，复用同一编译二进制。uniform边界保authored link成功、normalized link失败与bounded diagnostics/MSL事实，未授其Metal像素，后续归开放队列。

普通Debug 27.022s且两产品/project/锁文件前后一致，签名/原helpers通过；execbf6e2e9e…3678b、dylib20a03658…6a2c，metallib仍e451f575…2848。原3557068717两份原入口摘要相同，固定WallDate `2026-11-13T10:00:00Z`、SceneTime20和PhaseX=.416666667；前后均F95/request1，旧424copy变为真实material采样→named424→420 slot1红通道遮罩→named420→237模型到main/seal，同CB/GPU完成、零截断并排空。原3024×1964 PNG中相位产生可区分纹理变化，不能认领全体像素差或整景/夜侧增亮；自有纹理门独立证明相位数学。独立3477054430原包4秒PASS，模型、完整猫/楼体终端图与GPU排空保持。此前替换前的候选构建、目录参数错误和载体失败不计当前资格；官方像素、性能、结构类型varying及更多省略接口未授。

当前自有源/32读回、原作者同钟前后图/供货、构建身份与审查归 `.artifacts/scene-model-phase-20261114`；独立作者原报告与必要图归 `.artifacts/scene-evidence/runs/scene-model-phase-20261114`。

## 世界模型的分量贴图 <a id="model-material-map"></a>

2026-11-14按[模型分量设计](advanced-object-coverage.md#model-material-map)，原Entry的emissiveMask/三nullable draw参数退出，以单一typed数据binding消费slot2。原TEX位只供省略默认，显式0关/任意非零开、PBRMASKS0仅关map；M/R替换原响应标量、B乘反射、A乘发光，stock静态数值材质在unlit仍保profile及gain缺省1，legacy原缺省0/A路径保留。B0按实际有效reflectivity停止反射，避免既有pow floor在HDR下残留。五产品净+38行，无新owner、PSO、池、缓存或ABI字节；原data loader/UV/sampling只在准备消费，draw重复可空map校验退役。可选图无有效位时会先沿原加载链取得metadata再局部丢弃，不授冷准备零成本或性能收益。

该分量切片的5个map方法/60实际输入与6个原normal方法/36输入通过；当前扩展及最终载体见[HDR发光](#model-hdr-emissive-gain)。同一编译Swift/Metal载体分两payload执行并逐次核source/support及binary/library身份。分区map与独立等值标量得到同RGBA/depth，覆盖四分量、0/1/2/-1、总开关、TEX省略/显式无header PNG、缺图、UV/filter/address/改名、normal/反射/HDR/alpha与legacy。B0/M1/brightness16与scalar0均严格[0,0,0,255]，同环境B1为[4,4,255,255]。当前五产品与NormalChecks匹配实际执行载体输入；共享测试transport中其它入口的修订未进入该96项调用链，不扩大其覆盖。 相邻发光6方法、编译/ABI/点灯计数/来源资格及资源分段6方法、点光/聚光阴影4方法的分步有效16方法通过；退役三段纯源码包含/排序镜像，保真实编译/读回并把断言信号基线148收紧至142。

普通Debug 24.862s、五产品/project/锁文件前后一致，签名/原helpers通过；exec7c89dd96…bc98、dylibc0cbfb1d…7348、metallibe4726416…6b48。原3453730450自然20s/after17，F853/request1/CB503263185536的53实际4096×2048 components3、77实际1024² components1到main503207287040/seal/GPU完成、零截断并排空；1280×831终端图有完整受光月面、轨道、星空与时钟。两场预启动固定SceneTime/Date只取得前后同灰幕，已撤出可见资格，不声称严格作者A/B像素或77逐part贡献。独立3437487219原包5秒PASS，F159的112取8192×4096 A图components8，同主目标/GPU并排空，完整地表/云/大气/时钟；3557068717原包5秒PASS仅授片头，F117的182取2560×1440 A图components8、亮星/远星体与GPU完整，不授后期地球夜光全貌。官方像素、任意动态MR/外部反射/命名map与性能未授。

另用真实53的原MDL几何与三张4096×2048 TEX组成无脚本自有scene，保相同相机、点灯、世界矩阵、源资产/App/场景SHA，仅四分量combo从省略切0。两场F94/request1均同次main/seal/GPU完成、零截断并排空，on绑components3及RG normal，off仅退map。整球颜色/背景排除并集167063像素中87539（52.3988%）改变，平均绝对RGB差.6481 byte、最大116；6个量化边缘像素改变排除mask归属，不授几何覆盖变化。此图R恒0等于标量，差异具体归因G粗糙度50…255替代scalar1；不授真实77金属逐part贡献或作者原景/官方像素。首次等长改材质目录导致catalog漏读的clear-only失败与该批内改basename的对照保留；此断点已沿[明确材质角色](#model-material-role)纠正，未调几何/灯/相机或纹理。

作者报告/必要图与日志归 `.artifacts/scene-evidence/runs/scene-model-material-map-20261114`；自有数据、源码/载体身份、边界、灰幕与退役断言失败、审查及构建收据归 `.artifacts/scene-model-material-map-20261114`。

## 默认模型 HDR 发光 <a id="model-hdr-emissive-gain"></a>

按[材质合同](advanced-object-coverage.md#model-hdr-emissive-gain)，原SurfaceProfile保作者REFLECTION非零声明，原Pipeline以既有HDR/光照资格投影materialFlags.x的bit2；高级材质在反射、brightness之后、fog/PMA之前追加当前RGB的正HDR/A贡献。沿原分量图单次采样，零贡献不做新增乘加，legacy及原前置A路径不变。四产品净+12行，没有ABI字节扩张、资源、pass、PSO、cache或新owner；旧的REFLECTION语义丢失和后反射增益缺口退出。当前HDR资格仍由原General flag供给，显式材质HDR combo边界另在队列，不授全部作者HDR覆盖。

最终8个map/6个Chroma/6个normal/7个emission共27方法、442实际输入通过；原60 map、76 Chroma、36 normal及244 emission输入保留。两份同字节Swift probe复用源/Harness/flags，四payload均真实执行，只重编一次Metal；probe和所选库按[库选择规则](../development/development-workflow.md#metal-probe-reuse)同目录，以旧无增益与新库的可分辨读回闭合实际载入。旧的只换cwd结果不计新Metal资格。黑albedo反射A1/E4与独立B4同RGBA/depth（蓝18→71，对照71），含半A、颜色、改名、两族、HDR关闭、E≤1、A禁用及作者RF为非零但强度0/无history、LIGHTING非零但无灯等反例。RGBA16Float原因子先溢出的65504对安全控制795.5已恢复等值；零增益的大颜色反例原展开式红0对控制1.32617，最终同为1.32617。只保已有两个数值控制，不授全部Float代数。三门旧深度预期同步固定translucent非writer与显式near writer/far正深度；没有改生产深度、输入、夹具或容差。

最终Debug构建12.441s，产品/project/锁身份不变，strict/deep与原compiler helpers通过；exe0b51f6a9…e5cc、dylib2d4f5e0a…69bc、metallibc187b79a…b6b9。原347固定intro/cursor/audio/rgb关闭、hdr属性.3，35s的1512×982原16bit PNG晚段F933/1413/1768/1868均有连续白紫亮边/尖端、黑心及钟日/公式；未见这些采样帧持续白化、壳层分离或双像拖影。after为request6/CB503599254144/main503623581696，201实际.2、14读取F1767环境，113终端、export/seal/GPUcompleted、零截断并排空；原93→115仍为2048×1024。整轮仍FAIL原4项resize诊断/epoch验证，仅授恢复后端点和上述采样帧，不授连续全时段。

官方2.8.0.42后处理ultra、reflection开启的固定输入E4→E1→E4，原Display ICC JPEG在冻结body/tip ROI内从白紫亮边/外晕→细暗缘→亮态返回；原enabled档三暗图不作全质量零响应。窗口右侧遮挡不覆盖两ROI，场景相位未完全配对，不授精确4倍或跨平台RGB。原生相对官方Ultra的外晕仍窄弱、内纹更平滑；背景软线差异也未建立同相位首错。作者hdr属性0的独立14s控制保持GeneralHDR=true，F701/request1/CB534938978944的201=.2与14环境/主输出/GPU排空健康，但和.3不同相位图尚未辨出外晕贡献，不授精确零或属性可见贡献。独立3437487219原包5s PASS，F159/request1/CB501785510784见完整地表/云/暗面/大气和文字，输出1280×831来自3024×1964；无model-reflection行，不授该分支或全视角。

源、门、数值反例、官方有界对照、两张晚期原PNG及独审归`.artifacts/scene-model-hdr-emissive-gain-20261116/evidence.zip`；三次真实运行报告/必要原图归`.artifacts/scene-evidence/runs/scene-model-hdr-emissive-gain-20261116`。外晕、细纹及相邻材质语义继续[开放队列](../roadmap/scene-open-breakpoint-queue.md#implementation-gaps)，不宣水滴全面或官方精确一致，也未取得性能收益。

2026-11-16用户观察当前水滴视觉已与官方接近，确认转查其它已知断点或样本；该画面完成当前视觉验收。上述异相位差异和未取得的反射元数据语义不升级为当前阻断，精确RGB/所有属性与时相仍未授。

**表面亮度的正确次序** <a id="model-hdr-brightness-order"></a>：按[表面合同](advanced-object-coverage.md#model-chroma-surface)，generic4与Chroma在材质受光/反射合并后统一乘HDR brightness；退generic4把brightness混入albedo/F0及反射另乘的旧职责，两产品仅三行替换、净零增长，无新flag/ABI/资源/owner。真实同104输入/Harness旧新读回中，generic4的B0直接高光[5,5,5]、黑金属斜入射[12,12,12]均恢复0，后者B1/B2为12/24；有色材质B2从[61,94,122]恢复[68,105,139]，半mask也随完整颜色增益。70条authored-Chroma输入的RGBA/depth逐值不变，legacy/custom/override邻例保持；14方法104+82实际输入通过，含B0/1/2、HDR关闭、反射/混合发光、改名及alpha/depth。新Debug28.253s/签名通过，exe efc96420…a56d5、dylib17cf3c20…f648、Metal c3d50762…f20c；347原包及固定控制14s/after12，R3/F701/CB530917590784的14/115/113/main/export/seal/GPU完成、零截断排空，亮缘/黑心/内亮瓣/文字与细线完整，整轮仍保4resize失败。独立343原包5s PASS，R2/F142/CB508871558912见完整地表/云/大气/钟日。异相位图不授精确RGB或外晕改善，未改反射history/LOD语义；源/旧新读回/身份与独审归`.artifacts/scene-model-hdr-brightness-order-20261116/evidence.zip`，两真实运行归`.artifacts/scene-evidence/runs/scene-model-hdr-brightness-order-20261116`。

## 明确材质引用不受目录提示限制 <a id="model-material-role"></a>

2026-11-14按[准备角色合同](advanced-object-coverage.md#model-material-role)，原Catalog用同一规范身份的queue索引与material位替换seen；MDL附加材料、JSON model.material、particle及effect pass的明确消费者调用同一loadMaterial，待处理hint原位提升、已处理hint只补一次。普通effect dependency仍为hint，未消费.other不读；保原来源选择、脚本、排序、取消/revision和局部坏材料。产品仅Catalog净+13行，无新parser、MDL读取、资源owner、持久cache或普通帧工作。

同输入旧Catalog的12方法保13条失败，当前12方法通过：原Catalog门11方法核7材料的改目录/后缀/大小写、pending/processed提升与单次读取、package优先、坏/缺材料及无消费者JSON零读取；原MDL→SourceFacts→Catalog→materialPass门的17现代/legacy/多part/PKG变体保同份PreparedSource及健康peer。替换只选测试编译输入，不复制材料或网格解析逻辑。普通Debug32.161s，Catalog/project/锁文件前后字节一致，签名与原helpers验证通过；exec3f76122a…5432、dylibd4f260c2…a7ca5，metallib仍e4726416…6b48。原分量/法线/深度GPU合同未改，复用其有效门；未授准备性能收益。

直接读取上一分量批冻结的真实月球资产失败变体及materials/等价载体，project/scene/pkg/材料与几何字节相同，仅MDL材质引用不同。相同固定Date/SceneTime、画幅与App，两场F94/request1分别CB517910315904、511535694720，layer53的albedo、RG normal与components3到各自main/seal/GPU完成、零截断并排空；输入、原protocol、App和Catalog前后SHA不变。旧外路径clear恢复167058月球像素；新外路径、新标准路径与上一构建标准路径三图均SHA7687586a…41f63，1280×831全部1063680像素零差异，无ROI裁剪或宽容阈值。资格为同真实资产自有scene的材料路由修复，不授作者整景或官方像素。独立3437487219原包5秒PASS，F120/request1/CB515864495872的112/114进入main515873918720/seal/GPU，地表、云、大气与时钟完整并排空。当前材料角色断点退出开放队列。

自有输入身份、同输入红绿/单次读取、两场实际图与收据、独审和构建身份归 `.artifacts/scene-model-material-role-20261114`；独立作者原报告、必要图和日志归 `.artifacts/scene-evidence/runs/scene-model-material-role-20261114`。未知未引用文件、真实坏JSON不被此次角色放行；动态材料、其它shader/多pass及官方像素仍按原能力边界。

## 世界模型的渐变漫反射 <a id="model-shading-gradient"></a>

2026-11-14按[原渐变设计](advanced-object-coverage.md#model-shading-gradient)，stock generic4的活动slot4沿原Resource/Entry/Frame/Metal供货，省略取stock默认、明确坏图/无file的typed user局部退普通响应。原SurfaceResponse的diffuse cosine由signed N·L lookup替换，specular保持原正NoL/Fresnel/GGX，三灯继续独立一次衰减/阴影。image同一clamp(dot)移到caller后原乘法次序不变；模型旧重复dot退出。七产品净+72行；只新增16B uniform、texture8/sampler3与typed immutable binding，UV中心采样线冷准备一次，无新PSO/pass/池/cache/owner；无gradient的固定绑定成本不称零成本。

最终同一Swift/Metal载体三个payload的16方法、56 gradient/60分量/36normal输入通过，source/support、binary/library身份及复用输入逐次核对。真实ResourceView/TexturePathResolver与原Frame/Metal消费分段RGB的负/零/正方向，分别得到[15,0,0]、[0,24,0]、[0,0,34]，与独立普通灯色等值；背半球全白lookup为[15,24,34]，实际caster阴影为[0,0,0]，alpha255且同depth。R8/RG复制R、RGB、2/-1/0/省略、normal翻转、有效域/中心行/采样、default/改名/缺图/custom/override/unlit与明确user缺file、三灯/cone/radius、ambient/emission/spec/reflection/HDR/alpha/depth边界保持。原图像31条scalar/half、19格式及world capture/family数值，与模型emission6和pipeline7方法的分步有效16方法通过。首个native只因过窄resolver替身丢stock默认而15/16，已退该替身、编入真实resolver并重编一次后全过；图像旧fixture三处缺try已按既有API修复，仅补受影响方法，未改产品/输入或阈值。

最终普通Debug26.624s，七产品/project/锁文件前后相同，签名与原helpers通过；exec2ae29db2…3884、dylib240c0cef…512c、metallibaeb9d00a…6564。首轮33.035s构建及真实pair保作中间结果；最终增加typed用户输入的default所有权修订后，两场固定Date/SceneTime的真实月球资产控制完整重验。最终on/off的F94/request1分别CB531241337728、501344798464，原几何/world/相机/灯、源资产与protocol前后SHA不变，on实际64×2 R8 lookup、RG normal与MR3进入同main/seal/GPU完成、零截断并排空；off无gradient。off与旧构建逐PNG相同，on/off的1280×831全图中，颜色排除背景并集167107像素的159472（95.4311%）改变，平均绝对RGB差11.2111 byte、最大55；此并集是颜色测量，不授几何覆盖变化或原作者整景严格A/B。最终on与首轮on也逐PNG相同，未调参数拟合月色。

原3453730450自然20s/after17，F826/request1/CB515873867520的53、77一个实际part及306/340/342复用同一64×2 texture进入main515864339840/seal/GPU，终端月面、星空、轨道、标题与时钟完整，零截断并排空；不是77全部part资格。独立3437487219原包5秒PASS，F141/request1/CB530126540288的112/114无gradient，地表/云/大气/时钟完整并排空。算法为本引擎明示漫反射风格合同，未授官方像素、rim、用户provider/热更新或性能。

当前原作者报告、必要图与日志归 `.artifacts/scene-evidence/runs/scene-model-gradient-20261114`；实际资产开关与旧/中间/最终身份、56/60/36输入、局部失败/修正、相邻门、独审和构建收据归 `.artifacts/scene-model-gradient-20261114`。

## 世界模型的轮廓漫反射 <a id="model-rim-lighting"></a>

2026-11-14按[轮廓合同](advanced-object-coverage.md#model-rim-lighting)，原SurfaceProfile冷准备amount/exponent，原shader每片元一次view曲线只增强每灯diffuseCosine；保原Fresnel/GGX、radial/cone与真实shadow，shared BRDF API/Frame不改。metallic1、NoL0、无直接灯/纯ambient与完全阴影无rim，exponent0恒1，amount0跳pow。错型/动态值仅关rim不丢M/R/反射profile。四产品净+32行，只新增16B uniform，无texture、varying、PSO、pass、池、cache或enabled状态；关闭仍有固定ABI与统一片元管线成本，不授零成本/性能收益。

同一Swift/Metal载体四payload的21方法通过，45 Rim、56 gradient、60分量、36 normal共197实际输入，source/support及binary/library逐次核复用身份。Rim闭式增益只转为独立普通灯色控制，roughness0排除有限specular；固定pixel的独立pinhole先核actual camera/world/normal事实，再验正面/侧面/背面、0/2/-1/省略、exponent0、normal/彩色gradient/NoL0/纯金属、三灯/径向/cone/真实caster阴影、无灯/ambient/emission/reflection、HDR/alpha0/depth与改名，不复制BRDF。真实ShaderValue/Timeline与原parser六声明、staticComponents及actual surfaceProfile的CPU门6.248s通过：含user:null、script:17/animation:17、有效timeline/script、坏raw/count/finite，MR/反射保持，仅rim0；该门的stock VFS只是输入边界，不授资源运行。三个相邻方法15.835s通过，保完整标量/typed wrapper，非零Rim与exponent0经两种动态材料copy均保持整profile。CPU门只锁实际动态声明和完整标量边界。

普通Debug30.256s、四产品/project/锁文件前后字节一致，签名与原helpers通过；exec2c79cb11…a882、dylib4dd02626…c5a1、metallibb2053bb2…c80c。固定Date/SceneTime的同真实月球资产控制只改RIMLIGHTING一字节，gradient1、原MR/normal/几何/相机/单灯/world不变。旧on为F94；当前on/off均F95/request1，CB502327609088、522091135872的实际normalRG/MR3/gradient64×2 R数据到各自main/seal/GPU完成，零截断并排空；源、旧/新protocol、App与四产品SHA不变。off与旧on及上一梯度on逐PNG相同；1280×831全图比较、排除固定背景的颜色并集167198像素中67583（40.4209%）改变，平均绝对RGB差3.70457 byte、最大143，右上受光轮廓增强。颜色并集不授几何覆盖变化、原景严格A/B或官方像素。

原3453730450自然20s/after17，F877/request1/CB536284483072的模型/normal/MR/gradient到main536336657024/seal/GPU，月面、轨道、星空、标题与时钟完整；独立3437487219原包5秒PASS，F158/request1/CB513468403200的112/114到main513518951296/seal/GPU，地表/云/大气/时钟完整，均零截断并排空。该运行不授完整Chroma材质受光；共同表面及noise的独立资格见[Chroma表面](#model-chroma-surface)与[颜料](#model-chroma-pigment)。源码、测试、实际图及最终身份独审无阻断。

原作者报告/必要图与日志归 `.artifacts/scene-evidence/runs/scene-model-rim-20261114`；真实月球开关、旧/新App输入身份、197输入与CPU/相邻门、审查及构建收据归 `.artifacts/scene-model-rim-20261114`。用户动态rim、其它材质族和官方像素仍未授；本批未改最终输出或照明owner。

## Chroma的共同表面与颜色次序 <a id="model-chroma-surface"></a>

2026-11-14按[原Chroma合同](advanced-object-coverage.md#model-chroma-surface)，原SurfaceProfile承接stock chroma4及静态specularTint，三灯共用原MR/shared权重；view tint先形成有效albedo再进BRDF/F0，spec tint只乘specular瓣，mask按原albedo A分别限制两项。退出该种类的晚view染色与reflection内重复gain；两族当前HDR次序见[表面亮度](#model-hdr-brightness-order)。无灯/反射但非常色view tint仍可预载normal，静态相等色不读图。四产品净+45行；只加16B uniform至1440B，无新纹理/varying/PSO/Frame/缓存/owner，不授零成本或性能收益。

同一Swift/Metal载体五payload有效27方法、76 Chroma/45 Rim/56 gradient/60 map/36 normal共273输入通过；Chroma白tint等值generic4的MR/三灯/normal/map/gradient/rim/遮挡、R0 tint无贡献、有限粗糙度两瓣分离、无mask color无效、单侧默认与动态back、mask0/半/1、unlit view法线需求、mip normal透明边缘、HDR/alpha/depth及改名均有实际像素。首轮仅HDR反射发光控制gain2饱和而一方法失败；只把两行albedo降至非饱和区，沿同份source/support/binary/library补Chroma6方法，gain1[16,24,63]→gain2[32,48,126]，未放宽断言、重编或改产品，原失败保留。真实parser/helper/profile CPU的Chroma方法8.368s通过，原Rim方法复用同一执行的有效结果，整profile动态copy邻例7.493s通过。首CPU错误用共享入口尚不支持的数组充正例，改为实际支持的字符串后重跑受影响方法；数组/包装错维度独立复现并留队列，不在消费者重复解析raw掩盖。

最终普通Debug25.047s、四产品/project/锁文件前后字节一致，签名与原helpers通过；executable ae4f46c9…75599、dylib0eebe5d9…c4e5e、metallibb5c35fdf…981c。前一候选构建不计最终运行资格。冻结真实3437487219/114的439270B MDL几何与原8192×4096云TEX/alpha，材料引用仅basename等长改名避免包内优先；同一相机/单点灯/world/采样、白front/back/pigment0，保M.1/R0与宿主translucent/test/write/cull。旧Rim App F95与当前F94/request1分别CB531967297280、504851170176，实际颜色到同次main/seal/GPU完成、零截断并排空；源/protocol/旧新App/SHA不变。1280×831全图排除背景的颜色并集157100像素中117325（74.6817%）改变，平均绝对RGB差3.25892 byte、最大33，云层按MR响应变暗；未调亮度拟合。此图只授真实M.1/R0的共同MR贡献，白tint/R0不授彩色view或有限specularTint，RGB颜色边缘不授数值alpha/depth、几何覆盖或原作者全景严格A/B。

原3437487219五秒F149/request1/CB513567409024的112/114到main513629395840/seal/GPU；地表/云/大气/时钟完整。原script对114.color的typed动态back仍沿已有Frame消费，未另授原材质回调writer。独立3453730450自然20s/after17，F846/request1/CB513769885184的53/77具体part/306/340/342到main513829804288/seal/GPU，月面/星空/轨道/标题/时钟完整，均零截断并排空。产品/测试/实际图独审无阻断。该MR对照不授pigment/noise，独立结果见[颜料](#model-chroma-pigment)；更多动态参数、官方像素及性能未授。

原作者报告、必要图与日志归`.artifacts/scene-evidence/runs/scene-model-chroma-20261114`；真实云控制、旧新身份、273输入、原失败/定向补验、独审与构建收据归`.artifacts/scene-model-chroma-20261114`。

## Chroma的颜料噪声 <a id="model-chroma-pigment"></a>

2026-11-15按[颜料合同](advanced-object-coverage.md#model-chroma-pigment)，原SurfaceProfile冷准备静态amount，原Entry沿slot8/.noise准备当前目标pixel→UV的独立data绑定；三灯已遮挡directRadiance统一乘signed noise权重，保ambient/emission/reflection/HDR与原PMA/depth。采样均值的saturate是SNORM到有界signed响应的算法，不加格式许可或像素扫描；原gradient的默认所有权判断汇合到optionalTexture，退重复消费者检查。五产品净+77行，只新增32B uniform至1472B和texture9/sampler4，无varying/PSO/pass/时钟/池/cache/owner；关闭保固定ABI/占位绑定成本，不授零成本或性能收益。

同一Swift/Metal载体四payload的分步有效21方法、35 pigment/76 Chroma/56 gradient/36 normal共203实际输入通过；source/support、binary/library与最终五产品身份核同。初始21方法31.632s全过，但独审指出两行mapped extent超过physical，只授受控数学、不授生产padding；改成真实有效4×1/mapped2×1/半宽UV及2×2旋转轴域，仅两行输入改变，沿原binary补受影响的一方法0.207s通过，不重编、不改产品/阈值，原输入/结果保留。新门以黑/白noise的.2对应普通灯色.8/1.2，彩noise实读RGB均值，R8/RG复制R、BC5 SNORM负均值饱和；三灯含point+normal、真实全影0、direct+ambient+emission+reflection/HDR/half等值控制及零alpha后的far/depth通过。实际屏幕物理坐标、mapped extent、UV origin/双轴、nearest/linear、repeat/clamp、meshUV与资源改名、stock默认、显式缺图/user缺file/有file、0/缺省/generic4/unlit只局部关闭。该transport不授TEX解码或动态raw；真实parser/helper/profile的Chroma CPU方法6.264s核静态/标量/负数/超界、user:null、script/animation错型与动态仅关amount，其它profile保持；动态材料整profile copy邻例6.820s通过。退载体旧purpose三值许可，不为noise再扩白名单。

普通Debug29.006s、五产品/project/锁文件构建前后相同，签名与原helpers通过；executable eeb47aa0…fa0e1、dylib763bafa4…c6cf0、metallib5917c277…01900。沿上批单份owned Cloud包，独立于只读用户原件，冻结原几何、8192×4096 TEX/alpha、白front/back、M.1/R0、相机/点灯/world/宿主状态；仅amount0→.2，stock实际256² RGBA8 util/noise、linear/repeat/noMip。旧off、当前off/on均F94/request1，所有原输入/协议/App/source SHA不变，同次主目标/seal/GPUcompleted、零截断并排空。当前off与旧off及上批pigment0逐PNG完全相等（6b3c095f…3d9b2）；1280×831全图颜色前景并集156807像素中77611（49.4946%）改变，平均绝对RGB差.36387194 byte、最大10、P95=1/P99=3，有符号均差每通道约−.004，表现为细粒变化而非整体增亮。246个背景颜色量化成员改变不授几何覆盖，RGB图不读数值alpha/depth；数值覆盖/深度由原生门承担。该真实资产控制授本引擎screen-locked pigment贡献，不授原作者全景严格A/B、stock视距/世界相位或官方像素。

原3437487219五秒F147/request1/CB524195710720、112/114到main524249013120；独立3453730450自然20s/after17，F804/request1/CB524860098304的53/77具体part/306/340/342到main524923355136。两场原project/pkg摘要等冻结matrix，签名前后核同当前App，模型与终端seal在同CB、GPUcompleted/trunc0并排空，地表/云/大气/星空/时钟及月面/轨道/标题完整。trace不观察模型内部材质绑定，不能由此声称slot9或逐part pigment像素；可见贡献归前述实际资产对照。

原作者报告、必要图与日志归`.artifacts/scene-evidence/runs/scene-model-pigment-20261115`；自有Cloud开关/旧零基线、203输入、CPU/相邻门、构建与独审归`.artifacts/scene-model-pigment-20261115`。用户纹理provider、动态amount、world/object锚定、更多stock效果与官方像素仍未授。

## 定向阴影的可见接收区 <a id="model-directional-shadow-fit"></a>

2026-11-16，用户报告3589454154土星向星环投影锯齿及球/环黑物闪烁。原15e App自然40秒中，32秒以后原生图有右上粗暗带；15个成功捕获均到同request/CB/main/seal/GPUcompleted、trunc0并排空，但全场另有5次superseded、1次teardown截图失败。保所有物体显示，只保球456/环462投影时粗带消失；单关近环479时仍有粗带；球/环/479投影时另有细长影痕。三组和后续两组控制均完整PASS，不将两种现象合并为同一故障。

一次回调前缀的真实390项TRS经原WorldResolver和旧Projection纯CPU重建，全部25个caster使灯域达146.48×104.09，球/环/近环仅9.31×6.33；远482/483占XY两端且与主环不相交。原MDLReader实际解码逐顶点bounds与测量用header逐Float相同。该前缀在Main后、725角度更新前，不能冒GPU最终矩阵；两份最初误用getLayer(id)的空getter记录已排除，getLayerByID修正后130层全部实际取值。source默认casttrue保留，符合[官方模型默认投影](https://docs.wallpaperengine.io/en/scene/models/lighting.html)，不以关远卫星或陨石修产品。

按[接收区合同](advanced-object-coverage.md#model-directional-shadow-fit)，原Projection双向裁剪实际颜色域的box/frustum边，XY只拟合可见受光接收区与caster覆盖交集，相关caster扩Z，XY/Z留边分离。Frame仅实际受光prepared层求pass/clip，退无消费者预约与正常域完整bounds重复计算；没有新增map、ABI、PSO、纹理、时钟、历史或缓存。普通帧仍有范围数学，未实测性能收益。这组接收区对照保4tap双线性PCF与1024图、全部合法cast及coverage/cull；当前图尺寸另归[输出密度](#model-directional-shadow-density)，一般大场景稳定化未解。

生产CPU门8方法/21同输入，旧源8个几何子断言红，新源全绿；独审删两处无用计算后再验，输入/Harness/21行结果逐byte不变。含无关远XY/Z、灯域相交的屏外caster、擦边长盒/包含clip体/无角内的交叉、native/canvas/反向深度、nil/奇异域保守回退及等价TRS；数学API无资源身份，不拿label改名授资源消费者。真实Frame6与DirectionalPixel2方法通过；首轮13子失败来自旧夹具全unlit仍要求map、及无消费屏外位置读回，已保首失败。现增加实际绘制的独立lit黑色非caster receiver，原主体/peer颜色、camera depth和三灯coverage阈值不放宽；217行均完成且采样坐标有效，另有无lit receiver不建定向图的反例。黑receiver的颜色snapshot仅ambient，真实可见direct影由DirectionalPixel门另授。named生命周期/阻塞提交/resize/cancel与原前缀容量4方法通过。

最终普通Debug21.525秒，两个产品/工程/锁文件前后SHA一致，原helpers及strict/deep签名通过；exe c3e7a0eb/dylib90b4a71e，metallib仍bfb78133。固定33个模型、灯及祖先对象的TRS与原静态camera、原MDL/TEX/材料，退脚本且不含作者cameraPath；它不冒成熟原景镜头或作者动画。旧→fit原图RGBA8有411,657像素变化、最大185、alpha不变，星环粗条退出且主影保留。最终v2与v1冻结原PNG逐byte相同；原作者自然40秒/12捕获全PASS是v1，未冒最终v2原场景重跑。独立3437487219最终v2自然5秒PASS，地表/云/大气/星空/时钟完整，未授其未请求的定向影贡献。最终独审fb05fda9…de312无本范围阻断。

细长影仍未全闭，原三角外的虚假写深度另由[覆盖修正](#model-shadow-primitive-coverage)处理：当前fit控制单关479即退密集细痕，关259则连主影一起退；两个场均保持输入/二进制且PASS。纯CPU解码479有267,216个四三角组件，中位世界直径.00416；冻结控制仍有477接收候选扩X域，当前texel为X .02888/Y .00589，不能沿用近环-only的.009作当前全场尺度。组件多数嵌在环薄层内，不能称所有长影正确或全部可见。球面自影暗点的后续归因与修正见[实际接收平面](#model-shadow-receiver-plane)；环上细粒、快速闪烁与作者cascade意义仍未闭，不以更大map或无闪烁静图授时间稳定。其余Bloom/细线微颗粒/轮廓反馈仍未知；原图、失败、原报告/事件、生产源与独审归`.artifacts/scene-model-directional-shadow-fit-20261116/evidence.zip`（121,172,837B，SHA17c12296…d09bb）；正式载荷归`.artifacts/scene-evidence/runs/scene-model-directional-shadow-fit-20261116`的original-v1/independent-v2两独立run，按真实App5分立并以同SHA别名去重。

## 定向阴影的物理输出密度 <a id="model-directional-shadow-density"></a>

2026-11-16按[密度与共同预约合同](advanced-object-coverage.md#model-directional-shadow-density)，Frame从实际受光prepared颜色pass最长物理边选1024/2048/4096，point/spot保原face尺寸；复用一次1024 guard-band fit、现有三角覆盖/4tap、全部合法cast及唯一pool。高图整组stage后才编码，失败退原逐灯1024局部成功；实际fallback keys只保护失败reclaim中的暖低图，成功stage仍可退出旧闲置图。退单kind-only私有事务，旧adapter复用mixed Collection/keyed core，无新预算/资源/缓存/历史owner、shader、PSO或ABI。产品Frame/Pool净+52行，新增短期plan与slot/extent输入只供这条质量/回退链。

复用[接收区控制](#model-directional-shadow-fit)的冻结33对象，先只变定向target1024→4096，原世界域/矩阵、材质、资源及颜色算法同。3024×1964原16bitPNG从3a87aeab…bbc2变bcdd1440…2f95；RGBA8量化198,867个RGB像素改变（132,294变亮、66,573变暗），alpha全同。根域主影边缘与密集长黑痕在同尺寸观察中明显改善，不把所有变化像素授为真值。最终实际pass/cohort策略的原PNG逐字节同4096隔离控制，固定4096实验不充正式选择。额外479仅castfalse的包精确复现83f45fb3…01c7；另一包只改visiblefalse，场景外字节/原project均同。两个实际运行68.757s PASS，单关cast仍有细粒、隐藏模型后退，说明残余还含真实微几何颜色/覆盖，不应全部归为阴影；该对照不授MSAA或官方表面响应已一致。

成本是1024深度单图4MiB→4096的64MiB载荷；实际cache/在途成本另量。原1024与固定4096同冻结输入、目标60FPS、warmup30s、关闭execution observations的一对诊断各PASS，测量窗仅8.501/8.474s，低于60s稳态门。GPU帧P50 20.354→23.417ms、P95 28.963→32.765ms，CPU帧P50 2.785→2.745ms；完成FPS57.991→51.571、pool采样峰150,927,872→276,756,992B（+120MiB，两个在途图）。这限定为该隔离控制的短测成本，不授能耗、一般回归或最终cohort CPU等价；不能称提高密度没有开销。4218个可见ring三角centroid的独立CPU footprint呈显著各向异性，未模拟实际alpha/遮挡，不据此采用圆形大模糊。

生产门核13个实际Frame输入：物理尺寸阈值/高度主导/改名、四dir在16/12MiB保四张/原前三张1024、充裕预算高图、混合point/spot尺寸与无效spot空slot、无受光receiver主颜色/零dir图，4方法通过；原mandatory depth/particle3方法保持。新pool原子/生命周期门先有一条空缓存重试次数的fixture误断，原始失败保留；修订保所有失败回滚断言。独审又定位真实warm低图被失败高图reclaim的问题：精确旧Pool8dab的同门11.614s真实失败，身份/驻留/内容三项为false、无执行错误；最终809c的Resource4方法10.539s全绿，Frame6507的7方法52.513s全绿。旧公开target kind的33方法在首mixed core通过；最终只增失败reclaim保护集合。独审无新增阻断，原预算/stage/revision/pin主体保持；不授所有闲置缓存绝无副作用或group伪造pass资格。

最终Debug25.237s、两产品/project/锁文件前后同、strict-deep与trusted helpers通过，exe149c8a3f…248d/dylib2d3196be…beaa/Metal仍4415ad9f…8814。最终冻结36.129s、原130对象40秒/after32的77.200s、独立原3437487219自然5秒/38.020s均PASS；分别2/7/2个model→main/seal/GPUcompleted捕获、trunc0/parse0，停止/释放/排空完成。独立地表、云、大气、暗面、星点和钟日完整；原作者7秒采样与旧3.5秒及Date不同，不授逐像素或快速闪烁频率配对。质量/成本对照、真实失败与暖图反例、原报告/PNG/输入、源码及独审归`.artifacts/scene-model-directional-shadow-density-20261116/evidence.zip`；正式运行按真实App5分立于`.artifacts/scene-evidence/runs/scene-model-directional-shadow-density-20261116`。球面暗点的同姿态后续见[实际接收平面](#model-shadow-receiver-plane)；环上残余微模型颜色/覆盖与快速闪烁仍开放，不靠关闭479或改作者风格掩盖。

## 定向投影面重建的真实三角覆盖 <a id="model-shadow-primitive-coverage"></a>

2026-11-16按[三角覆盖合同](advanced-object-coverage.md#model-shadow-primitive-coverage)修原caster深度重建：raster吸附后的覆盖不能直接授权在原三角之外写无限平面的深度。Apple M4旧实际178输入有44处严格ray miss仍写图，其中22处越过三顶点自身Z范围；精确有向边/轴向ray独立复核，最小外部距离.0002texel量级，非边界舍入分类。原106个已写内部/边缘命中保持，26个旧漏采样不由此恢复。首严格零扩边原型丢一个共边点，按实际重心加减项的8ulp余量后恢复；此余量是有限工程边界，不授全部Float几何零扩张。

原Pipeline仅冷选一份定向PSO，具有shader barycentric能力时沿原plane/Jacobian校正texel中心重心覆盖；不支持的设备保原fragment，该硬件路径未新实机执行。两入口共享原材质覆盖和平面算法，导数放在材质coverage之前，隐式采样仍先于新增discard；此调度收整未取得当前Metal2.4的alpha失败反例，不宣修复已证LOD错误。无网格展开、附加buffer、map、ABI、cache或owner；该coverage对照采用1024与原4tap，当前尺寸归[输出密度](#model-directional-shadow-density)，point/spot语义保持。新增ALU/重心输入只在定向深度片元，未取得可比性能或能耗收益。

冻结同33对象（模型/灯/祖先）、实际TRS和原静态相机，旧fit原PNG SHA c88d7c77…b440，对新coverage原PNG 3a87aeab…bbc2；全3024×1964图按RGBA8量化有43,402个RGB像素只变亮、0变暗、alpha全同，原16bit文件保留，主影仍在。该控制未含作者243镜头脚本，不能称32秒原景逐像素相位对齐。首版shader6191/Pipelinecd535自然原130对象40秒有12个实际model→main/seal/GPUcompleted捕获、trunc0/parse0，末request13在teardown失败使整场CHECK，停止/释放/排空均完成。成熟图仍有明显微投影细痕；此次只退原三角外虚假遮挡，不宣闪烁全部解决。

首版Debug26.146s；最终shader6bef/Pipelinecd535仅提前已有导数，Debug10.031s、签名与输入身份稳定，exe65ac1ebb…7fa6/dylibfb6fb876…9b4c/Metal4415ad9f…8814。最终冻结35.839s PASS，原PNG逐字节同首版；独立原3437487219自然5秒/39.340s PASS，地表、云、大气、暗面、星点与钟日完整，两场各2个实际GPU闭合捕获并排空。原作者40秒和首版独立观察各保自身App5，不合并成最终实机资格。最近斜面自影/接触/cull与滤波5方法、Frame相机/三灯coverage6方法首版通过；最终63输入生产indexed draw门4方法加原Frame受影响alpha2方法通过，覆盖严格外部、已写内部深度、恒深phase、闭四面体、共边、非顺序共享index、materialPath改名与等价TRS。该改名不是VFS纹理热换资格，collapsed微面仍不承诺新命中；独立审查通过。

官方原包30文件guest逐SHA一致，成熟1600/2560视图在shadow ultra、MSAA2×、post enabled只读配置下未见本地密集长黑痕；不同Date、窗口/DPI与捕获条件不授像素或闪烁频率一致。原始对照、尾帧失败、两版身份、实际生产门与独审归`.artifacts/scene-model-shadow-primitive-coverage-20261116/evidence.zip`；正式作者/冻结/独立运行按真实App5分立在`.artifacts/scene-evidence/runs/scene-model-shadow-primitive-coverage-20261116`。后续球面receiver暗点见[实际接收平面](#model-shadow-receiver-plane)；近环子texel颜色/覆盖、快速闪烁和剩余主影边缘继续归开放队列，作者cascade距离的单位/意义尚未证实。

## 模型阴影的实际接收平面 <a id="model-shadow-receiver-plane"></a>

3589454154冻结33对象、2268×1474输入中，原149c App预先固定球面ROI有17处局部暗差>8、其中12处>16；关闭259阴影或仅关闭456自身cast均归0，生产projection与bias保持。官方同冻结输入/client尺寸主体边界差约1像素、对应暗点原生17/官方0；这是有界画面对照，不授精确RGB或官方算法。官方479 on/off client RGB相同，不证明该字段已被消费。

真实百万三角sphere、完整viewport/2×2 scissor诊断保原vertex、矩阵、winding与同CB map；Float32逐bit核对且primitive ID匹配源索引。旧两点visibility .2824707/.661377恰等左列tap权重，右列减原bias仍判暗；GPU屏幕导数梯度偏离实际face。用真实face梯度锚在同GPU clip，四tap reference均低于stored depth，不需放大bias；不同tap来自不同caster面，不要求共面，也不判硬件故障。

按[接收面合同](advanced-object-coverage.md#model-shadow-receiver-plane)，Pipeline复用同mesh顶点/索引缓冲，以primitive ID及16/32bit宽度取三角边，局部相减再用world线性部分变换；三灯比较消费真实平面，退出屏幕相邻差的几何职责。BRDF/normal-map保原法线，bias/caster/相机不变，无新网格/资源/owner；定向当前滤波见[下一节](#model-directional-shadow-filter)。两组64/80-face曲面走两种索引，独立ray给字面预期；同输入旧3方法4条visibility失败/0error，最终8方法含Point seam/transform、Spot cone通过32.932s，保间隙遮挡和邻例。

该批Shader6ceb/Pipeline313ec，3091→6ceb只改注释；Debug25.423s及注释构建14.160s各保身份，strict-deep/helpers通过，App e6ad/6704/67bc。同冻结75% PASS32.114s，球面ROI 17/12→0/0，全图仅350处RGB8像素改变、alpha完全相同。原149c/最终e6ad完整3024×1964、45秒/warm30短测实际仅13.496/13.469秒：GPU P50/P95 13.759/14.170→13.470/14.230ms，CPU 2.987/3.333→3.053/3.293ms；GPU/RT池采样峰同750436352/213842432B。背景/VM未控制，不授稳态性能或零开销。

原130对象自然40秒/after32/每7秒采样78.607s PASS，主影/内容完整，但用户仍确认环闪；独立3437487219自然5秒36.927s PASS，112/114模型与135图像到main/seal/GPUcompleted，零截断并停止释放/排空，地表/云/蓝大气/暗面/银河/钟日完整。此批只闭球面暗点；原图、实际GPU读回、输入/身份归`.artifacts/scene-model-shadow-receiver-plane-20261116/evidence.zip`，正式原作者载荷归`.artifacts/scene-evidence/runs/scene-model-shadow-receiver-plane-20261116`。不授全球/全视角无自影、环闪已修完或官方完整一致。

## 定向微阴影的有限覆盖滤波 <a id="model-directional-shadow-filter"></a>

3589454154四组环上暗/健康邻点用实际462片元、原BC3、4096固定on-fit及479 caster取证：5个有限存深均有真实碎石ray遮挡，最大深度差7.48e−8，32tap分类全同；不支持继续改caster面或放大bias。原双线性单tap权重可约.95，微影欠采样随相位变化很大；479关cast同时改变map Y相位，差图只作候选。模型省略cast按官方缺省开启；utilwhite alpha1三种深度控的官方blue/blue/red仅支持该材质非writer，不外推BC3。

按[有限滤波合同](advanced-object-coverage.md#model-directional-shadow-filter)，同tap helper以三texel方盒与双线性重建卷积替换定向2×2，16个独立receiver-plane reference/bias比较分四组gather，不保跨组数组。Point/Spot仍4tap；无新资源/PSO/ABI/owner、历史或缓存。逐组dot改变Float32累加次序：860合成通道最大差1.79e−7，真实8点×4相位/128通道最大1.20e−7，均在原2^-20容差内，alpha/PID/status逐位同；不称浮点逐位一致。

正式旧源FilterFootprint3方法21失败/0error；最终受影响Filter3、ReceiverPlane3及CasterPlane1共7方法17.188s通过。原6个skinny几何/中心ray意图不变，两条窄正间隙仅覆盖16tap中的4条，有限覆盖期望应为5/9；独立oracle核后修期望并加全覆盖正间隙0反例，未放宽容差。Point seam/transform与Spot cone的5方法（4项GPU行为、1项CPU投影）在scalar-N3载体通过后按未变消费闭包复用，不称同次最终12方法运行。

最终Shader973f36c4，Debug12.334s且产品/project/锁文件前后同，strict-deep/helpers通过；App 476b/6704/d303。同冻结33对象/2268×1474 PASS31.269s，完整RGBA8与scalar-N3一致；对原e6ad四个暗点R为15/18/18/17→92/135/134/134，sphere ROI仍0/0。预注册环ROI局部暗差>16为3381→2331，含真实纹理，不能当作全部错误黑点或闪烁计数；主影和合法遮挡保留。最终原130对象自然40秒/after32/每7秒采样77.646s与独立343自然5秒36.422s均PASS，停止释放/排空；根已看原图，主影、模型/环、UI及独立地表/云/蓝大气/暗面/银河/钟日完整。捕获资格随原事件保留，不以rc0代替画面。

相同冻结输入、3024×1964/target60/warm30/duration45的短成本观测：原e6ad与最终476b实际测量13.469/13.502秒，GPU P50/P95 13.470/14.230→14.742/18.238ms，CPU 3.053/3.293→2.792/3.121ms，completed 59.916→59.101FPS、GPU失败0，RT池采样峰213842432→280951296B（+64MiB），峰值原因未获逐key事件证明；RT池采样峰213842432→280951296B，进程footprint 1049281904→1150698864B。每帧pass/copy census同，但无逐key分配事件，不能因shader未建资源就称无峰值增长。顺序运行/背景/VM未控制，均不足60秒稳态门，不授能耗或普适加速。原始逐次16比较与跨组数组原型分别观测15.960/17.762、13.999/14.604ms，最终停止微调并保真实成本。

本批只减轻已证微影欠采样，剩余颜色/几何覆盖及快速闪烁继续列首项，不称官方滤波公式或完整一致。原图、GPU正反例/变体、身份与独审归`.artifacts/scene-model-directional-shadow-filter-20261117/evidence.zip`；正式原作者载荷归`.artifacts/scene-evidence/runs/scene-model-directional-shadow-filter-20261117`。

## 实际直接光贡献后的阴影需求 <a id="model-shadow-demand"></a>

2026-11-17按[需求合同](advanced-object-coverage.md#model-shadow-demand)，在原fragment实际normal/灯贡献成立后才查同kind/index灯影，退三个visibility数组与前置全图遍历；reverse查找保原最后匹配语义。无surface或无gradient的NoL≤0、point原重合/radial0、spot cone0不再取影；背光gradient、法线扰动、零指数半径外的实际能量和Tube原链保留。indexed世界边读取移到coverage discard之后，不需要quad导数；纹理隐式采样仍在前。唯一Metal+43/−36净7行，无CPU/ABI、资源、PSO、缓存或owner增加，六个原visibility/filter/response/coverage函数及Tube至PMA尾部逐字相同。

最近九方法实际7过、2条旧depth期望红；同旧973f Metal重跑这两条仍相同红，56行RGBA/depth及其它非requests字段逐值相同，requests内容/次数相同而次序有差。不放宽或改写原断言，也不称14全绿。新增五个原邻门27.876s全过，包括238行point实际轴/边/角/有符号间隙、四map/零map/混合灯、Spot过渡及径向零指数/legacy/surface；gradient背光/NoL0、改名、normal、rim、ambient/emission/alpha都沿原实际资源→Frame→Metal。独审核当前产品与读回身份，不以profile或源码命中代像素。

普通Debug33.816s、输入/project/lock前后同，strict deep与原helper校验通过；App0353fd1e…a8d6f、dylib1b2718d6…7a608、Metal7c94461a…2cbb7。frozen33/2268×1474的三次capture各28模型→原1×main/display→export/seal→同CB snapshot，completed/trunc0并排空；after PNG与原476b逐字节同，SHAcd7a9c67…2940a。原358的40秒/after32有七个capture，343独立作者有两个；实际模型/单输出/完成与停排空均闭，根与独审看过球/环/主影/文字及地表/云/暗侧/蓝大气/银河完整图。原景未锁相，7秒采图不授高频环闪关闭或官方逐像素一致。

同frozen33/3024×1964、60FPS、warm30/duration45的相邻候选→原476b→候选，各实际13.504/13.529/13.500秒、0failed：GPU P50/P95为13.948/17.119、14.325/15.488、13.540/13.990ms，FPS59.686/59.871/59.924，CPU P50/P95为2.724/3.221、2.632/2.922、2.712/2.955ms。候选首次pool280951296B/GPU allocated818069504B与原相同，重跑为166329344B/701415424B；实际在途/暖驻留有变，不能从无新增资源推出固定减内存。这是本固定输入的小幅成本观察，背景/热状态未完全控制，不授稳定提速、一般能耗或严格因果；停止继续微调此分支，环闪仍为首项。

自有夹具、同输入旧红、当前结果/身份/独审与冻结原图归`.artifacts/scene-model-shadow-demand-20261117/evidence.zip`；原作者载荷归`.artifacts/scene-evidence/runs/scene-model-shadow-demand-20261117`。后者为保四张原PNG沿单包96MiB明确例外（两张Earth即超过32MiB），14天/总5GiB不变；正式包不含全部周期PNG，不把九个实际capture等同九张已晋升图。

## 定向阴影的固定世界网格 <a id="model-directional-shadow-grid"></a>

2026-11-17固定真实479 caster、462 BC3接收面、456 camera-depth前缀和近处相机/世界，只移动自有远处lit noncaster接收物；其配对unlit caster与近面灯域X间隔扣除N3 footprint后仍>20.44世界单位。旧生产fit在四个原4096物理texel相位−.25/0/.25/.5下，登记近点(971,710)的visibility range为.03930670023、诊断Half返回R range为.00421142578125；完整余量的held-fit及shadowoff、近面alpha/PID均逐bit稳定，Z行相同。该控制证实独立XY拟合相位影响，未把合法477判为错误caster，也不授自然闪烁首因或完整作者BRDF。

按[固定网格设计](advanced-object-coverage.md#model-directional-shadow-grid)，原Projection只替换连续XY跨度/中心，复用相关bounds和传入1024 coarse分辨率，以向上尺度分档及世界格中心直接构造一次矩阵；旧Z、凸裁剪、caster、bias、map/分配与N3消费保持。两个轴复用一个私有函数，产品净+14行，无新状态、资源、缓存或owner；新增两轴log2/ceil/exp2和round，不称零成本。任意共同平移的旧逐UV合同退出，同world表达、几何与深度覆盖保持；跨尺度档和旋转仍可能跳变。

候选直接重用旧实际执行的四份receiverWorld Float32矩阵，未按新texel重造位移。新编译/GPU 8.933秒、单CB完成，原点位/BC3/诊断N3材质/固定near查询及shadowoff与旧逐bit同；四相位production矩阵、全Float visibility和完整Half返回RGBA分别全逐bit稳定，前述两个range归0。heldXY最小30.930物理格、Z余量.000997987，原held/off/t0、远接收物实际覆盖、alpha/PID与原世界矩阵控制全通过；shadowoff颜色与旧输入逐bit同，不把四点稳定外推全景。

CPU现有门30行/10方法通过2.605秒，旧连续源同JSON为8绿/2个新增网格方法红；原21固定输入字典保持。五个metamorphic位移由各版真实返回矩阵反推，实际worldShift不同，不能称同world因果对照。整体world+camera平移的原XY等值断言按新合同修订，Z/尺度/覆盖仍核；同world镜像非uniform、正负整格、中心格边界与尺度档边界另核，临界角点Float32滤波余量2.501007格。最近实际Frame/颜色深度/三灯覆盖与生产make像素门共8方法通过29.421秒；其他固定矩阵内核和独立Spot/Point不重跑。CPU门与产品/carrier/实际读回分别经独立审查；存量依赖门仍报队列已登记的5边；结构15方法为14绿/原目录命名方法红，含Tube与PreparedTask两项，登记门仍报原架构文档未登记，相关源/布局/登记均同HEAD；开放队列已保留，不冒全门绿。

普通Debug26.293秒，产品/project/锁文件前后同，strict-deep及trusted helpers通过；exe c7ebc838…4f608、dylib30bc27f2…3f5cc、metallib仍7c94461a…c2cbb7。冻结33/2268×1474、原358自然40秒/after32、独立343五秒分别有3/7/2次capture；实际模型→main/display→export/seal→同request/CB/texture snapshot completed、trunc0/parse0并排空。after分别F238/R3、F939/R6和F175/R2；根与独审核完整球/环/主影，以及地表/云/暗面/大气/银河/钟日。原景相位未配对、7秒采图不授高频闪烁关闭或官方逐像素一致。

同frozen33/3024×1964、目标60、warm30/duration45，候选→独立035基线各实测13.502/13.505秒、0failed：FPS59.843/59.978，CPU P50/P95为2.706/2.958与2.685/3.018ms，GPU为13.568/14.362与13.618/14.141ms。逐帧pass/copy census同；pool采样峰166329344/213842432B、GPU allocated701415424/750436352B、footprint1536591504/1584973504B，不能把在途/暖驻留差授为固定减内存。短窗、背景与热状态未完全控制，不授稳态、能耗或严格因果；本批停止加迟滞/缓存，残余真实微模型颜色欠采样沿下一节和开放队列继续。

控制输入、旧/新原读回、源身份与独审归`.artifacts/scene-model-shadow-grid-20261117/evidence.zip`（9,706,573B，SHA3f47c3b1…6db7a9，392条逻辑记录/236份唯一原字节逐SHA核验，14天）；原作者运行载荷归`.artifacts/scene-evidence/runs/scene-model-shadow-grid-20261117`（92,437,863B，保四张原PNG沿96MiB单包例外，14天/总5GiB不变；周期PNG仅保原报告记录，不冒全部已晋升）。唯一连续DD及当前有效1×App保留；31项测试运行副本、临时HOME/App和可重建native缓存经归档覆盖、fresh PS/lsof及原inventory一致后已精确清理（19,785项、逻辑2,727,130,599B，不冒物理释放量）；035对照App已在C7基线交接后按独立清单精确退役（3,802项、逻辑268,705,862B），身份/输出与未解决真实几何输入保留。

## 世界模型的亚像素颜色覆盖 <a id="model-raster-coverage"></a>

无shadow的真实456 cameraDepth前缀→462/479颜色链已证几何跳变：2268×1474相机四个对角相位0/.25/.5/.75px，(663,888)仅.75相位被479的PID684958覆盖；源face面积约.3199px²、alpha1，使R约.174→.0639。保原BC3九级、PMA/back-cull与非writer，不能将全部环黑点归为错误投影或删除合法碎石。

同几何/相机的固定ROI有限面积参考中，1×/2×/4×alpha MSE为.024313504/.011507701/.003736049；但16坐标四相位中2×缩4/增5/同7，不授全局、单调或自然闪烁改善。RGB还受LOD影响，不以此授颜色参考真值。固定五点CPU滤波因覆盖误差与细线扩散已淘汰，不续调或用全景模糊关闭问题。

2026-11-17后续研究沿原MainPass/pool/PSO建立同N颜色与cameraDepth，包含普通image/text和通用terminal；无中断域memoryless，真实中读/离屏域private，只有原1×可读输出。近远两序、半透明、先读far再续near、clear=false、离屏后续画共16行实际读回通过；通用terminal新增9项实际像素/冷暖/反例通过。完整材质门另9项在相同HEAD原生重放中逐项同失败，未改golden，归开放队列；不把聚合门称通过。

同真实三角形的private保样本+resolve/private最终resolve/memoryless最终resolve三组输出逐Half同，18正确性与84交错计时的中位3.316500/3.166812/3.120667ms；memoryless色深allocatedSize为0，不能外推整个App零开销。原N2候选逐次解析导致完整358 GPU中位28.427ms；按实际读取才解析后，每帧14段只有2次resolve，降到18.463ms，仍高于1×15.180ms。

完整358原包45秒/warm30、native3024×1964的1×/迟解析2×测量窗13.488/13.408秒，submitted FPS31.434/31.027，CPU P50/P9518.714/19.521与18.971/19.862ms，GPU15.180/16.806与18.463/20.984ms；池峰778770192/896356656B。成熟画面保土星、主环/主影、时钟与图标；同冻结输入ROI可见黑色方块与环边阶梯缓和，碎石暗点仍在。冻结33模型的memoryless域约60FPS、池峰均138378496B，不代表完整原包成本。

独立已验收347同build4、30秒/after25/HDR.3近时1×/2×控制中，submitted FPS45.434/42.352，GPU P50/P9512.178/13.563与13.316/14.843ms，池峰308728832/451268096B。白紫发光边、亮尖、黑心、背景光带和钟日公式保持，未见足以抵销成本的新可辨收益。两次独审据此撤回通用默认2×及全部配套PSO/cohort/策略/API和测试接口；产品继续1×。短窗不授稳态、能耗或严格计时因果，但已触发候选停止线；不以三角形数量/AABB密度或样本名单挽救默认许可，现prepared元数据不能区分细分曲面与独立亚像素碎石。

此前完整影像与面积研究保在`.artifacts/scene-model-raster-research-20261117/evidence.zip`，低成本存储研究保在`.artifacts/scene-model-tile-research-20261117/evidence.zip`。本轮新增研究归`.artifacts/scene-model-raster-withdrawal-research-20261117/evidence.zip`（12647881B，SHA33896157…149125，478 aliases/351唯一payload逐SHA复验，14天）；五场原包完整App按真实数字ID独立保于同名前缀的Scene evidence runs，各低于32MiB，共享5GiB。早两份源只有SHA+原读回，不授旧版本完整重编；相应两probe/库保留。37个已停用App/HOME/sample及编译子项经提取与fresh PS/lsof、原inventory核对后精确清理，逻辑4150016682B，不冒物理释放量。研究不冒现役资格。环自然闪烁仍开放，重启须真实完整原景收益及健康独立样本成本共同通过，不重复默认N2或五点滤波旧路径。

## 深度与帧临时纹理复用 <a id="depth-submission-order"></a>

按[使用期合同](../architecture/scene-resource-admission.md#depth-submission-order)，原深度pool保三个slot与每CB独立预约，tracked同queue已enqueue前驱可共享；原scratch Entry沿既有pin许可复用。退出跨CB无条件复制和逐part不可变shape重验，保同CB/未enqueue/跨queue/untracked、取消/完成/reset、精确准备身份及history/SceneColor边界，无第二资源/预算owner。

旧/新深度10例24CB、frame scratch8例17CB读回保持；同frozen33/3024×1964的四张16bit原PNG均SHAb10fa13f…10d8628。原短窗pool峰213842432→138378496B、CPU中位反增.424ms，不授CPU/能耗改善；实际原记录归`.artifacts/scene-frame-scratch-order-20261117`及同名formal run。新后台runner以原Surface/GPU/PNG链取native3024截图，ready/after仍逐字节同b10fa，foreground ASN前后同；不代验前台点按。

<a id="frame-resource-preflight"></a>
同帧完整驻留预检集中到原FrameResourceBundle：退出FramePreflight重复resident快照、evaluate、allocationPlans及无producer的deferred结果；原Admission消费bundle的ready/busy/rejected，busy仍延期，拒绝保原原因。五产品净减11行，无新缓存/token/预约owner。Graph34、copy/history1、coordinator生命周期1共36个不同方法实际通过；新增busy→同请求完成后ready→取消无残pin三项全真，96B拒绝无pool/native增量，原像素/history与取消保持。退两条强绑旧调用位置的源码字符串断言，未放宽行为golden。

原Cache在预算已足够时直接返回，退无用victim列表/排序；真实生产helper的-Onone交错8进程、16/64/128居民微基准中位18.025/86.843/171.686µs→1.554/5.530/10.933µs。两预算逐出/pin控制逐值同；0CB/0GPU，仅授helper成本，不外推App或OS冷启动。

最终Debug24.024s、12个产品/project/锁输入前后同，strict-deep与trusted helpers通过；exe370857cf…d8ce566/dylib7166bbe1…33d35b，Metal仍7c94461a…0c2cbb7。完整358原包两场95秒/warm30/after35，原1×构建→候选各63.502/63.495秒有效测量，CPU P50/P9519.236/20.047→16.639/17.325ms，submitted FPS30.865→33.641；GPU15.171/16.830→15.179/16.885ms。每帧15main/11depth/28offscreen/16Program/12source/3copy及91094528B拷贝完全同，均0failed、stopped/surfaces released/GPU drained。两成熟图保土星、环/主影、钟日与图标；自然clock/label不同，不授整图byte同或完整文字正确。

呈现间隔P50/P95均33.333ms，进程CPU总时78256.727→78693.736ms，不能将单帧节省授为总占用、能耗或所有设备收益。pool峰863079184/861334736B仅为本场采样，不作固定资源节省。独立347保原30秒/after25/HDR.3，成熟白紫发光边、亮尖、黑心、背景光带及钟日公式保持；submitted45.423、pool308728832B，和近时原1×45.434/同池峰相当，只授健康画面/成本保持。环自然闪烁仍开放。

本批源/原生读回/CPU采样/独审归`.artifacts/scene-frame-resource-preflight-20261117/evidence.zip`（6284251B，SHAbc3d5904…98cffae，236别名/179唯一载荷逐SHA复验，14天/总5GiB）；原包baseline/candidate/347与profile-diagnostic各保真实数字ID的独立formal run，后者不作干净成本。共21个停用运行/编译叶（含旧71/75 App）已按提取、fresh PS/lsof及精确inventory退役，逻辑3145366435B，不冒物理释放。保唯一连续DD、一份baseline5 App和三份缺旧源的唯一probe/库。

## 确定零覆盖的模型工作 <a id="model-zero-coverage-work"></a>

按[零覆盖设计](advanced-object-coverage.md#model-zero-coverage-work)，原Frame每层只消费一次归一alpha，严格零返回空draw；逐part将既有完整动态材质投影前移，非normal且opacity严格零在mesh/pose/albedo前退出，normal0仍保颜色、相机深度和受影，仅在原caster角色退出。2026-11-17本次7+/6−净1行，无新状态、资源、PSO、缓存或owner。上游Script/Timeline/动画/provider调度和graph demand保持；外层world/normalMatrix仍可能计算，不授整层逆矩阵或全provider停工。

层零门的既有真实479/462 BC3/456控制保8CB/41项、同renderer0→1→0/改名、四近点RGBA与absent同及正值合法影；仅剩零接收者时的cold4096影池67108864B→0，normal0的无用1024投影池4194304B→0而白色/深度保留。该资格与原始失败归前批零覆盖包，不授一般驻留/FPS/能耗，也不推断TEX alpha上界。

本次固定同真实几何、相机、灯及四近点，只把远lit noncaster设translucent、层alpha恒1，typed material依次absent/0/1。旧67b三CB健康，zero仍保draw，fit和近RGBA错误地与正值同；当前0d54三CB全部正确，zero的fit/近RGBA恢复absent，absent与one所有业务字段与旧逐值同，三行bodyDepth精确同。正值合法caster实深度<1；不是换cast、关灯或统一提亮。这只授typed Frame材质输入，不冒SceneScript/属性面板回流或作者自然动画。

CameraFamily实际226行与永久normal0受影两CB完成，原217+3输入和全部220行输出字段逐值同，未排除token或放宽旧断言。新增六行核cold1→dynamic0、cold0→dynamic1、additive0，以及同层健康part与缺named part：零part不查询，健康颜色/深度/合法影仍在；正值和normal0仍查询并保持未就绪语义。normal0实际受影开/关仍为32/56、cameraDepth .001900196同。Native九方法先实际通过；按审查退去过大失败域golden后，最终九方法复用同226+2真实读回作CPU断言重放，carrier/input/产品不变，不另编译GPU。新mixed-named两反例只核query、pending与健康色深，不固定撤影或零池来保护旧失败域；相邻ordered named缺项仍会扩大影图失败范围，留[开放队列](../roadmap/scene-open-breakpoint-queue.md)，本次不盲删完整性标记。

Debug29.067秒，Frame/project/锁文件前后同，strict-deep及trusted helpers通过；exe17bd1c19…ae434、dylib89146505…43ee1、metallib仍7c94461a…c2cbb7。冻结33八秒/after4/75%和独立343五秒/after3两App共70.055秒通过，五身份与输入前后同，均stopped/surfaces released/GPU drained。after分别F239/R3与F172/R2，28/2模型进入同次main/export/seal、GPU completed且截断/解析错0；2268×1474冻结PNG仍为1d1e6cde…9916，与前一有效基线字节同，独立地球纹理/大气/暗侧/文字齐。未重跑未受影响的原358四十秒窗，不据短运行授自然环闪全部关闭、官方一致或性能收益。

当前源、实际GPU及完整App证据归`.artifacts/scene-model-non-normal-zero-20261117`和同名formal run；此前层零/材质零caster资格保于`.artifacts/scene-model-known-zero-20261117`，其native不可变manifest仍反映封口时App pending，实际App/最终独审另附。更早dc8与已淘汰五点重建归`.artifacts/scene-model-zero-layer-alpha-20261117`。本轮保唯一DD、bd01对照App与未解决真实几何输入，不重写旧包身份。

## 半透明模型的覆盖阴影 <a id="model-shadow-coverage"></a>

2026-11-15按[实际覆盖合同](advanced-object-coverage.md#model-shadow-coverage)，只撤原Frame的translucent caster类别门，保原cast intent、可见prepared、三灯>.5 material×layer×实际albedoA覆盖、cull与camera depth独立；additive原行为不另设禁令。唯一产品Frame净−2行，无新资源/PSO/ABI/owner/状态或普通帧解析；恢复的caster会增加原有每灯map绘制/必要申请，不授零成本或性能收益。

同一测试/输入的旧源两方法为原120 cull行通过、coverage方法在translucent的[1,1]失败，健康peer仍[.5,.5]。当前两个方法26.397s通过：原120行逐值不变，新增23行经过真实Frame筛选/三灯map读回，normal与translucent的两点深度完全一致；孔洞为clear1/covered，directional covered=.5，spot=.400000006，point两点约.40316/.40306。alpha恰.5不写/下一个half值写，material×layer×texture乘积、maskA0不挖孔、castfalse/hidden、additive、反面cull/nocull、camera test/write独立与改名变换均有结果；健康opaque peer使反例仍有有效map。旧新Harness/输入字节同，源identity仅Frame一项改变；不复制shader或BRDF。测试shell只补上批新增的可空pigment传参，不增加材质行为替身。

普通Debug28.794s、Frame/project/锁文件前后相同，签名/原helpers验证通过；executable840105de…8d304、dylib076accad…8aa47，metallib仍5917c277…01900，与旧App逐字节同。真实3589454154的ring462/planet456所需七份原资产64.9MB在owned目录共享只读硬链，原用户pkg/媒体不链接不写；原ring1024² BC3/9mip/linear-repeat，首mip覆盖>.5占43.53%，不是实心环。保原MDL/TEX/材料/MR/alpha，固定模型/相机/单directional且sphere castfalse，on/off仅ring.castshadow切换。弧度角经原Definition的−worldX列核光向量，世界矩阵三场逐值一致；源/协议/App SHA前后不变。

旧on、当前on/off均F94/request1，CB502016033664/507002143616/531765379968分别把456/462供同次main/seal，GPUcompleted/trunc0并排空。off与旧on逐PNG/RGBA完全相等；on出现清晰弧形暗带。1280×831全图6061像素改变，均在预先固定的球面保守矩形内；前景颜色并集263162中变化2.3031%，平均绝对RGB差1.04903 byte、最大135。该矩形包含前景星环，6061不能全授为排除ring自阴影后的纯接收球面像素数。独立几何在读取新App像素前选定的alpha-hole与无遮挡受光两个5×5区域均逐RGB零差；未取得covered 5×5，不称三类ROI全部通过。二值map的数值覆盖由前述Frame门承担，可见弧带及可逆终端颜色由此真实资产配对承担；不授半透明透射、原作者全景严格A/B或官方阈值。

当前on的depth-written只观测首epoch1–3、light259/casters1，旧on与当前off无该事件；F94的trace不含内部map绑定，不能声称终端帧全量阴影map执行观察。颜色/model状态/main/seal与GPU完成仍按同次capture闭合。原3589454154自然35s/after32的F870/request1/CB501301071360/main501198989952有24个模型含球456/环462实际绘制，已越过作者进场而非只看片头；独立3437487219五秒F140/request1/CB500997588736/main500942233088的112/114绘制。两场原project/pkg摘要等冻结matrix，App签名前后核同，终端图有土星/环/文字及地表/云/大气/星空/时钟，GPUcompleted/trunc0并排空。原场景相位、取景未配对，不授原景逐像素阴影归因或其它反馈关闭。

原作者报告、必要图与日志归`.artifacts/scene-evidence/runs/scene-model-shadow-coverage-20261115`；真实双模型开关/旧基线、143行红绿、身份/构建与独审归`.artifacts/scene-model-shadow-coverage-20261115`。

## 聚光灯指数与共享径向边界 <a id="spot-radial-falloff"></a>

2026-11-15按[径向合同](advanced-object-coverage.md#spot-radial-falloff)，原Format一次保有限非负exponent，原SpotSnapshot/图像preflight与两payload把作者值交到实际Metal；缺省2/显式0，cone/强度/阴影各自独立，动态指数与旧经验volume不扩。共享sceneRadialFalloff消费已求worldDistance/radius；正指数先截止再求曲线，零指数规则见下文当前修正。旧remaining API、模型正距离1e−8平方死区与1e−4半径floor退出，原方向距离只求一次，radial0跳无能量BRDF。图像保max-component长度路径，去packer重复整包finite扫描，只保最终Capture.init（含VP/reflection、逆矩阵及point/spot尾向量）。八产品净+11行，模型1488B/Image880B各追加16B指数向量，无owner/PSO/资源/cache/光列表或热解析，不授整体性能收益。

真实parser/snapshot CPU方法3.850s过缺省/0/.54/负/非finite/bool/错型及包装fallback，颜色/同帧世界变换更新保指数；无live指数target不授热更新。图像原CPU打包方法14项核四槽0/.54/1/5、混合配额、缺省与ABI，唯一final init在真实GPU载体拒point NaN/spot Inf、逆矩阵、补入的VP/reflection坏值且健康payload接纳。原preflight邻例42.726s通过；机械适配其typed Spot stub，未另造材质行为。首Image GPU因新增helper与旧变量同名未编译，改名只补该方法、复用有效CPU分支；该批沿共享截止的零指数预期已由下文实际官方控制和新字面预期替换。

该批模型六方法/225实际输入8.516s通过，含44条Spot的多归一距离/.54/0/1、cone过渡/外、legacy/stock等值入射，以及20条point/spot正近距、小radius、重合与大边界控制；保原发光、HDR/雾、view tint、alpha及frozen响应。图像最终一方法14.096s通过36条Spot及原12矩形/13family；默认2/legacy2逐像素等值，四彩灯槽、alpha.5、轴向100.nextDown/up及对齐center的3–4–5斜边界/内外均有真实读回。正指数边界/外精确0、内保持正光；当时零指数的截止断言已退出，不再作为当前边界资格。独立入射控制不复制BRDF，误差未放宽。旧同模型载体的d≈1e−5/e0/r10点灯与Spot均RGB0，对照directional=.33203125，保该反例；修后对应正例恢复。旧失败和中间结果不升级为最终资格，极端Float上下溢、legacy image point平面下限不由此扩大。

唯一普通Debug32.510s，八产品/工程/锁文件前后字节一致；签名与原helpers通过。executable cb94d100…05f94、dylibba4ea20d…182a7、metallib4957688f…883bf1。复用真实Saturn sphere四原资产63.18MB，原world/材质/alpha与camera不变，无脚本单Spot同camera位置朝0，r16/I1/inner20/outer30且整球最大离轴角11.1°，shadow/volume/ambient/HDR关闭；只切作者343/84的.54000002与2。旧.54（原消费2）F94、当前.54 F95及当前2 F94/request1，CB535993140096/501210694528/534798386048，球456供同main/seal、GPUcompleted/trunc0并排空，所有输入/协议/App和world保持。

新2与旧基线逐PNG/RGBA全等，0像素差；新.54对新2的1280×831前景颜色并集90953中90375（99.3645%）变化，平均绝对RGB差7.90573 byte、最大14。预定球内32²区域全1024像素改变、均差11.28874，RGB均值(10.998,10,8.75)→(23.307,21.692,18.615)，未调强度/纹理/曝光。背景与终端alpha相同；颜色并集不是几何覆盖，App未读模型数值depth/alpha或GPU lamp uniform。此为同真实资产的自有径向供货贡献，不冒充343原景逐灯像素或官方host曲线；typed/native门与App终端各授实际范围。

原343五秒F141/request1/CB527375944320/main527370362368的112/114到主画布；84原typed指数.54、radius6000/I3、cone72.29/77.94与parent57已保，不据自然相位图单独归因。独立3453730450自然20s/after17，F780/request1/CB520733231744/main520724060416的53/77具体part/306/340/342绘制。两场源摘要=冻结matrix、App签名前后核同，终端地表/云/大气/星空/时钟与月面/轨道/标题完整，同capture seal/GPUcompleted/trunc0并排空。spot-light failed已定位为未请求volume时的诊断，不称surface失败，留队列归原owner。

原作者报告/图/日志归`.artifacts/scene-evidence/runs/scene-spot-radial-20261115`；真实球指数控制、225模型/36Spot图像与原邻例、入口/最终finite门、局部失败、构建及独审归`.artifacts/scene-spot-radial-20261115`。

### 零指数不限制表面光半径

2026-11-15，3662790108的Pluto/Makemake/Haumea/Eris在首15目标两相反视角均近黑；同原作者847对象/材质/纹理/灯及实际焦点的官方Eris A可见右侧灰色受光纹理。太阳3692声明radius100000/exponent0/I6，原脚本同写世界位置与共享记录，Eris A距离约120万；该源链不冒作GPU灯uniform读回。官方2.8.0.42（PE daac1ea7…bda07）的真实Eris几何/TEX、单point、无ambient/volume/shadow小控制中，e0范围外与同尺寸全资源/ID改名均完整受光，e2范围外为黑实体、e2范围内有纹理，独立蓝peer保持。×10尺度控制官方填满窗口，退出官方取景资格；本地尺度变体仍有效。以上为实际原生窗口人工定性观察，无本地官方PNG或逐RGB/完整BRDF资格。

原共享sceneRadialFalloff只增一行e0返回1，正指数的截止/乘方字节不变；无新owner/状态/ABI/资源/重复距离，保持cone、有限阴影投影、重合点无方向、旧2D point及volume。先保旧源在新字面预期下模型7方法10失败、图像1方法2失败，再用同载体当前源：模型7方法/244输入8.019s、图像1方法12.431s全部通过且Metal validation实际启用。模型只10条e0边界/外侧RGB改变，234整行逐值不变；图像13family+36spot仅6条改变、其余43及12rectangle汇总逐值保持。所有原alpha相等，HDR/coverage颜色保持；这些门不含新shadow/depth数值读回，相关源码不变，不能冒作三灯map新资格。

普通Debug12.643s输入稳定，签名/原helpers通过；exe453a90b9…8fb1、dylib8ebc6f49…73df、metallibcd47906e…30b4。五个小型控制同输入旧新App串行，三个e0范围外/尺度/纯改名各115830个RGB像素改变，e2范围内与范围外全图逐RGB相同、五peer核心不变。先前两wrapper短暂重叠的两轮已排除验收。真实作者四矮行星A/B仅私有驱动startIndex/count缩小，原847对象、1174非scene条目与原project保持；八个实际选帧分别有strict READY→END HOLD、encoded后继同request/CB/main/seal/GPUcompleted及RGBA无损查看资格。A已见Pluto地形、Make左新月、Haumea扁球薄受光及Eris右亮半球，保暗侧实体；自然时钟与相位未锁，不授作者逐像素A/B。A整轮通过；B末次series0011/request14在teardown失败，整轮保FAIL而八个目标选帧独立有效。独立343原包五秒F167/request1/CB526007027456，112/114到main/seal/GPUcompleted、零截断并排空，地表/云/大气/星空/钟日完整，保其正指数spot路径，不单独归因逐灯像素。

自有输入/旧红新绿、实际选图、官方观察、源与构建身份、独审归`.artifacts/scene-radial-zero-20261115`；独立原作者收据归`.artifacts/scene-evidence/runs/scene-radial-zero-20261115`。半径外阴影、全部卫星/航天器/镜头、实际双击交互与366整体官方一致仍开放。

## 模型材质的数值数组 <a id="model-numeric-arrays"></a>

2026-11-15按[输入归一合同](render-graph-shader-coverage.md#shader-value-numeric-arrays)，现Format ShaderValue共享raw/kind/components投影退Document/Catalog重复数值解析。真数字数组保全量顺序，单项保number/raw单token，布尔/混型/空及未知包装不从调试文本抽数字；旧字符串和原scalar完整证明、Document-only Timeline/既有nested scalar/string、Catalog无nested及wrapper元数据保原。三产品净减13行，无新owner/cache/ABI/普通帧解析；原构建语义身份覆盖Format/Assets，不另清播放缓存。重复函数组103→102并由原门收紧基线。

同23个数组/字符串/坏值载荷在旧两入口保26条失败子断言；最终Document/模型材料/vec2相邻19方法及Catalog12方法共31方法通过。实际parser核1/3/5/16项完整值、user:null/script/properties/Timeline及nested差异，模型真实prepared字段核颜色/单项scalar，无复刻解析或BRDF。首候选误删无关normalizedPath的编译失败已恢复并由最终门覆盖，保失败收据；不授一般uniform数组、矩阵GPU或新动态target。

普通Debug41.627s，三产品/project/锁文件前后相同；签名/原helpers通过，execa839520a…7fbd0、dylibdf225e0c…76137a，metallib仍4957688f…83bf1。复用358原球几何/两TEX，自有无脚本scene的相机/world/spot/曝光/材料其余值冻结，只改color=[.2,.7,1]或等值字符串。四场均F94/request1，旧array/string的CB536677401472/517652005760，新array/string为533174240128/511699600256；456进入各自main/seal/GPU完成，零截断并排空。旧array typed颜色unknown、旧string及新两场vector[.2,.7,1]；新array、新string与旧string三PNG/RGBA逐字节相等。旧array→string有90370个RGB像素改变，固定32²ROI平均RGB[52.71,48.98,42.46]→[12.02,35.67,42.46]，终端alpha相同；这是颜色贡献，不授几何覆盖或model uniform GPU读回。

原3437487219自然5s，F136/CB526867416832的112/114到main526816402304；独立3453730450自然20s/after17，F771/CB521702624768的53、77所选part及306/340/342到main521616583296。两原入口摘要匹配、同main/seal/GPU及排空，地表/云/大气/时钟和月面/轨道/标题/时钟完整；不认领原作者数组命中或自然钟严格A/B。首次benchmark多传一层Scene目录，输入缺失且未启动App，修正参数后才取得这些资格。

自有输入/前后四图、31方法及保留失败、构建身份与独审归`.artifacts/scene-model-numeric-arrays-20261115`；原作者报告/必要图和日志归`.artifacts/scene-evidence/runs/scene-model-numeric-arrays-20261115`。旧最小数组复现解除未解决保护；官方像素、性能及更多shader消费者未授。

## 小帧UV的模型颜色与投影 <a id="small-atlas-frame-uv"></a>

2026-11-15按[共享UV合同](render-graph-shader-coverage.md#small-atlas-frame-uv)，现SceneTextureUVTransform一份finite/nonzero谓词替换SlotBinding与StaticModel颜色/阴影入口的1e−7面积许可，旧私有valid/area实现退出。三产品净减21行，原raw frame入口各保同一次检查，无新owner/字段/ABI/cache/范围门、Double或普通帧运算；原Textures构建语义身份自然更新。旋转/skew与Loader轴范围仍未扩。

原真实Frame/Metal载体的同8个raw UV新增输入中，普通frame中心色[32,32,32,255]而tiny全黑且draw=false、整灯图未发布；旧三方法有两方法失败。最终三方法151条输入通过，原120相机/三灯与23覆盖行逐记录相同。tiny在directional/spot/point下的中心色均与identity相同，各投影所选两点的深度分别为[.5,.5]、[.400000006,.400000006]、[.403161734,.403064817]，与各自identity逐Float相同，peer投影相等。只授prepared-input真实Frame颜色/三灯投影读回，不借此授实际MDL albedo动画/provider全链或receiver最终阴影像素。zero/NaN仍拒draw；现Frame撤整light map、没有可读peer depth，沿[开放队列](../roadmap/scene-open-breakpoint-queue.md)独立处理，不授单caster隔离；原carrier假定first!的失败留在载荷，不把空map填成depth1。

真实4096² BC3 TEXS单frame（origin2048²、轴1,0/0,1、duration2.5）由原Loader→Catalog provider/publication→SlotBinding→8²实际Metal：旧tiny及实际改名路径unavailable、64像素全黑，32px frame健康；新两tiny ready且publicationComplete、physical/mapped仍4096²，UV两轴1/4096、面积5.960464477539063e−8，64像素全[.501953125,.501953125,.501953125,1]，与独立4² BC3/PNG逐像素相同。原37材质向量逐记录相同；最终57行为合同通过，zero/NaN仍invalid黑。旧55合同中的两tiny共4项失败；就绪后另两extent事实可观察，不把它们算旧可执行结果。Native5路径共4份唯一输入，逐SHA与App实际包内TEX相符，真正改名不靠label；已结束临时载荷由冻配方恢复并逐SHA核对，归档明确重放来源。

普通Debug32.244s且三产品/project/锁文件前后相同，strict deep/原helpers通过；exe39c4e2ec…a6d9d、dylibaf938e9c…b78eb、metallib仍4957688f…83bf1。原App自有载体只比较独立4² BC3与同alpha128的4096²1px frame，无灯/原albedo/颜色/相机不变；旧两场tiny黑而control[16,32,8]，最终两场同[16,32,8]且wholePNG与旧control逐字相同。两scene.pkg及原TEX旧新逐字同（tiny16777344B），原mapped保持4096²。新tiny F96/request2/CB533801385984/main533836326912，新control F97/request2/CB528768090112/main528803212544，sourceCapture→ordinary→main/seal/GPU、零截断与排空闭合。App五个执行文件全程固定；local driver漏UVTransform启动源码采样，真实三产品由既有Debug before/after和独立during/post receipt闭合，不伪称该driver在start采过。App不授内部UV/uniform读回。

独立3437487219原project/pkg匹配，自然5s的F138/request1/CB504072506880中112/114与135到main504131230592/seal/GPU并排空，地表/云/大气/时钟完整；未发现该作者活动tiny输入，不授原景缺图恢复、官方像素/性能或线性atlas边缘与独立图全部等价。自有源/输入/红绿读回与App图、构建与独审归`.artifacts/scene-small-atlas-frame-20261115`，作者原报告归`.artifacts/scene-evidence/runs/scene-small-atlas-frame-20261115`；未决坏caster失败范围另用独立保护包`.artifacts/scene-model-shadow-draw-rejection-gap-20261115`保留。

## 静态模型的单帧TEX <a id="model-single-frame-texture"></a>

2026-11-15按[单帧合同](advanced-object-coverage.md#model-single-frame-texture)，原Loader的静态候选已接一image/恰一合法frame，退整类sprite拒绝。原候选构造携实际frame与isSpriteSheet，保atlas physical/mapped、用途/色彩、revision/sampling/format；多frame不偷偷取frame0。首mip与decoded尺寸不同用缓存尺寸一次换算frame并只在该异域核实际源范围；普通同域不重验。单产品净增28行，无新owner/clock/持久字段/ABI/cache/上传或普通帧工作，原模型Entry/颜色/shadow与Catalog播放职责不变。

最近候选门原123项payload旧新逐值相同，实际11份输入SHA相同；新增23合同全过，旧有效红例15个正项失败而独立crop和相邻反例健康。raw 8×4/mapped6×4的非恒RGBA frame、真实资源改名、duration0均携UV(.25,0;.5,0;0,.5)，实际源shader取样RGB[32,64,128]等独立4×2 crop；原readback目标opaque clear使输出A255，不把它当源A128读回。normal/mask另证typed data/取样位置，不授normal照明。legacy embedded mip8×4/实际PNG4²的straight/PMA两目的均携UV(.5,0;.5,0;0,1)，实际像素[255,255,0,255]等独立crop；x6,width2在真实源外均拒。多frame、zero、NaN、越界保拒，原普通图/资源与上传门保持。第一次literal alpha假设失败已修正载体并保留原报告，不改输入/产品/容差。

普通Debug28.652s且唯一产品/project/锁文件前后相同，strict deep与原helpers通过；exe4e5189ce…95791、dylib17044829…0965d、metallib仍4957688f…83bf1。真实自有MDL、材质/光/相机与健康peer不变，仅TEX entry换独立4²crop或8²atlas的唯一frame（origin2²/轴4,0/0,4、duration2.5）。旧两场crop具三色/真孔/后景与接收面阴影，frame丢model2。最终四场通过；old crop==new crop==new frame的3024×1964两phase完整PNG及解码RGBA严格相同（PNGe38865c7…9daa0），新frame仍绑定实际8²源，未用小图替代。三实色为R/G/B200、孔/未遮接收面97、三影区5，bluePeer255；zero/multi局部缺model2，整图等旧missing-frame，peer保持。真实遮挡与接收者像素授效果，不授cameraDepth纹理数值或内部UV/frameIndex GPU读取。

新四场均F96/request2：crop CB517404771200/main-seal517396785792，frame CB533879882624/main-seal533869718144，zero为531430687616/531420244608，multi为503345234816/503335217792；模型[1,2,4]或拒绝后的[1,4]到各自终端/GPUcompleted、零截断并排空。old/new同两输入pkg及各entry逐SHA同，MDL/scene/材料不变。shadow depth-written等首epoch日志另作事件证据，不伪称F96内部map行；当前终端投影像素已有上述严格等值。原Catalog多帧/0duration/事务邻门一方法通过；首次因既有载体三处缺try编译失败、零GPU，修调用后补验，产品/输入/断言未改。

原3437487219 project/pkg匹配，自然5s的F123/request1/CB508680962944中112/114与135到main508687659520/seal/GPU并排空，地表/云/大气/时钟完整。限定五个星球包的117份TEX头均已解析且无sprite，不授活动作者单frame命中或原景缺图恢复。自有输入/红绿/整图/构建/独审归`.artifacts/scene-model-single-frame-texture-20261115`，原作者报告归`.artifacts/scene-evidence/runs/scene-model-single-frame-texture-20261115`。本节仅授当时静态入口；当前 albedo 多帧见[统一供货](#model-albedo-frames)，Catalog embedded 源帧见[共享准备](render-graph-shader-coverage.md#material-atlas-source-frame-evidence)。pigment图集像素域见[局部寻址](#model-pigment-frame-addressing)；仿射、官方像素/性能及任意线性边缘仍未获资格。

## 模型 albedo 统一资产与多帧 <a id="model-albedo-frames"></a>

2026-11-15按[统一供货合同](advanced-object-coverage.md#model-albedo-frames)，静态/单帧/多帧 slot0 全部沿原 Catalog→FrameProvider→Registry。冷 MaterialPlan 一次固定首 pass0、投影材质及需求，原 resource-planning 同时交接最小 readiness；Entry 退 direct loadCandidate/纹理驻留和双 nullable。普通帧只取当前 publication，颜色与 shadow 冻结同 draw；asset 缺供只丢 part，named 完整性独立。两 Task 整体归位、原免等待测试分支退出，无新时钟/worker/barrier/cache/Metal ABI。冷视频集合避免每帧重扫静态 Entry，并并入原独立需求与初供/暂停重试。

自有真实 MDL/receiver/健康 peer、材质/相机/灯相同，8² TEX 两个4²帧的时间固定.25/2.25，颜色和透明孔由象限1移2，对应投影同移。旧 d2ae/2a5f 的 crop0 健康、animated0 在实际像素处失败（模型与阴影消失），非 prepared-ID 先验阻断。新8b85/1acb 的两方法8场通过：两时间各 crop/animated、原 crop/single/identical-multi/zero；12组完整 PNG 与 RGBA 严格等值，ready/after各同字节，单帧输入不变。两时终端变化30176 RGB像素，实际typed UV分别[0,0;.5,0;0,.5]与[.5,.5;.5,0;0,.5]；该观测不等于 GPU uniform 读回，也不授同一 Surface 连续转帧。每图同 request/CB 的模型→main/seal/GPU 完成，零截断并排空。

TEX App运行对应首个不可变构建30.417s；其后仅资源/Ordered的冷视频索引收窄，最终Debug28.136s、产品/project/锁文件字节稳定，strict deep与原helpers验证通过；exe c74784a7…992c、dylib12daf356…f4c0，metallib4957688f…83bf1未变。复用未受影响TEX矩阵，不把首构建资格冒给最终源码。最终App真实TEXB视频albedo普通/启动即暂停两场分别15.281/14.803s：四处颜色[0,200,1]、投影[5,5,5]、peer蓝/未遮面97，模型[1,2,4]；暂停保持F0，首视频publication后才qualified并完成初帧GPU。初供前确有layer2 pending日志，未捕获其阶段图，不授无黑闪；不授模型媒体热换、隐藏effect共用视频像素、官方一致或性能。

最终App另以同一 animated 包自然时钟运行8.423s，不设时间覆盖、after延3s；同 Surface531235655168 的 request1/F33→request2/F96，两次沿同 atlas texture531253118208 取上述两UV，颜色/孔洞/投影实际跨帧。两张3024×1964整PNG与RGB分别逐字节等原crop0/crop1参考，各自main/seal/GPU完成、零截断并排空。此场补授同 Surface 播放；未读回精确SceneClock/GPU时刻或全部中间帧。

原四class Native32方法首次30过；新增缺图载体的两个part误共一纹理已改独立输入，原局部失败预期不动，Selection-only30checks全真。另以HEAD原产品/载体及同blends输入实读，三灯所有深度/像素与当前逐值相同，证明“translucent不投影”是旧oracle；退类别名单，保五个真实覆盖和cast=false反例，两个原失败方法用冻结GPU结果CPU补验通过。原失败和wrapper日志顺序误断言均保留，不把它们记成产品回退。Task3方法与SurfaceAdmission纯计划门通过；当前asset缺供/UV/sampler/PMA及冻结draw的6项正反检查全真，named原图回归保持。独立3437487219原project/pkg匹配，最终App自然5s、F140/request1/CB506203999744，模型112/114和图像135到同main506255019776/seal/GPU，零截断并排空；实际查看地表、云、大气、星空、时钟完整，非活动atlas作者命中。自有输入、完整红绿/图/身份、复用范围和独审归`.artifacts/scene-model-albedo-frames-20261115`，作者原报告与图归`.artifacts/scene-evidence/runs/scene-model-albedo-frames-20261115`。本批不授normal/map/lookup动画、跨image、仿射或全部atlas边缘等值。

## Noise图集帧的像素密度与局部寻址 <a id="model-pigment-frame-addressing"></a>

按[自有域合同](advanced-object-coverage.md#model-pigment-frame-addressing)，sprite noise从整atlas mapped除法改为frame实际源像素域，最小1目标像素；原typed sampler决定局部repeat或texel-center clamp。普通非sprite的完整UV、padding、采样和amount语义不变。原binding携冷尺寸/倒数，原uniform尾加16B至1504，旧offset不动；唯一UV仿射留在寻址后，未复制纹理、BRDF或资源/时钟owner。四产品净+32行，不授性能收益。

真实Loader原单frame raw8×4/mapped6×4的data门补noise purpose，isSpriteSheet/UV/采样与独立crop实读通过，24单frame及38Catalog合同全真。原Prepared/Frame/Metal载体47行/426文件同输入，修后同Harness的旧代码真实像素红、新代码原4方法全绿；五组nearest/linear、repeat/clamp/改名的sprite/crop在RGBA、6邻像素、outside与depth严格相同。两个subpixel域的受测中心/探针均为[14,21,28,255]且等dark控制/同深度；不授fractional线性过滤隔离。原35行/318文件保持，原4方法全过，除冷Set请求顺序外全部字段逐值同，请求内容和次数同。首轮Native夹具复制候选漏isSpriteSheet已补一字段，初失败原报告及driver尾误断言均保留，未以此改产品/输入/像素预期。

完整App真实slot8 raw8²、origin2²/frame2²黑白noise，对独立2²crop；Chroma/常灰albedo/方向灯/真实MDL/接收面/peer全部同字节，仅grain.tex不同。旧c747/12da的crop七个物理pixel交替54/80，atlas全72；新38010e6d…b1d5d、dc83a35b…380b7、metallib9062517f…0864d的两场恢复同54/80，ready/after完整PNG与RGB均逐字节等旧crop（PNG0d11389b…be90a00）。新旧atlas仅19370 RGB像素改变，bounds(1451,900,1573,1064)限模型surface；阴影全0、receiver93、蓝peer及外部不变。四图同request/CB的model→main/seal/GPU完成，尺寸等实际3024×1964，零截断并排空。旧31.820s/新31.496s两场是功能运行，不能当作性能对照；原11组fixture字节保持。

普通Debug31.656s，四产品/project/锁文件前后稳定，strict deep与原helpers通过。独立3437487219原project/pkg与matrix/report三方匹配，最终App自然5s，F147/request1/CB520161054208的112/114模型及135图像层到同main520225414656/seal/GPU完成，零截断并排空；实际查看地表、云、大气蓝弧、银河与时钟完整，执行18.253s且App/四产品身份稳定；自有输入/红绿/完整图/身份/独审归`.artifacts/scene-model-pigment-frame-20261115`，作者原报告归`.artifacts/scene-evidence/runs/scene-model-pigment-frame-20261115`。真实作者原整图noise只作回归，非活动sprite作者缺陷恢复；不授官方像素、跨image或任意fractional/线性边界等值。

## 模型仿射TEX的颜色、孔洞与投影 <a id="model-affine-frames"></a>

同[源帧构建/输入资格](render-graph-shader-coverage.md#material-affine-frame-evidence)，真实MDL/albedo/receiver/方向灯/蓝peer不变，8² atlas原4²彩色/透明孔区域只变TEXS轴。rot90原像素域O(6,2),X(0,4),Y(-4,0)，mirrorY为O(2,6),X(4,0),Y(0,-4)；两者分别对独立排列的4²crop。旧38010e6d/dc83a35b的crop颜色/孔/影健康，rotframe丢model2，在应蓝200处仅receiver97；未被prepared-ID先截断。最终App五场75.551s通过，rot四张完整PNG同2383aee9…6b7037，mirror四张同1381ba1a…07fe5，各自crop/frame ready/after完整像素相等，非只profile命中。

skew用O(1,1.5),X(4,0),Y(2,4)，只授四个字面probe：源texel(2,2)/(3,4)/(5,4)的RGB精确为[60,70,76]/[80,110,110]/[120,110,114]且对应影5；(4,2)透明孔的颜色与投影均97，peer蓝。它不宣整个skew等于矩形crop。实际typed source UV分别[.75,.25;0,.5;-.5,0]、[.25,.75;.5,0;0,-.5]、[.125,.1875;.5,0;.25,.5]，属于draw输入观测，不当GPU uniform读回。各图同request/CB model→main/seal/GPU完成、零截断并排空，原13组model输入不变。

独立3437487219原project/pkg与matrix/report匹配，最终App自然5s，F140/request1/CB503923197696中112/114模型与135图像到同main503972617728/seal/GPU，零截断并排空，18.383s执行且App/六产品身份稳定；实际查看地球、云、大气、银河星点与时钟完整。作者报告归`.artifacts/scene-evidence/runs/scene-model-affine-frame-20261115`；本节只授上述自有整数nearest/clamp帧，cross-image、任意线性边缘或官方像素不由此推导。详细原始输入、完整图、失败与独审归`.artifacts/scene-model-affine-frame-20261115`。

<a id="model-normal-consumers"></a>
### 模型法线需求与保有面积的零轴平面

按[实际消费者合同](advanced-object-coverage.md#model-normal-consumers)，原Material纯需求供Frame/独立Pipeline共用；有限world中无lighting/viewTint/潜在reflection的part用identity法线载体，不求逆，仍沿同draw参与颜色/depth/shadow/volume。Frame只在有需求时至多求一次原Double逆转置，singular只退对应part且先于named查询；原world有限性前移到Frame实际入口，Pipeline已有入口继续守其提交域，退数学内与prepared产物的重复重验。三产品净+7行，无新shader/ABI/PSO/资源owner/状态/cache，normal纹理原准备资格未扩；原数学签名和线性计算保持，不为SDK无内置矩阵转换再加helper。该几何算法不宣官方一致或活动作者rank2命中。

普通Debug29.753s通过，三产品/project/锁文件构建前后同；strict-deep与原trusted helpers通过，exe521462eb…7a69、dylib9171e7cf…7e20、metallib仍9062517f…0864d。旧App两场31.509s中XY正常控制先通过，仅subject scaleZ1→0后红200位置实际露后绘蓝200，原模型丢失；新同输入四场60.318s全过。XY及经父Ry90/镜像、实际MDL/material/TEX改名的YZ scaleX1→0两对，ready/after完整PNG全部同c7559ada…5476，并等旧XY正常控制。非恒红/绿/蓝200表面、透明孔露后绘蓝面、实体影5/孔影97、蓝peer255保持；日志核subject2先于far5，后绘远面启用test/write，故遮挡对照可区分。每对除scene单个scale分量外全部输入同，原18变体字节不变；六场12捕获逐一同request/CB/main/seal/GPUcompleted、trunc0及排空。运行时长是功能验收，未授性能对照。

原Frame载体的原120程序循环及31 JSON观察共151行完整结果逐值同，新增41项，共192行同输入实际GPU读回；旧二进制新两方法24个子断言红、无执行错误，新五方法全过。两版复用同一Harness/JSON，无API适配；有面积XY/YZ、组合旋转/镜像/改名world的unlit恢复实际白色/相机depth与三灯map深度，mixed的lit/view/reflection只退其part，unused named不查询，零面积/非finite world保独立peer。原NormalMap六方法36输入32.111s通过，原动态材质/normal数学7.717s通过，保小非零、非均匀、负det与原方向/手性/alpha/depth/反射断言；不是把测试业务逻辑重写一份。原CULL Swift169行完整归位fixture再扩原class，两份测试674/251行，未新建suite或renderer；初两处载体构造/必需参数编译失败为零GPU，原日志保留。产品未因载体失败改变，未增加普通帧诊断或缓存；此Native载体不授实际parent resolver、named provider readiness、volume replay或normal uniform反读，父层级只由前述完整App实际变体资格。

独立原3437487219自然五秒18.593s运行，F138/request1/CB527020903936的112/114模型及135图像到main526972165632，终端封口/GPUcompleted、trunc0/parse0并排空；原project/pkg摘要等冻结matrix与运行副本。完整地表、云层、蓝边、暗半球、星空银河及钟/日期可见，仅授普通作者回归；未冒称全树运行后哈希或作者使用零轴平面。必要原报告/日志/终端已按14天/32MiB晋升`.artifacts/scene-evidence/runs/scene-model-normal-consumers-20261115`；生产输入、原生结果及独审归`.artifacts/scene-model-normal-consumers-20261115`。

<a id="model-material-opacity"></a>
### 模型 opacity 的冷归一与健康投影

按[单一归一合同](advanced-object-coverage.md#model-material-opacity)，已证alpha角色的有限Double不再先按Float范围拒整part；原Compiler仍保完整数值/形状证明及其它channel域。legacy/builtin只在原raw入口将非有限opacity回缺省1，authored复用已有Double有限性保证，两者共同在Resources唯一clamp0…1再Float；原dynamic有限Float路径保持。全产品只有这一raw构造和两个Self重建，Pipeline颜色/阴影两处同值finite重验退出；coverage、二值阈值、cast intent和真实draw失败发布不改。三产品净+3行，无新helper/持久状态/owner/cache/ABI/shader。

现有binding CPU class11方法75.636s通过；真实Builder/Catalog/Compiler分别用原/候选源码产出同166份作者文件的15producer，hostBuiltin/ authored、number/string10e299/array/value wrapper与真实改名覆盖。Native实际compileMaterialPlan/完整prepare→Frame→Metal分步取得45行及新增2producer×3灯6行，共17producer/51行；不是51一次性执行或所有handoff字节相同，三个authored巨值producer的9项派生binding state/reason/list按修复改变。原45中24行完整逐值同、21行改变，旧方法24subfail/0error、新同方法通过。builtin ±巨值变1/0、NaN回1；authored ±巨值从拒绝到实际颜色/depth/投影，authored NaN/巨RGB/巨brightness仍局部拒；其9行仍实际画receiver但无subject/map，不冒称有健康caster影。原45发布正观察为旧15/新36；首轮在arm清空后读取的同名字段只作无效观测保留，其余每一实际像素/depth字段与最终逐值相同。

补6行仅给原fixture typed near层供layerAlpha=.5，默认1及原45有效输入不变；复用原真实Producer二进制而未重编大源集，alpha1/2两树仅一个作者数值不同。三灯after的2×.5与1×.5业务字段严格同；定向旧2×.5为红255、receiver0/mapDepth.09925878，旧1×.5为[166,39,39]、receiver78/mapDepth1，新两者均后组且保实际near深度，point/spot各按自身控制同。这核到先归一再乘层alpha及原≤.5阴影cutoff，未授作者layer parser/属性回流。最终CPU同方法重评旧27subfail/0error、新全过，原45与补6分别绑定各自实际Harness/库/原始读回，不把两批说成单一载体。Native纹理transport受控，完整App补真实TEX/PNG消费；未作GPU normal/opacity uniform反读、全map等值或官方像素宣称。

完整App旧521/917三场46.581s：alpha1和巨alpha castfalse的独立健康caster影均5，仅巨alpha开启投影后健康caster色仍[0,200,0]、其receiver影变97，第一失败为该实际阴影ROI。新244a/f909四场60.282s通过，巨值及真实MDL/material/TEX改名与原/新alpha1控制的8份ready/after完整PNG逐字同7d9529d7…21fc65，健康影恢复5、彩表面/孔/自身影及蓝peer保持。castfalse只授独立caster色/影归因，不扩完整主体颜色对照。原22变体字节保持，控制/巨值仅材质alpha不同、巨值/noCast仅castflag不同；实际genericimage2/hostBuiltin descriptor吻合冻结材料。七场14捕获逐一同request/CB/main/seal/GPUcompleted、trunc0/排空，输入/App五件/产品源均稳定，测试进程无残留；时长不当性能对照。

两旧Spot/Point门的手工Float坏opacity不能代表新冷入口，已退该伪handoff与重复CPUproducer，保独立失败生命周期门：raw fixture退化UV使第二draw真实失败，map不发，首draw仍有65536/14337覆盖像素；pending/reset后pin1分别保4MiB/24MiB，GPU完成后resident0。两门54.287s通过且源码稳定，不宣该raw UV生产可达或拿它代opacity证明；初旧载体锚点已过时造成的零GPU异常与修正保于证据，未改产品失败处理。

最终Debug26.401s、三产品/project/锁文件构建前后同，strict-deep与原trusted helpers通过，exe244a827c…770f、dylibf909c0e4…4662、metallib仍9062517f…0864d。初共同finite表达式已收至legacy入口后重锁最终身份，早先成功构建/作者只作迭代，不授最终。独立原3453730450自然20s/after17运行36.596s，F784/request1/CB521233747456：53×1、77×4及306/340/342各1到main521241927808，同封口/GPUcompleted、trunc0/parse0并停机排空；原project/pkg当前=冻结matrix=运行副本。完整月面、亮暗半球、轨迹/星野、标题钟日可见，只授普通作者回归，不授作者巨alpha命中、内部opacity反读或同相位A/B。正式作者包归`.artifacts/scene-evidence/runs/scene-model-material-opacity-20261115`；其余实际输入/源码/原始读回及独审归`.artifacts/scene-model-material-opacity-20261115`。其它HDR缩窄、Float乘积/half域与属性/script巨seed边界仍在队列，不宣一般数值健康。

<a id="model-hdr-color-intermediates"></a>
### 模型 HDR 颜色的中间精度

按[唯一存储投影合同](advanced-object-coverage.md#model-hdr-color-intermediates)，颜色采样、PMA解码、surface/lighting、coverage、雾与最终PMA保Float，只在原RGBA16输出投Half；PMA只对正A除、零A清RGB，straight A0的opaque/mask颜色保留。退legacy重复Half运算与1e-5清零，Chroma无mask仍忽略global color，legacy不新增PBR radiance。shadow同源A用Float采样，原>.5阈值不变。产品仅原Metal净减18行，无新PSO、ABI、纹理、状态、owner或finite重验；不据采样类型变更声称三灯此前有精度故障。

同一冻结244行输入、RGBA32Float纹理→实际Pipeline/Metal→RGBA16Float/Float16读回，旧8.336s完成但新增8项像素红，新8.963s七方法全过，19新增均精确符合独立安全控制与字面存储值。高纹理经低tint由.249878→.5，高tint/brightness/mask由65504→257/512；小正PMA原0→1/16384、除法原65504→1.5，极小coverage原0→1，masked A0原0→.25。普通、straight A0、PMA A0及7个等值控制保持；late-view/fog旧已健康，只授回归。原225输入JSON逐字相同，156项完整RGBA不变、69项因退出Half中间舍入改变（如22480→22496），原六方法的业务断言和容差未放宽。极小coverage的最终Half alpha仍量化0，不宣任意多次合成、Float32代数或RGBA16范围已解。

Frame原192项加24项线性RGBA8 A127/128边界、三灯与资源改名，共216行的新旧原始结果逐字段相同；实际shadow map在略低/等于.5不写，略高与A1同深度，独立peer/camera不变。两份GPU结果以最终六方法CPU重评通过，未重GPU。最初below颜色被错误限定127，实际两版均128；有效A的纹理凸包及Half→U8存储只保证RGB整数[127,128]，现仅修此oracle，exact/above仍128、A1仍255，所有shadow/peer/camera严格预期保持。两次6条错误点值失败保留，不把测试资格纠正当作产品修复。共享shader另补原normal/reflection六方法36行，34.699s通过，方向/手性、alpha/depth、slot与环境反射原断言未改。

完整App沿真实genericimage2、MDL/TEX和同opacity1/1024，对照white255×tint514与texel1×tint131072，经原RGBA16存储后的片元PMA均257/512。旧244a/f909两场40.477s中控制主体225灰、high255白；新bbf6/f909/17c2三场62.222s中control/high及真实MDL/material/TEX改名的6份ready/after完整PNG，全部逐字等旧control的两图（SHA da8b8355…f5bc5f）。receiver97、蓝peer255及不投影控制不变；原26变体字节保持。10捕获逐一同request/CB/main/seal/GPUcompleted、零截断及排空，输入、App五件和产品源稳定；时长仅为功能验收，不授性能或活动作者HDR命中。

最终Debug12.051s、产品/project/锁文件前后同，strict-deep与原trusted helpers通过，exebbf6dfbb…55d9、dylibf909c0e4…4662、metallib17c2ed96…b3da。独立原3437487219自然5秒、23.629s运行，F126/request1/CB505517278080，模型112/114和图135到main505505897344，同封口/GPU完成、零截断并停机排空；原project/pkg等冻结matrix及report。实际地表、云层、蓝色大气弧、暗半球、银河与钟日完整，只授普通作者回归。必要作者原报告/图归`.artifacts/scene-evidence/runs/scene-model-hdr-surface-20261115`，自有输入、旧红/新绿、错误oracle及初MSL构造编译失败的零GPU日志、独审归`.artifacts/scene-model-hdr-surface-20261115`。剩余raw HDR缩窄及property/script seed仍归队列，不授官方像素或任意数值健康。

<a id="model-hdr-disabled-brightness"></a>
### HDR 关闭时的材质亮度需求

按[实际消费合同](advanced-object-coverage.md#model-hdr-disabled-brightness)，原Pipeline亮度finite许可只在usesHDRBrightness开启时生效；HDR关闭继续沿原编码取实际gain1，raw大值不进入uniform，不再使模型隐形而留影。产品只替换原guard一行、净增长0，无新字段、状态、helper、shader或资源owner；HDR开启的finite拒绝、非负投影与其它材质检查保持，authored Float接口的超域准入也未变。

完整App的同genericimage2、MDL、4² TEX和general.hdr=false两包，只将同材质brightness1改为有限Double1e300。旧bbf6/f909两场30.273s：三处原200红/绿/蓝主体变receiver97，model2实际failed，三处实体影仍5、孔与孔影97、peer蓝255；不是元数据或准备失败。新9690/244e三场51.012s通过，high及真实MDL/material/TEX改名、字符串"1e300"变体的6份ready/after完整PNG全部逐字等旧control两图（e38865c7…9daa0），原三色、孔洞与投影严格断言保持。两个原包与旧执行pkg/entries字节完全同，原29变体字节保持；10捕获逐一同request/CB/main/seal/GPUcompleted、零截断及停机排空，输入/App五件/源码稳定。此为真实冷Catalog→Material→draw边界，不授作者活动巨brightness命中或全部数值域。

最近Pipeline门复用原emission GPU载体，只加opt-in实际Bool/2像素peer/depth传输，不新建renderer或suite。旧/新同7行分别.554/.387s完成；旧仅HDRoff大值一条像素子断言红、无执行错误，新方法全过。off1/off1e300同RGBA[.25,.5,.75,1]、depth.5与实际draw=true；HDRon正常1/2确实增益，on±inf/NaN仍draw=false、颜色/depth清0，全部健康peer同蓝[0,0,1,1]/depth.5。仅替换冻结before Pipeline单源，原其它六行逐值保持；直构Float坏值只授draw边界，冷可达由前述实际App证明。原244输入序列化不变、默认输出仍name/pixel/completed，这只是载体/输入核对，未重复执行244或冒称本批新资格。

普通Debug33.898s、产品/project/锁文件前后同，strict-deep与原trusted helpers通过，exe96900e78…a1d3、dylib244ec71c…6f3a，metallib仍17c2ed96…b3da。独立原3437487219自然5秒、21.522s运行，F136/request1/CB527121220480，112/114模型及135图到main527137987456，同封口/GPUcompleted、trunc0/parse0并停机排空；原project/pkg等冻结matrix及report。实际地表、云、大气蓝弧、暗半球、银河星点、时钟日期完整，仅授普通作者回归，不授同相位、官方像素或性能。作者原报告/图归`.artifacts/scene-evidence/runs/scene-model-unused-brightness-20261115`；自有原输入/红绿、严格边界、身份及独审归`.artifacts/scene-model-unused-brightness-20261115`。

<a id="model-effect-role"></a>
### 模型上游 effect 的明确准备角色

按[原资源角色合同](advanced-object-coverage.md#model-effect-role)，SourceFacts只给原Catalog传objects.effectFiles路径，cold queue用两位值类型角色替换material Bool；同身份累计选择，待处理原位汇合，已处理只追加新角色差额。路径hint仅在处理时仍无明确角色才选择并记账，不给已知consumer多加无用schema。原parser、来源/排序、取消/revision保持，普通dependencies仍hint，未引用JSON不读；退effect文件名许可，无新扫描、资源/输出owner、持久状态或缓存。最终两产品净+17行，只供冷准备，不授普通帧成本或性能收益。

原named-late真MDL caster2依赖隐藏image provider11，slot0为_rt_imageLayerComposite_11_a；直接挂现有own_dim，仅RGB乘.5。两包同时保标准/非标准effect别名，body及其余entry同，只scene中一处file引用不同。旧9690/244e两场9.495/9.086s：标准有Program、模型G45；非标准0 material/0 graph Program，raw capture和model binding仍成功、模型G90，明确是原图fallback替代效果；影5/receiver81同。标准首场原载体误求raw capture，保失败，仅用实际graph发布/绑定/像素CPU重评、零重跑。首实现Catalog93d0/SourceFactsd770、App601b/2117的三场47.659s，通过标准/非标准和真实MDL/provider/材质/PNG/effect/shader路径、varying/局部变量及(c+c)*.25变体；6份ready/after完整PNG和解码RGBA精确等旧标准4face8…d41ac。原32变体字节同，前两包project/scene/pkg/entries精确复用；此三场只授首实现身份。

后续发现首实现把kind hint并入明确角色：materials目录的effect多跑Material parser、effect.json命名的material多跑Effect parser。最终813272e0将hint推迟到无明确角色的处理入口，沿原queue记已选择位，无新字段。保首实现三场，最终只补新materials/selected-effect.json的一场16.785s；App20f692d3/aaaf0937的两份完整PNG及RGBA仍精确等旧标准，G45/影5/receiver81和Program→named-publication-only→model/main/seal/GPU门通过。原35变体字节不变，未重跑三场。两旧/三首实现/一最终共12捕获各自同request/CB/frame的model→main/seal/GPUcompleted、trunc0及停机排空，source/App/输入稳定。中间named copy完整token未暴露，初binding日志无frame，不声称tail和model source直接同纹理或逐帧绑定反读；只授自有一跳albedo，不授mask或作者非标准路径命中。

原Catalog CPU门旧15方法12.618s有9个行为subfail/0error，首实现15方法11.872s全过；原12方法、30输出字段与113份自有fixture文件保持。两版generic引用/explicit数组当时同，旧Harness只机械省未知effectPaths API label，原产品不改，不以编译失败冒旧红。hint修订增两文件；中间93d0在两新冲突各read2/两parser各1，11.510s取得2条成本红。最终class已有13方法通过，另2失败来自把dual-pending的hint误当真实effect需求；保该raw，只给此正例补明确effect请求，generic引用与115文件字节不动，10.839s补两受影响方法通过，分步有效15方法，不重跑其余13。两冲突最终各read1/正确parser1/相反parser0，无错误catalog条目；两真实role则各parser1、readBytes2，无旧角色重放。初最终class原30字段严格同；补验其余29同，missingValue.rawValue只有Swift字典诊断次序变化，不称所有packet逐字相同。局部坏/缺effect、健康peer、only-hint .other/未引用零读、取消上抛/零新增读及原高优先根alpha.625保持。此门不授SourceFacts/GPU接线，后者归实际App。

首实现Debug25.308s、独立原3557068717自然20s/after17执行41.736s，均保93d0/601b身份。F547/request1/CB513463601792的166/186/156/237/270/204/99/182模型到main513425706112，424/420实际material及named发布、420 slot1读424可核；封口/GPUcompleted、trunc0/parse0并排空。原project/pkg等matrix/report，实际完整地球、云层、亮暗半球、城市光、星点和时钟可见。报告归.artifacts/scene-evidence/runs/scene-model-effect-role-20261115，不冒最终源码或直接named copy同一。

最终Debug26.275s、两产品/project/锁文件前后同，strict-deep与原trusted helpers通过，exe20f692d3…6e03、dylibaaaf0937…8f6f、metallib仍17c2ed96…b3da。最终独立原3437487219自然5s、17.863s执行，F147/request1/CB512306332544，112/114模型及135图到main512254321408，同封口/GPUcompleted、trunc0/parse0并停机排空；原project/pkg等matrix/report。实际地表、云、大气蓝边、暗半球、银河星点和钟日完整，报告归.artifacts/scene-evidence/runs/scene-model-effect-role-final-20261115。两作者均只授原包播放，不授活动非标准effect、同相位A/B、逐part贡献、官方像素或性能。自有输入、旧红/载体误报、分步绿、身份及独审归.artifacts/scene-model-effect-role-20261115。

<a id="image-model-role"></a>
### 模型 albedo provider 的 JSON 模型角色

按[明确image模型合同](advanced-object-coverage.md#image-model-role)，SourceFacts只传原objects.imagePath数组；Catalog原角色集增加imageModel位，model/material/effect共用hint选择、canonical已选择位和差额队列，旧独立kind.model解析分支退出。模型成功沿原material闭包与model→material链接供TextureResolver，局部失败只更新原failedModels/pendingSources，不跳过其它schema；成功kind!=model名字补原候选数组，未加新索引/cache。两产品净+5行，无新状态、renderer、MDL解码或普通帧解析；不授全部Script-only/热换或kind.model非.json候选名域。

旧20f/aaaf App同named-late/provider11/caster2及标准own_dim；两包都放models/provider.json与providers/provider.json同body别名，只改provider11.image。两场30.103s：标准有G45模型/影5/receiver81；目录外effect仍admitted-generic，但无model→material链接/texture URL，layer-source-not-ready、named capture/binding失败，所选帧无model2 draw，颜色与影均露81。不是effect丢定义或raw fallback。新71e9/617b三场47.547s通过，目录外及真实MDL/provider/材质/PNG/shader、变量与等价式改名变体，均保标准effect路径；6份ready/after整PNG及解码RGBA精确等旧标准4face8…d41ac，恢复G45/影5，receiver81不变。原36变体字节同，前两新包project/scene/pkg/全部entries精确等旧执行；原delta3与同Program→named-publication/model→main/seal/GPUcompleted、trunc0/停机排空要求保持，共10捕获。中间named copy token观察上限仍在，不声称直接同纹理或逐帧绑定反读；只授自有一跳供货，非作者目录外缺图命中。

Catalog真实CPU门旧17方法11.424s有8个新增subfail/0error，新17方法10.789s全过；原15方法AST/语义及两版结果保持，原46输出字段严格同。124份自有fixture逐SHA同，归档原115文件不变、只增9份。两版generic引用/explicit数组相同；旧Harness只机械省未知imageModelPaths label，不改产品、不以编译失败冒红。目录外Unicode后缀/无后缀/大小写、material/effect hint冲突均model parser1/相反parser0/read1；pending/processed真实双consumer各model/material1、read2，缺失/other0、坏模型尝试/读1且健康peer保持。临时transport只记录原DynamicReferenceAnalysis真实return，实际包含已显式解析的providers/scene Ω.payload和processed名，不复制算法；不据此授Script-only全部模板或MDL。

普通Debug28.519s、两产品/project/锁文件前后同，strict-deep及原trusted helpers通过，exe71e933b5…7dd8、dylib617bbef4…5198、metallib仍17c2ed96…b3da。独立原3477054430自然5s、12.345s执行，原project/pkg等matrix/report；F187/request1/CB533847163776，14×2、23×1、47×2、68×1到main533850286080，同封口/GPUcompleted、trunc0/parse0并停机排空。实际月球、星点、楼体、猫及耳机完整，只授普通原包播放，不授同相位A/B、逐part贡献、官方像素或性能。作者原报告/图归.artifacts/scene-evidence/runs/scene-model-image-role-20261115；自有输入、旧红/新绿、身份与独审归.artifacts/scene-model-image-role-20261115。

<a id="tube-light"></a>
## 管状灯的模型受光

2026-11-16补通`ltube`的Format→原Layer→同帧LightSnapshot→stock generic4/chroma4 SurfaceResponse。按[线段合同](advanced-object-coverage.md#tube-light)使用局部CP与完整world，CPU每灯准备单位轴/长度，片元取有限最近点及原径向项；退原类型丢失，不伪装Point、不增pass/纹理/PSO/缓存或输出owner。15产品文件净增164行（含42行typed定义），原Pipeline972行；GPU尾增224B至1728B，旧字段偏移不变。原General/可见性与共享四灯预算接纳Tube，legacy authored point ABI不被Tube失效；阴影、体积、旧材质和Generic/image仍不在此资格。

真实3617056047的默认罐体70使用stock generic4与原MDL/TEX，静态白管灯86的I6.6/r1033.98/e2.65未进入旧消费者。固定原资产/相机和70/107姿态，清空ambient/sky及其它灯，只改86强度0/6.6；旧off/on终端PNG完全相同，原点灯83正控能照亮罐体。当前同三输入全PASS，1280×831中点灯正控与关灯画面分别逐RGB与旧图相同；Tube-on改变20158像素、最大通道差85，差异界[586,344,759,563]位于可见罐体下侧。该控制隔离直接贡献，不授原包全景严格A/B或官方曝光一致。

真实Builder/World/Snapshot与用户属性门93项全true，包含局部坏CP/强度/radius不带走健康Point、General缺省/关/非零、资源及ID改名、父TRS与当前typed值、共享四灯顺序和legacy ABI邻例。模型GPU六方法/37输入通过零长点极限、两端整图Point等值、内点线长不变及离轴光差、零指数半径外、零强度/无灯/unlit、normal/MR/Chroma/rim/pigment、alpha/深度和改名；四份I1与单份I4整图等值，实际遍历四Tube槽。相同Swift probe与payload仅换共目录旧Metal，37输入新执行中Point各行RGBA/depth全等，Tube黑；直接CPU调用原断言得五红、一零能量邻例绿，证明门能检出缺消费者。脚本VM/父隐藏与live property两方法另在四类灯实际执行通过，Tube显隐计数0/1/0/0/1，父隐藏撤光、property显隐0/1/0且launch/color/I需求保持；11方法合计通过。最初两夹具未编译的失败保留，修支持DTO/显式数组表达式后只补受影响门。

Debug增量33.905秒、产品输入不漂移，实际App strict/deep签名通过；exe `3203f653…5f822`、dylib `65c79a02…ec523`、Metal `bfb78133…e89aa`，两编译工具仍为既有签名身份。原361与未参与修复的3437487219均取得完整终端、model/main/seal/GPU与排空且整轮PASS，实际罐体与独立星球纹理/完整图已观察。一次错误的TestSuite断言重放触发多余current setup，覆盖了内存rows，错误绿收据已作废并保留；正确旧断言直接读取原old GPU结果。该重复执行与作者代表运行重叠，作者运行仅授画面/播放，不授时耗性能比较；不重跑无变化产品来制造新结论。

独立设计/产品/测试审查未见阻断。官方VM恢复后，完整运输并核对6输入文件，但仅point正控装载即触发官方0xc0000005错误框，尚无有效罐体像素，未试Tube off/on；已请求恢复客户端，性能设置未改。保留的Point计数与删灯后数量不符、PKGV头版本差异只是未决输入风险，不定崩溃因果；原平移计划的相机通道无效，未生成变体。CP坐标域与官方数值受光仍未知，本批按明确自有几何算法交付。必要原图、原报告与source/readback/审查保在`.artifacts/scene-model-tube-light-20261116/`及同名formal run，构建沿原单一DerivedData复用。
