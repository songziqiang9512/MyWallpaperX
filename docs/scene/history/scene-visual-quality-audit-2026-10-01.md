# Scene 画面质量审查报告（2026-10-01）

> **历史证据 — 非现役入口**
>

- 截止日期：2026-10-01
- 类型：Scene 专题静态审查记录（算法/写法质量 → 画面实际呈现效果）
- 独有价值：四路并行只读代理交叉审查产出的「画面劣化问题」总账——含 4 个文档未登记的算法级新发现（相机抖动、发射图 alpha、straight-alpha 降采样、音频 16 档稀释）与「L3 已执行 ≠ 画面等价」的折扣清单、E5 降级残类、结构性能力洞的完整对照；行号锚定提交 ff8019c8 时点
- 当前权威：当前代码与运行证据；各条修复进展以工作树与提交历史为准，本文件不决定后续任务顺序

## 审查方法与范围

- 方法：四路并行只读代理（禁止编辑/构建/运行测试）——①文档权威面（coverage-ledger、runtime-evidence-current、roadmap、engine-refactor-program E5、验收台账、effect-execution-coverage）；②运行时渲染算法质量（数值方法/色彩混合/纹理采样/粒子/音频/时序/几何七维度逐项找实例）；③shader 编译与路线选择层的降级缺口；④效果类别专项（对照 scene_capability_census 普查与实现代码）。四路结果交叉核对后汇总。
- 范围：`MyWallpaperX/Core/SteamWorkshopScene/`（Runtime、Systems、Rendering、Resources、Compilation 抽查）+ `docs/scene/` 权威文档 + `script/scene_capability_census*.json`。
- 性质：静态审查。低置信项已明确标注「需与官方客户端对照后定」，未做任何运行时实测。

## 总体判断

引擎数值功底总体相当好，以下常见坑经审查明确排除：弹簧用闭式阻尼解（长帧不发散）、贝zier 关键帧 48 轮二分精确反解（无线性化）、splitmix 随机数无模偏差且 per-particle 派生种子、暂停恢复用锚点平移（无相位跳变）、法线用双精度逆转置矩阵、发射率小数余数累积无丢帧、正交/透视/reverse-Z 数学正确。真正影响画面的问题集中在四层：代码级算法缺陷（新发现）、「已执行但打折」的近似、shader 降级导致效果丢失、结构性能力洞。风险形态几乎都是「缺块/不出现/形态不等价」而非画面错乱——失败均为局部 fail-soft 保 previous-current。

## 第一层：文档未登记的算法级缺陷（本次新发现，可直接立项）

### V1.【高】相机抖动是平滑周期轨道，无噪声成分

- 位置：`Systems/Input/SceneCameraShake.swift:103-117`（periodicVector）、`:119-139`（radialShape）；消费点 `Rendering/Frame/SceneMetalRenderer+Camera.swift:15-25`。
- 问题：抖动位移 = `SIMD2(cos(phase), sin(phase×1.333))` 双频 Lissajous 合成，`phase = sceneTime × speed²`；roughness 只做径向 `pow(length, roughness³)` 整形。无任何高频/噪声成分。
- 画面后果：speed<1（作者常用 0.1~0.5）时为秒级慢摇摆；speed=1 时每 6π 秒精确重复一次。观众看到的是平滑「8 字/椭圆漂浮」而非抖动；roughness 大时运动趋向贴轴十字。两个审查方向独立命中。
- 修复方向：改用多倍频梯度噪声采样（工程内现成实现 `Systems/Particles/SceneParticleSimulationSupport.swift:204-262` gradientNoise），roughness 映射为倍频分布，保持绝对 scene time 相位（保留暂停/回放确定性）。

### V2.【中高】Layer Image 发射图 alpha 被二值化，发射密度无法表达作者渐变

- 位置：`Systems/Particles/SceneParticleLayerImageEmissionMap.swift:30-41`（收集 `alpha > 0` 像素）、`:49-52`（均匀随机采样）。
- 问题：alpha=1/255 与 alpha=255 的像素发射概率完全相同，无 alpha 加权。
- 画面后果：作者用 alpha 渐变绘制的发射图（边缘渐隐光晕、中心实外圈虚）被摊平——稀疏辉光边缘出现与核心等密的粒子，发射区域变「胖」。此为 `.layerImage` 发射器主路径（`SceneParticleSimulator.swift:610-612` 直调），非 fallback。
- 修复方向：按 alpha 累积权重 + 二分累积分布采样，保持现有 RNG 与确定性。

