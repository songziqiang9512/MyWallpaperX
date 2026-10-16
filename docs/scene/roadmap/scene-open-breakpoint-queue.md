<!-- document-role: active-plan -->

# Scene 当前断点修复队列

> 更新：2026-10-16。本文只排当前开放问题，顺序为**画面正确合成/正常播放 → 有证性能成本 → 属性热更新接线 → 其他合同与验证债**；专项选序服从[兼容路线](scene-compatibility-roadmap.md)。已修首断点退出，具体视觉余项单独保留；完整golden、全部交互或更多profile尚未验，不自动构成新缺陷。

当前状态以源码与同身份执行证据为准。**运行已复现**、**静态反例**、**能力缺口**和**待当前复验**分开；旧日志、声明数量、默认隐藏/属性关闭、首帧暂未ready不直接算当前可见失败。根因unknown保留unknown，不能据同类样本、图层名或截图补算法。

样本/人工历史归[验收台账](../capabilities/scene-sample-acceptance-ledger.md)及[统计](../capabilities/scene-corpus-capability-inventory.md)；新增N组的原始身份见[10-11普查](../history/new-scene-intake-2026-10-11.md)，当前执行见[运行证据](../capabilities/runtime-evidence-current.md)。243成员快照、10-11 intake的279份与旧混合App归档不是同一分母。未关联当前运行者保留not-run，不靠重整队列刷新人工verdict。

## 1. 画面合成与正常播放：可定位的开放项

| 项目 | 当前证据与边界 | 最小下一门 / 停止条件 |
|---|---|---|
| N08 · world / 负subdivision RopeTrail | **现profile仍拒绝，行为unknown。** 3337494481十个visible复制层unavailable；原十个hidden不计故障。固定官方自有20图只证明-16可见及曲线有输出，未判负值规则或world朝向 | 已停止无区分矩阵；重启须有能裁定空间或细分合同的正控，不猜abs/clamp、不直接放开guard。static child Rope的修复不关闭本项。[资格与停止边界](../history/rope-trail-profile-qualification-2026-10-15.md) |
| U40 · 3749463715重复Puppet拖动失效 | **10-16 fresh受控三轮仍未闭合。** 首轮598可见骨写，释放后TypeError，后两轮callback停；562正常。同包静态跟进定位CursorUp延时链首个缺失host方法为`applyBonePhysicsImpulse`，实际形态为Number+Vec3两参；不是getAnimation缺失，尚无动态PC因果证明 | 官方载体2/2资格失败，angular缺省/空间/响应仍unknown；先取得可见骨姿态正控与数值合同，禁止no-op、猜default或削fuse。修后同输入三轮持续响应、释放后继续更新及健康邻居。[原动态证据](../history/repeated-puppet-drag-qualification-2026-10-16.md)；静态资格：`.artifacts/tmp/repeated-drag-consumer-qualification-20261016/qualification.json` |
| N03 · 3337494481特殊composition | **10-16原包fresh。** 70/202/228/229/591均为native-world `composelayer_depthtest.json`，visible却无source，前有18个写深度模型；旧“1条未恢复”实为一条含五层的诊断。147属性类型首错及永久删除callback后误拒合法编辑均已退出，不再列作待修。Rope只归N08 | native采集正控资格STOP，后继门归[D1](batch2/composition-render-target-design.md)，不放普通composition别名、不忽略深度或绕main-source准入。229首effect另有局部Program fallback，不随source缺口关闭；[已闭编辑边界](../history/property-callback-recovery-2026-10-14.md#retired-property-callback-consumers)。 |
| 普通unlit数值下溢 | **10-08自有GPU旧反例，未fresh复验、真实样本影响未证。** weighted输入source alpha=.5、vertex=.25、R8 clip=128/255仍把应约2.5098的RGB算成0；既有fast-math下溢未由溢出修复关闭 | 沿唯一颜色乘积/片元owner保有限结果及alpha，不全图压暗、加cap或换混合。先取得真实活跃消费者，分开数学反例与用户画面收益。[现有证据](../capabilities/runtime-evidence-current.md#e-2026-10-08-unlit-product) |

<a id="qv-visual-repairs"></a>
<a id="qf-2026-10-07-用户点名四样本公共主链修复"></a>

3610154602于10-16同身份复验并读源资格后，不再按“缺getTextureAnimation API”排实现：435.alpha/origin首错依赖当前缺席的播放器控件，423只存在一层parent却读取祖父；公开missing lookup/null及无父undefined合同已执行。其余动态创建/导入是否应提供缺席控件仍unknown，不记作者错误或样本完成；取得合法producer证据后再开共享首断点。人物、城市、时钟与橙色频谱实际呈现，非完整parity。限期证据：`.artifacts/scene-evidence/runs/texture-animation-owner-qualification-20261016/`。

3078285611的effect6/22/24 speed于10-16同身份读源资格后退出“缺API”修法：三者对整个scriptProperties容器做算术，健康effect5读取其中Number成员；现无原型容器不能primitive coercion，解释原toPrimitive首错。没有公开whole-container转Number特殊合同，改变原型或替换slider也未证明能产生合法速度；不认定作者错误、官方结果或样本已修。后继须取得能改变此类型判断的公共行为证据再开共享缺口，不重复numeric门。中性收据`.artifacts/tmp/307-speed-consumer-research-20261016/qualification.json`（SHA `ab21f208267dfc4ed8719cf87c338210c26e64196d1b657d4e0175e0cb158939`）。

## 2. 具体视觉差异：保留观察，待当前身份复验

下表保存尚无关闭证据的具体差异，不表示当前HEAD均有缺陷。QV旧观察仅能追至原队列所链09-26—10-08证据；未注明更新日期者缺最新App、phase/属性/音源身份。先用当前链路复验；若不再出现或确认作者设计/关闭则退出，不为“完整parity未验”继续造任务。

| 样本 / 旧观察 | 当前边界与下一关闭门 |
|---|---|
| 2887542690 · 音频ROI、黑遮挡/字体与片区布局 | 10-16 composition创建、286控制及限定透视回绘已接通，原visible-of-null退出；只证旧外悬蓝条同位置消失。固定pointer显隐消融未找到音频条的可重复正证，资格STOP，不能称图框内音频恢复；其他旧具体视觉与完整交互仍待当前可区分证据。[本批边界](../history/composition-local-perspective-2026-10-16.md) |
| 2134765860 · 右侧旧黑块 | 10-16默认日景及作者Night(Lights On) String选项4实图未定位独立右黑矩形；亮吊灯、书柜和地板可见，灰白海报与软阴影仍在。旧精确ROI、媒体和墙钟/viewport phase未齐，不写已修；移出当前已确认缺陷，先取同状态可区分复现再追source/effect/compositor，不据两条无归属mask诊断实施。[夜景限期证据](../../../.artifacts/scene-evidence/runs/213-black-region-night-qualification-20261016/manifest.json)；标题修复不重开。 |
| 3768903841 · 云形/烟花细节 | 旧Worley云形及烟花/色彩细节未取得同相位关闭。10-16 R40独立原包复验四束spot GPU成功、底部光束可见，实图仍有横向深色云片；只证明当前呈现，不据此判新根因或整样本通过。先同phase对齐实际source/Program与ROI，不因四束恢复关闭旧云形差异。[原边界](../history/runtime-evidence-index.md#e-spot-light) |
| 3226487183 · 游离手臂、侧脸碎片 | 旧图的1028/934/876错位未闭。10-16中性资格只证无parent/attachment、center且origin含script，非center pivot静态反例不命中；seed不能当实际VM输出。沿实际origin→pose/bone→skinning对齐，并保composition成员效果。[闭包证据](../history/composition-member-closure-2026-10-07.md) |
| 3809618616 · 布局/显示比例裁切、音频活动 | 旧柱/照片缺失已修；此处只保旧布局/裁切及音频活动复验，不再重开int compound/TEX照片入口。先确认仍有具体差异及当前状态。[最后整合身份](../history/committed-range-review-repairs-2026-10-07.md#整合验证) |
| 3791967416 · 眼部完整周期、局部图案/合成 | 最终eye105闭眼无虹膜已有有界证据；旧局部图案/整体合成差异未取得同phase关闭。复验完整周期和对应ROI，不重修已闭barcode/seek/bone alpha。[边界](../history/puppet-clipping-2026-10-08.md#跨样本app与最终冻结) |
| 3789316755 /3211615441 · 频谱形状/幅度/全柱活跃度 | 旧容量与连续PCM首门已修；需要同声源App A/B与静音/噪声反例，不能用峰值策略充当官方算法。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-28-audio-band-peaks) |
| 3211615441 · 首焦点点击、按住外观/多步跟随与位置 | 事件和三点跟随已执行，旧完整交互未闭；按住需跨帧，不能以同帧down/up验收。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-28-effect-cursor-visibility) |
| 3788467391 · 漩涡方向/速度/形态与长预热 | 旧Rope纹理跨度修复保留；300秒预热被预算截断、原版轨迹仍待相位对照，不能旋转整背景补偿。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-28-rope-trail-texture) |
| 1315486372 · 顶部光线、中部渐隐、水波位置 | 旧载体/根旋转修复不关闭范围、根部、位置和节奏；先同phase定位source/geometry/合成，绝对sprite size须独立标尺 |
| 3769761761 · 缺左上向右下斜光 | 旧局部变换、默认trail及alpha、1/2/4倍size尝试均未恢复目标；粒子或shader来源仍unknown。先同viewport/phase分离实际来源，禁改作者参数。[最后诊断](../capabilities/runtime-evidence-current.md#e-2026-09-28-ray-source-diagnosis) |
| 3768724269 · 光束过大、根部深入/脱层 | 旧coverage/载体/视差输入首错已修，具体范围/根部差异未闭；固定camera开关、depth与phase核MVP，不硬绑背景。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-27-parallax-shader-input) |
| 3287715210 · 眼周过亮/渐变弱、横移细竖条纹 | 两个独立余项。10-08原包与gradient-only完成GPU，16F量化存在但未证是条纹根因；后继官方2.8.0.42自有phase4输入已取得8位PNG、52色/最长63列平台，只能证明终端量化，不能推出内部F16或328根因。物理呈现及整样本仍待同状态复验，不额外压暗、不重复优先消融Bloom。[颜色/精度证据](../capabilities/runtime-evidence-current.md#e-2026-10-08-gradient-storage-isolation) |
| 3750813609 /3363252053 · 相机过强/纵向反转 | 用户三轮仍未接受且要求挂起；仅有官方同输入或用户重启时恢复。默认2D camera后继不替这两个原报告作体验验收 |
| 3662790108 JUNO · Data脚本异常 | 10-13开场/持续更新的heap首门已修；10-14 layer517读取undefined的p1_longNode TypeError仍待当前复验。10-16冷运行未ready，不会执行证明该异常消失。[最后CPU资格](../history/script-c-codegen-ablation-2026-10-14.md)、[heap边界](../history/scenescript-host-heap-admission-2026-10-13.md) |
| 3589454154 土星 · Bloom、亚像素细线/微颗粒、轮廓/布局 | 用户调序暂缓；已修模型/光照不关闭这些旧具体差异。保持合法屏外投影，不用视锥剔除消影。[原光照证据](../history/saturn-light-delivery-2026-10-07.md) |
| 3747492842 · 闪烁、光束位置、viewport裁切/文字构图 | 旧正交near-plane首错不重修；固定当前输入/phase比较首个不同stage，再判原因 |
| N07 · 3248220186运动/密度/亮度 | 世界Sprite准入/相机与GodRays首门已修；这里只保10-11旧运行所留的具体运动/密度/亮度差异，待同phase/音源当前复验，不再列“world Sprite不支持”。[运行边界](../history/particle-world-depth-2026-10-11.md) |
| N03 · solid亮度差异 | 原队列有比较观察，但缺本项当前target/状态身份；先补精确消费者和同状态对照，再判是否为颜色域/材质合同问题，不能全局删brightness |
| 2938612768 · 右下时钟裁切 | 10-14固定13基线/候选的两张后期图均在，23层执行集合相同。根因未定；先当前布局/输出ROI复验，不改矩阵期待掩盖。[同输入证据](../history/frame-texture-snapshot-convergence-2026-10-14.md) |
| 2775915974 · 顶部灰边 | 来自09-06/08旧人工观察，缺当前身份；方向/顶部事件已修不证明该边界消失，先复验其是否是作者画布露底 |
| 3437487219 · collision行为 | 旧人工裁决的collision未取得后继关闭证据；先复验实际碰撞输入/owner，日期/时间恢复不代替本项。不能仅因旧fail写当前碰撞缺陷 |
| 3448845950 · 脚本效果/布局 | 09-06/08旧人工记录未取得当前关闭链，精确target/可见状态待补。第4节font仅是新合同候选，不把旧TypeError归给它，也不按旧黑屏重开资源链 |
| 3712499998 · 重复文字/样式 | 来自旧人工观察，Vec构造首门与频谱已修；若当前仍重复，定位实际String/图层组合，不再补WEVector API |

<a id="qv-cccea6c-user-report"></a>

### U组：2026-10-08用户报告的具体余项

原观看身份为cccea6c1a8a738fd97889fda53e8c9cb0603908d，缺App二进制、属性、声源和时间；下表未注明新证据者均**待当前复验**，不是当前HEAD缺陷结论。已闭主现象的U行退出；U40归第1节，U22/U24提交率归性能段，U42归属性段。同一余项只保一处。

| 编号 / 样本 | 仍开放的具体观察 / 下一关闭门 |
|---|---|
| U01 · 3764725758 | ①左侧向右下光束缺失；②人物眼睛错误飘动。分别定位实际来源/激活/合成与pose/挂点，不先假定同因 |
| U02 · 3549827466、3585542943、3581882134、3603711180 | 四样本光束缺失，各取实际particle/shader occurrence、准入、geometry/coverage与最终ROI；不能合并为一个未证算法 |
| U05 · 3723344874 | 人物背后流体烟雾缺失；沿实际作者定义→资源/Program或粒子→层序/合成复验 |
| U08 · 3802005866 | 音频条/蓝背景疑似越出限定矩形；先确认作者限定区域，再核变换/clip/extent |
| U09 · 3797217144 | 旋转并由小放大的出场缺失；核intro/Timeline/脚本启动与完整入场时序 |
| U10 · 3793998447 | 音频光圈和部分属性疑似缺失；先列具体active属性与typed消费者，不能从面板有声明推全部失效 |
| U11 · 3792249095 | 音频发光缺失、整体样式差异；先同声源定位驱动→effect/颜色/合成与具体构图ROI |
| U13 · 3042492564 | 原报告光束形状、封面右裁切/blur、布局及媒体交互尚待新基线复验。10-16已恢复默认camera倍率、星芒/海平线/塔底，1128非有限origin首错也已修；这些不关闭余项，也不把544作者ReferenceError:event列host缺口。[camera边界](../history/default-2d-camera-inputs-2026-10-16.md)、[Vec证据](../history/vec3-mixed-dimension-arithmetic-2026-10-16.md) |
| U14 · 2932157836 | 封面缺失、时钟及named-user旋转首门均已闭。保留10-13新观察272 cursor/timer取消owner异常待当前复验，及旧blur/精确spin样式、真实来源仲裁的具体差异；不以299旋转恢复关闭整景。[named-user证据](../history/named-user-pass-scalar-2026-10-16.md) |
| U15 · 3299228616 | ①hover水波弱；②时钟上方矩形独立运动。分别核pointer输入与graph/变换/相机/合成空间，不抬gain掩盖 |
| U17 · 3233141951 | ①脸部不随头发动画；②龙头轨迹不对；③黑色小人动画缺失；④音频双色重叠现只粉色。pose/attachment、时序/激活与audio混合分别复验 |
| U19 · 3807668787 | 主报告灰头冠/音频缺失已修；仅保10-11实测可见pointer轨迹958因alphatocoverage拒绝。现粒子blend/profile须取得同条件合同，不能猜替代混合。[最后证据](../history/independent-signal-producer-2026-10-11.md) |
| U24 · 3420215721 | freeze/封面依赖首门已闭；中央环官方亮度具体差异待当前复验。349/409 circular_text默认hidden且无激活证据，不计缺字，不改作者alpha补偿。[关闭首门及边界](../history/terminal-attachment-desktop-freeze-2026-10-10.md#u24-cover-dependency) |
| U25 · 3351163962 | 时间文字跑出左上音频环；核text anchor、布局与共同parent空间。自有camera-anchor官方ZERO资格失败，没有可用于改投影的合同 |
| U26 · 2849382252 | 三条白色图形分辨率过低；核原资产、采样/target extent与几何，不先判压缩或任意加分辨率 |
| U27 · 3754630802 | 狮子头眨眼异常；先固定clip/纹理序列与周期、关键帧再定位 |
| U28 · 2684431262 | 与官方显示差异大；现描述不足以定算法，先取得当前构图/逐层首个不同ROI |
| U29 · 3470948192 | 旧30秒越过intro仍黑水滴/缺发光，另旧人工记录有NaN、文字碎片、异常背景。未由模型emission首门关闭，均待当前真实输出/异常target复验 |
| U30 · 3750813609 | 旧观察①闪电缺失；②时钟颜色/发光不符；③雨弱，均待同phase复验。10-16原包身份复核：雷电为121→lightning2，普通Sphere/rate1，无periodic cap；旧405/412+cap32关联错误已删，它们属3749463715，能力缺口只归[静态审计](scene-full-sample-static-audit.md)。未找到121 root静态准入拒绝，不推断其视觉原因。 |
| U31 · 3264246690 | ①人物边缘锯齿；②点击换口罩缺失；③警戒带运动错误。解码/采样、hit/事件、时序分别复验；mesh/atlas首门已修不关闭本项 |
| U32 · 2131872317 | 烟花种类/效果不足、爆开乱飘；先核root/child准入、力/速度/空间/随机序列，固定dt/seed可区分轨迹 |
| U33 · 3769688830 | 玩偶应左右循环转而现单向转；核rotation/oscillation/Timeline的相位和方向，不专设摆动算法 |
| U35 · 2974757317 | 卡片下多出独立矩形频谱；先证作者是否本有该层，再核named/previous、层序/变换/clip，不直接隐藏 |
| U36 · 3780119725 | 中层固定而整景应随鼠标视差；另旧人工记录有脸部黑线/缺块、动画、光照/闪烁差异。沿camera/depth/parent→MVP与effect输入复验；默认camera后继不能代替该包当前验收 |
| U37 · 3769364482 | 发光突现，缺渐显渐隐呼吸；核opacity/Timeline/effect→typed→合成完整周期 |
| U38 · 3750342273 | 缺pointer镜头视差；复验输入、相机配置与各层变换，不全图后移补偿 |
| U39 · 3219398263 | 漩涡方向疑似相反；固定时间/角度/UV/空间后裁决，不凭单帧改符号 |

用户暂缓的低优先旧观察（3028090166光束、2419444134白点、3113554287顿挫、2304304373雾气及一般烟花/洋红/拖尾）仍保原人工证据；仅用户重启或共享修复实际触及时复验，不维持为无条件当前缺陷。3088601835雪雾用户已认为较正常、官方也过曝，不再作为待修现象。

## 3. 性能：先取得当前可避免工作的证据

专项阈值、有效基线与NO-GO/STOP只由[性能卡](performance-convergence-card.md)维护；本页不另建优化campaign。以下不是永久启动失败、泄漏或整引擎掉帧结论。

| 项目 | 最后信号 / 下一门 |
|---|---|
| N09 · 重型冷启动/准备 | 10-11的3476868923、3507496797首轮69秒超时，延时后153.425/93.820秒ready；10-16原3662790108冷120秒仍shader准备、无画面。prepare-catalog70.338s包含model-build43.313s，不相加。先定位当前唯一大成本与可省工作；不能再以延timeout、重开MDL/cache/排序或降低内容当优化。[最新归因与撤回](../history/shader-value-type-recognition-2026-10-16.md) |
| U22 · 视频越播越卡 | 10-08用户报告保留待当前普通App长稳复验；该包65/100秒双视频未见递减，只排除该短窗口。点击切背景首门已闭，不借此关闭长时成本，也不继续声称所有视频普遍递减。[有界运行](../history/named-timeline-interaction-2026-10-10.md) |
| U24 · 未提交/提交率 | 10-10实际音频60秒931帧不再freeze，但旧1879未提交/提交率需当前有效分母与drop原因；不是已证当前预算不足。中央环亮度归U24视觉项 |
| 轻重切换后驻留上移 | 已缩到purgeable分配，实际持有owner未定；先补有效分配来源与退出平台，不重复无caller整轮切换，不把allocator驻留当泄漏。[当前证据](../history/scene-switch-residency-qualification-2026-10-15.md) |

旧323 ready后超时、322冷shader变慢与累计tombstone扫描，只在取得当前有效运行/可避免工作后进入上述启动或稳态项；旧FPS及源码复杂度不是新性能缺陷。已撤回的声明准备等方向不因队列整理重启。

## 4. 属性热更新与编辑重建

具体能力边界与选题只归[属性卡](properties-panel-card.md)、[输入覆盖](../capabilities/runtime-input-property-coverage.md)。已闭视频入口、普通图片brightness、named pass scalar和Sound mixed paused refresh不再列本页待修；其未验的全codec/所有组合不改称当前故障。

| 项目 | 当前边界 / 最小下一门 |
|---|---|
| U42 · 面板打开/编辑、长Combo与显示语言余项 | 原生列表/AX滚动及有限本地化已有有界验收；旧“浏览严重卡顿/中文都变英文”不能无条件沿用。打开/编辑总延迟、完整系统键盘chrome、长Combo完整显示及更多locale仍待当前实际资格；未审词汇不直接算错译。先单个可达控件和用户动作/成本，沿原Intent→store→consumer验证 |
| font String公共合同候选 · 3448845950 | 实际默认font consumer是否被String拒绝尚未证；102隐藏且存在registerAsset生产者，不能用38次词法写归因旧TypeError。精确资格、下一门与停止条件只归[静态缺口表](scene-full-sample-static-audit.md)，不直接开放任意路径。 |

显隐slider/缺定义、条件-only Combo、maxwidth script等旧声明/候选不等于缺热更新：先有同身份instruction/callback/rebuild及可见consumer资格。314 fireplacesound属Sound mixed，已修；304 clock_lang已有真实text模块applyUserProperties consumer，亦非condition-only；不另造condition evaluator或value-only旁路。

## 5. 其他有具体依据的合同/验证债

| 项目 | 证据边界与下一门 |
|---|---|
| Timeline event-only attachment归属 | **静态反例，无真实受影响target资格。** Vec2/Vec3或numeric String可能尚未获VM control owner，却被classifier仅凭event-only吞attachment；10-16三包只见已支持Number control，资格已停。后继必须先证target及proven control owner，再复用原Timeline值源；不扩API或继续宽搜。[当前API边界](../capabilities/scenescript-api-coverage.md) |
| 普通桌面captureFrame返回1×1 | 10-15的3766415113 daemon已呈现而ScreenCaptureKit仅1×1 JPEG，同输入Metal诊断可完整；待当前窗口frame/捕获时机复验，不把诊断替代图当普通capture已修。[原尝试](../history/shader-completed-cache-retention-2026-10-15.md#未完成边界与无效尝试) |
| 粒子剩余真实unsupported profile | static depth-one child Rope的scale/预算首门已闭，原3665307769取得909/303 child段；不再保getsuga Z=2缺口。mapsequencebetweencontrolpoints、控制点约束、nested/event或非均匀child变换、深层duration/9999 delay仍按精确active child资格推进；不能拿root可见当child执行。[唯一profile合同](../capabilities/particle-component-coverage.md)、[已闭首门](../history/static-child-rope-2026-10-16.md) |
| 光照数值合同余项 | point剖面差异、spot父级缩放及更广2D ambient/spot/directional的精确响应未取得完整公开控制；先分consumer、固定法线/位置/父变换的官方自有正控。已闭灯数/零点、shadow朝向和模型表面响应不重修；R40逐动画播放已闭，见[共享角度合同](../capabilities/advanced-object-coverage.md#standalone-spot-playback)。[光照范围](../history/2d-lit-image-light-contract-2026-10-06.md)、[模型合同](../history/static-model-light-input-semantics-2026-10-06.md) |
| RF05及真实跨层/跨屏、异步故障组合验收 | 原property→dependency/provider闭包→Session唯一evaluation→simulationFrame→各surface独立提交→唯一compositor已分别有界执行；[readiness后验](../history/rf05-named-provider-readiness-implementation-2026-10-02.md)不证明全部组合。物理多屏/clock、跨surface VM/粒子/Puppet cadence、late epoch/purpose、重建中拖动和异步故障仍未联验。先实际可达组合与取消/退休反例，不新增第二事务或每帧heap序列化。[输入/lifecycle范围](../capabilities/runtime-input-property-coverage.md) |
| 两条历史GPU门与hidden extent覆盖 | persistent_history_visual_failure_gpu的initial passthrough、preserved_channel_frame_local_unique的8项false只证固定f79088a5旧输入；hidden resolvedMaterial extent的Python桩P2也未取得fresh关闭链。先核当前真实harness/生产分支再判fixture或产品，不能据旧红声明HEAD故障。原271检查/32false已另行闭合，不再列作当前产品失败。[已闭graph债](../history/graph-color-purpose-reconciliation-2026-10-12.md) |

其余尚未覆盖profile按[材质/Graph](../capabilities/render-graph-shader-coverage.md)、[Effect](../capabilities/effect-execution-coverage.md)、[Puppet/3D与平台](../capabilities/advanced-object-coverage.md)维护：LUT/material、未证source/provider、alpha/nested clipping、Puppet mixing/ended、级联destroy、Vec4/matrix、未证歌词平台或物理HDR等，只有获得具体可达缺口/反例才进入本队列。family名、L0/L1、没有golden或某平台未测不单独排一个“当前缺陷”。Steam真实授权/签名安装任务归[Steam路线](scene-steamkit-migration-plan.md)，不从旧发布版本生成安装指令。

## 6. 进入、关闭与证据退出

- 每次只选有用户价值的共享首错；先固定输入/属性/时间/音源/viewport与App身份，标明运行反例或静态候选。缺资格先做最便宜的区分，不补样本算法。
- 保持authored→prepared Program/graph/resources→typed frame→Metal→唯一compositor；同一输入不可双owner。普通帧不新增解析/编译/整图序列化或哈希；资源安全失败拒最小不安全单元，普通视觉失败局部回退。
- 关闭需同语义正例、改名/等价输入及相邻反例、真实输出、健康独立样本与相称生命周期证据。按子现象退出，不能把局部修复写整样本完成；没有当前缺陷的作者关闭项不保“待修”。
- 旧人工verdict与全集运行关联仍由台账维护，未知保持原状；更新随有效代表批进行，不为刷绿重跑全corpus。报告必要截图/中性事实、失败尝试、drift、退出/资源回收；只在用户授权时提交/发布。