### V3.【中】straight-alpha 大图降采样：透明边缘黑边/彩边 + 4-tap 走样

- 位置：`Resources/Textures/SceneImageTextureUploader.swift:477-493`（straight RGBA 逐通道重采样）、`:497-530`（仅 2×2 tap 双线性）、`:664-683`（straightAlbedo 路径）；阈值 `SceneTextureLoader.swift:166`（4096）。
- 问题：(a) 对未预乘 RGBA 独立滤波，透明像素 RGB 混入半透明边缘，shader 按 alpha 合成时出现黑晕/彩边；(b) 双线性只 4 tap，8192→4096 跳过 75% 源像素，高频内容加载即摩尔纹。对照组：同文件预乘路径（`rasterizedRGBA`）交 CoreGraphics 在预乘域插值无此问题。
- 画面后果：>4096 带透明直载 PNG（图像层/粒子贴图）整层可见边缘晕圈与细节破碎。
- 修复方向：premultiply → 多 tap 盒式/面积滤波（或渐进 2× 链）→ unpremultiply；零 alpha 处 RGB 保留语义不受影响。

### V4.【中】音频 16/32 档效果柱条系统性偏矮（峰值被平均稀释）

- 位置：`Core/Playback/SystemAudioSceneSpectrumAnalyzer.swift:37-61`（resample 对区间内 canonical 带取平均）、`:299-321`（64 档每带峰值）。
- 问题：canonical 64 档取峰值，16 档消费者拿到 4 带平均——孤立窄带（高频打击乐）柱高最多衰减 4×；官方 16 档为原生分析。
- 画面后果：同一段音乐在 16 档效果（官方 pulse.vert/shake.vert 及 Simple Audio Bars 16）里柱条明显矮、相邻柱连成一片，与 64 档效果观感不一致。
- 修复方向：16/32 档下采样改取区间峰值（或峰值-平均混合），或按消费者档位原生分析。

### 低置信三项（需官方对照后定）

- mipmap 在 gamma 域生成（`SceneImageTextureUploader.swift:606-611` rgba8Unorm 无 sRGB 视图）：中灰缩小偏暗、高饱和过饱和；官方 Windows 端若同样处理则不算差距。
- 粒子颜色生命周期插值在 RGB 分量空间直乘（`SceneParticleSimulator.swift:742-748`）：深色过渡偏暗（gamma 空间乘法）。
- 湍流单轴 mask 后不归一（`SceneParticleSimulationSupport.swift:385-419`）：`|cos(turn)|` 缩放致粒子周期性停滞；湍流默认参数亦为项目自定（`SceneParticleAudioResponsePlan.swift:202-208`）。

## 复核更正（2026-10-01 官方取证）

同日对第一层 V1/V2/V4 完成官方客户端 clean-room 取证（证据阶梯与结论详见 [client-runtime-static-forensics.md](../development/reference/client-runtime-static-forensics.md) §5.12 补记、§5.13、§7.4），本节更正审查时的推断，原文保留存档：

- **V1 撤回**：官方 shake 求值器经静态定案为**周期解析函数**（双频正交对 + 固定非精确比，无任何噪声/查找表/倍频成分）——「换梯度噪声」的修复方向会制造与官方相反的行为，予以撤回。项目现行实现与官方同族且参数映射一致；speed<1 的慢摇摆是官方行为本身。真实残差收敛为：float32 vs Double 精度、true-perspective XYZ 分支未实现、编辑器预览路径未复核。
- **V4 修正**：「官方 16 档为原生分析」的假设被否证——官方只有一条 64 档/声道、每档取覆盖 bin 峰值的分析链，16/32 档必然从 64 档连续分组投影；最终投影算子（峰值 vs 平均）静态未钉死、旁证倾向峰值（黑盒柱高比实验已设计）。修复建议相应改为「16/32 档下采样取覆盖子带峰值」并标注项目策略直至黑盒定案；宿主侧平滑同样标注项目策略（官方语义为作者侧平滑）。
- **V2 降级为未定案**：官方文档无像素级权重描述，静态取证确认「构建期样本集 + 离散索引抽取」架构但未触达加权构建代码（深入即私有算法表达，按治理停手）。「按 alpha 加权」仅为项目推断，若实施必须登记为 bounded approximation 待黑盒三贴图实验判别；已固化三个无关权重的合同点（alpha=0 不发射中置信、默认精确像素位置 + random offset 为作者显式选项高置信、emitter image 为场景图层对象高置信）。

本更正不改变第二至五层的内容。取证遵守 clean-room 隔离：反编译原文未入库未进入实现上下文，后续实现由新上下文仅消费上述行为合同。

## 第二层：「已执行」但打折扣的近似（台账有登记，本次代码确认）

| 条目 | 位置 | 画面后果 |
|---|---|---|
| Sprite Trail 直线拉伸无路径历史 | `Systems/Particles/SceneParticleTrailRenderPlan.swift:36-51` | 螺旋/作曲运动拖尾呈直条纹，速度趋零塌缩成点；绳轨迹折角（e4353122）同族残余，全引擎最后一处瞬时量近似历史 |
| RopeTrail 死亡尾迹当帧整条消失 | `Systems/Particles/SceneParticleRopeTrailPlan.swift:156-158` | 流星尾末端突兀断掉，非按 length 保留窗渐退 |
| 半透明粒子无深度排序 | `Systems/Particles/SceneParticleRuntime.swift:528-554` | 密集+渐隐粒子叠加次序错（局部过亮过暗、闪烁） |
| 指针连续效果每帧单点采样 | `Runtime/Frame/SceneSurfacePointerState.swift:6-47`、`SceneResolvedMaterialUniformEncoder.swift:265-274` | 快速挥动鼠标时轨迹断点、发射环/涟漪密度不足；「绳轨迹」在输入侧的残余 |
| 指针 uniform 边界钳制与事件侧不一致 | 同上 `:265-274` clamp vs `:57-60` 不钳 | captured drag 拖出屏幕时依赖越界深度的效果在边界冻结 |
| CG 光栅化默认质量档 + DeviceRGB | `SceneImageTextureUploader.swift:767-791` | straightAlbedo 无 alpha 源 resize 走低质量插值；宽色域源被 gamut-clip |
| 数据纹理大幅下采样 4-tap | 同文件 `:497-529`（preserved-channel 256 限幅路径） | X-Ray 类数据纹理边缘细节损失/锯齿 |

正面确认（同类问题未再发现）：puppet 闭式阻尼弹簧+maxDistance 限幅、parallax 指数平滑带 rollback、光标逆 MVP 投影双重校验、事件缓冲溢出整批拒绝、Timeline/TextureAnimation 的 anchor 重基暂停恢复均正确。

## 第三层：shader 写法触发降级 → 效果整块丢失（多数挂 E5 排期）

1. **colorTransfer 残类**（fallback 最大族，归档 613 次）：形态⑤「`vec4(RGB 混合, 采样 alpha)`」（`SceneAuthoredShaderColorTransferAnalyzer.swift:495-503` 要求末位实参字面量 1 → unresolved）、形态③ gl_FragColor 多 use（`:400-419`）、形态⑥ tone_mapping 载体（现行拒绝已钉住）→ `colorContractUnproven` → 效果局部 fail-soft 不执行。扩展证明器已登记「待正确性论证专批」（engine-refactor-program.md E5 ②-e/②-f）。
2. **generic→bounded 回退链未归零**：3,522 份归档日志中回退触达 1,367 次（fallback 1,009 + shared-backend 358），9 月下旬仍活跃；命中者近似或跳过。decisive 45 样本复核挂起待空载窗口（E5 ①）。
3. **纹理用途 source-proven typing 在 canonical 源上全部失效**（文档登记未排期）：`SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift:214-218` 喂 canonical 形态 → 21 条诊断 → 一切 source-proven 证明 nil → 材质按静态图降级。实例：833227004 flowimage 动画星云现为静态底图。需语义卡裁决（typing 改分析 prepared 源 vs 语法分析器学 canonical 形态）。**2026-10-07 核对注记**：canonical 喂源已由 `ec59195e`（2026-10-01）按「typing 分析 prepared 源」裁决修复；833227004 残量再定性为 material-only 路由缺口（断点队列 QF 批D），3791967416 层 23 残量为 prepared 源上的诚实证明失败（通道子集数据流形状，断点队列 QF 批C，见 [render-graph-shader-coverage](../capabilities/render-graph-shader-coverage.md) 当日条目）。
4. **fragment 改写 varying 且 vertex/fragment 宽度不一致**：`SceneAuthoredShaderVaryingPrefixLink.swift:201-215` 写守卫拒绝 → 3807151772 effect2 动态波扫丢失（等宽度改写已由 `SceneGenericShaderMutableFragmentVaryingNormalizer` 无损处理）。归 E5 varying 后继。
5. **组合子树不连续/子层自带效果**（3226487183 层 2522 色差组）：`execution-route-utility-composition-subtree-shape` 整层拒绝，需组合组独立渲染目标的架构批（与缺口 1 同级）。
6. compound `+=` 残类 fail-closed（当前语料无产生者，处置合理）；stage-link 残余形态（归档 210 条中已修大部分，瞬态 exitcode--2 观察中）；效果链 >2048 降档（锐度损失，纠正门未跑）。

## 第四层：结构性能力洞（整类效果无实现，台账 L0/L1）

- **11 个官方效果族无执行路由（L1）**：Cloud Motion、Swing、Radial Blur、Blend Gradient、Clouds、Fire、Nitro、Reflection、Refraction（无 normal/mask 数学）、Skew、Edge Detection——声明这些效果的层直接没有该效果画面（effect-execution-coverage.md）。
- **Scene HDR/tone mapping/EDR L0**：HDR 样本高亮滚降/过曝行为与官方不同；RGBA16F 输出≠真 HDR（`E-2026-09-27-SCENE-COLOR-PRECISION`）。
- **2D 材质光照/PBR/阴影/反射 L0**：声明光照的 2D 场景无明暗响应（3662790108 动态点光 ROI 已正证，接近闭合）。
- 其他：粒子 Collision 无 solver、Maintain Distance/Remap/vortex_v2 等算子 L1、Layer Image emitter 仅静态 plain image、SceneScript component/object/particle API L0、Animation Events L0、文字 outline/shadow L1、7 个 stock 替代字体字形不等价、`_b` secondary 数据流 L1、current-frame capture 复杂子树 fail-closed。

## 第五层：样本级待复测（根因多已定位，停在「待用户看」）

3769761761 头发上方斜光缺失（`E-2026-09-28-RAY-SOURCE-DIAGNOSIS`）、3768724269 光束范围/视差脱离、3287715210 全屏竖条纹（8 位量化，16F 贯通后待复测）与眼周白粉光时序、1315486372 光线贴图生硬（旧裁决）、跨样本音频柱形态/两端弱（`E-2026-09-28-AUDIO-BAND-PEAKS` 后待 A/B）、3211615441 音频环偏细、3788467391 漩涡方向/速度（预热偏差 249/300 步保留）、雷电 405/412（periodicEmission 算法未定暂挂）、Q1-B 视差幅度过大+垂直反转（用户裁决挂起）、验收台账 19 条旧 fail（旧裁决不代表当前 HEAD）。**共同根约束：官方对照 172/172 not-run**——所有 clean-room 近似（湍流/蜂群/音频聚合/粒子尺寸单位）无法升级为 parity 判断；另 3750813609 时钟数字灰黑渐变 vs 白色发光、雨丝密度等价未证。

## 建议优先级

1. 第一层 V1/V2/V4：改一处、一类画面立刻变对，且不依赖官方取证；V3 同理。
2. 第二层 Sprite Trail 历史采样可复用绳轨迹修法；RopeTrail 死亡渐退、透明排序为独立小批。
3. 第三层按 E 路线现有排期（与 Scene 会话协调），colorTransfer 形态⑤与 texture-purpose typing 两项收益最大。
4. 第四层为长线结构性项，按现役路线排段。
5. 低置信三项与官方对照后定（依赖 P4 官方一致性外部条件解除）。

## 边界

- 静态审查：未运行应用、未做画面截图对照、未与官方客户端并排比较；「怀疑需实测」条目的视觉幅度未量化。
- 本报告是审查记录，不构成现役计划；任务顺序由 docs/scene/scene-compatibility-roadmap.md 与 engine-refactor-program.md 决定，采纳需按治理登记。
- 行号锚定提交 ff8019c8 时点，后续漂移以符号名为准。
