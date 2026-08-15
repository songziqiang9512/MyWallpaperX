# 编辑器字符串表取证（locale/ui_en-us.json）

审查日期：2026-07-26
取证快照：Wallpaper Engine 2.8.42 `locale/ui_en-us.json`（3,332 keys）及同族 `core_en-us.json`（96 keys）、`var_en-us.json`（28 keys），36 种语言各三族
审查方式：只读静态提取

> 文档角色：`official-client-static-observation`。字符串表可确认固定 2.8.42 编辑器的字段标签和作者可见说明，不自动构成官方公开运行合同，也不决定 MyWallpaperX 现役能力或顺序。证据分类见[资料来源与证据索引](source-index.md)。

> 字符串表是官方**字段名到作者可见语义**的权威对照：wire 字段（`horizontalalign`、`maxrows`、`controlpoint`…）在编辑器里叫什么、归哪个面板、和哪些枚举值成组。它还给出每个粒子组件与 utility 层的**官方一句话定义**——这些定义在 179 个官方网页中没有的粒度。
>
> 本文只收 Scene 相关子集。key 总量 3,332，其中 `ui_editor_properties_*` 865、`ui_editor_particle_*` 175、`ui_editor_effect_*`/`ui_editor_effects_*` 145、`ui_editor_animation_*` 60、`ui_editor_scene_options_*` 38、blend 命名 74。浏览器/商店/工坊/移动端域不收录。

复现命令：

```bash
python3.12 script/extract_wallpaper_engine_client_evidence.py --client-root ~/Downloads/wallpaper_engine --output-dir <生成物目录>
```

输出 `locale.json` 含三族 en-us 全量键值。证据等级：A（字段名与标签逐字来自随包文件）；由标签措辞推断运行时行为为 C，逐处标注。

## 1. 结论先行

1. **45 个 effect 的 `ui_editor_effect_<stem>_title` 恰好 45 条**，与 [Effect 执行覆盖表](effect-execution-coverage.md) 的 45 项名单一一对应——官方名单的又一独立 A 级确认，且给出每项官方描述。
2. **粒子组件官方定义齐全**：3 emitter / 16 initializer / 25 operator / 4 renderer，与 [Windows 取证记录](../../history/scene/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md) §19 preset corpus 的 3/16/25/4 逐项对齐，每项带一句话语义。
3. **blend mode 官方共 35 个名称，且官方自己分为 `Native (fast)` 与 `Emulated (slow)` 两组**。项目 Tint 的 32 模式 `ApplyBlending` 表可据此核对命名与分组，但数值语义仍以 `common_blending.h` 源码为准。
4. **属性绑定共五种来源**：User Property、Timeline Animation、Script、Album Cover（system resource 的 UI 名）、Attachment。其中「Bind to Attachment」的确认文案写明 *"This will replace the current script on the property"*——attachment 投影绑定在官方实现里**就是一段 script**（C 级推断：该绑定复用 SceneScript 通道）。
5. **Timeline 编辑器合同**：mode 为 Loop/Mirror/Single，`Start paused`、`Random start frame` 是并列开关；smooth loop wrap 的官方定义是 *"Sets the last frame of the animation equal to the first frame"*；keyframe 的 Bézier 插值有五态 `none, automatic, left, right, both`；animation event 按 Frame + Name 登记。
6. **Scene options 全集**（38 keys）：标准 Bloom 与 Ultra HDR 两套参数、Camera parallax 带 `Amount`/`Delay`、Camera shake 带 `Amplitude`/`Roughness`/`Speed`、Camera zoom、Distance Fog 与 Height Fog 各带 start/end/density、Near/Far Z、FOV、Physics、Transparent object sorting。
7. **Utility 层官方定义**：`composelayer` = Adjustable Composition Layer（子对象合成单纹理）、`projectlayer` = Full Composition Layer（覆盖整个壁纸、与壁纸对齐）、`fullscreenlayer` = Post-processing Layer（覆盖屏幕、**不随壁纸移动**）；另有 Built-in Post-processing Controller 与 Solid Placeholder（solid 可被 user texture 或 album cover 动态替换）两类项目未建模的层。
8. **effect 有版本概念**：导入不同版本 effect 会弹 "Different Effect Version" 警告并可能重置实例设置。

## 2. 45 项 Effect 官方名称

`ui_editor_effect_<stem>_title` 全集（stem 与 asset ID 的差异独立列出）：

| stem | 官方 title | 对应 asset ID |
|---|---|---|
| `advanced_fluid_simulation` | Advanced Fluid Simulation | `fluidsimulation` |
| `blend` | Blend | `blend` |
| `blend_gradient` | Blend Gradient | `blendgradient` |
| `blur` | Blur | `blur` |
| `blur_precise` | Blur (Precise) | `blurprecise` |
| `blur_radial` | Radial Blur | `blurradial` |
| `chromatic_abberation`（官方拼写如此） | Chromatic Aberration | `chromaticaberration` |
| `cloudmotion` | Cloud Motion | `cloudmotion` |
| `clouds` | Clouds | `clouds` |
| `color_key` | Color Key | `colorkey` |
| `cursor_ripple` | Cursor Ripple | `cursorripple` |
| `depth_parallax` | Depth Parallax | `depthparallax` |
| `edge_detection` | Edge Detection | `edgedetection` |
| `filmgrain` | Film Grain | `filmgrain` |
| `fire` | Fire | `fire` |
| `fisheye` | Fisheye | `fisheye` |
| `foliage_sway` | Foliage Sway | `foliagesway` |
| `glitter` | Glitter | `glitter` |
| `godrays` | God Rays | `godrays` |
| `iris` | Iris Movement | `iris` |
| `light_shafts` | Light Shafts | `lightshafts` |
| `local_contrast` | Local Contrast | `localcontrast` |
| `motion_blur` | Motion Blur | `motionblur` |
| `nitro` | Nitro | `nitro` |
| `opacity` | Opacity | `opacity` |
| `perspective` | Perspective | `perspective` |
| `pulse` | Pulse | `pulse` |
| `reflection` | Reflection | `reflection` |
| `refract` | Refraction | `refraction` |
| `scroll` | Scroll | `scroll` |
| `shake` | Shake | `shake` |
| `shimmer` | Shimmer | `shimmer` |
| `shine` | Shine | `shine` |
| `skew` | Skew | `skew` |
| `spin` | Spin | `spin` |
| `swing` | Swing | `swing` |
| `tint` | Tint | `tint` |
| `transform` | Transform | `transform` |
| `twirl` | Twirl | `twirl` |
| `vhs` | VHS | `vhs` |
| `water_caustics` | Water Caustics | `watercaustics` |
| `water_flow` | Water Flow | `waterflow` |
| `water_ripple` | Water Ripple | `waterripple` |
| `water_waves` | Water Waves | `waterwaves` |
| `xray` | X-Ray | `xray` |

带行为线索的描述两条：Depth Parallax 的描述以加粗强调 *"requires the parallax option in the editor scene settings to be enabled"*（与 [开发硬规则](README.md#41-能力存在不等于启用) 的启用条件一致）；effect 选择器把每项归入官方组 `Animate / Blur / Colorize / Distort / Enhance / Interactive`，另有 `My Effects / Presets / Renderables / Utilities / Workshop` 五个非 effect 组。性能警告分两级：`Expensive` / `Very Expensive`。

## 3. 粒子组件官方名称与定义

组面板官方分组：`General / Emitters / Initializers / Operators / Renderers / Control Points / Children`（`ui_editor_particle_element_group_*`，7 组）。

### 3.1 Emitter（3）

| wire 名 | 官方 title | 官方描述要点 |
|---|---|---|
| `boxrandom` | Box random | 盒形内随机位置发射 |
| `sphererandom` | Sphere random | 球形内随机位置发射 |
| `layerimage` | Layer image | **从 image/text/puppet 层发射**；可用附加 mask 限制发射区域；发射时尊重 puppet warp 动画；粒子可用发射点的图层颜色初始化 |

`layerimage` 描述给出的能力面远超项目当前 `L1`（仅名称可诊断）：mask、puppet warp 跟随、图层颜色采样都是作者可见合同。

### 3.2 Initializer（16）

| wire 名 | 官方 title | 官方描述要点 |
|---|---|---|
| `alpharandom` | Alpha random | 随机 alpha |
| `angularvelocityrandom` | Angular velocity random | 随机初始角速度 |
| `colorlist` | Color list | 从预选颜色列表随机取色 |
| `colorrandom` | Color random | 两色之间随机 |
| `hsvcolorrandom` | HSV color random | HSV 空间随机，色域更大 |
| `inheritcontrolpointvelocity` | Inherit control point velocity | 把指定 CP 的当前速度加到粒子上 |
| `inheritinitialvaluefromevent` | Inherit initial value from event | 从父粒子事件读值作为初始值 |
| `lifetimerandom` | Lifetime random | 随机寿命 |
| `mapsequencearoundcontrolpoint` | Position around control point | 按序绕某 CP 摆放 |
| `mapsequencebetweencontrolpoints` | Position between control points | 按序摆在两 CP 之间 |
| `positionoffsetrandom` | Position offset random | **用 fractal brownian motion 偏移位置** |
| `remapinitialvalue` | Remap initial value | 创建时读取属性或 CP 值并变换 |
| `rotationrandom` | Rotation random | 随机初始旋转 |
| `sizerandom` | Size random | 随机初始大小 |
| `turbulentvelocityrandom` | Turbulent velocity random | **沿 perlin noise 决定的方向加速** |
| `velocityrandom` | Velocity random | 随机初始速度 |

`turbulentvelocityrandom` 官方口径是 perlin noise；项目实现是自建 3D gradient noise（[粒子组件覆盖表](particle-component-coverage.md) 已标注非数值等价），本行进一步确认官方噪声族。`positionoffsetrandom` 的 fbm 口径同理。

### 3.3 Operator（25）

| wire 名 | 官方 title | 官方描述要点 |
|---|---|---|
| `alphachange` | Alpha change | 寿命内两值间混合 alpha |
| `alphafade` | Alpha fade | fade in/out 便捷配置 |
| `angularmovement` | Angular movement | 角运动 + 角力 |
| `boids` | Boids | 聚群、匹配速度、保持最小间距 |
| `capvelocity` | Cap velocity | 限速 |
| `collisionbounds` | Collision bounds | **对 2D 场景的 2D 边界碰撞** |
| `collisionmodel` | Collision model | 对 3D 或 puppet warp 模型碰撞 |
| `collisionplane` | Collision plane | 无限平面碰撞 |
| `collisionquad` | Collision rectangle | 有限矩形、**仅单面**碰撞 |
| `collisionsphere` | Collision sphere | 球碰撞 |
| `colorchange` | Color change | 寿命内两色混合 |
| `controlpointattract` | Control point force | 基于 CP 位置的吸引/排斥力 |
| `inheritvaluefromevent` | Inherit value from event | 从父事件读值作为当前值；官方注明 *"Typically only useful for follow events"* |
| `maintaindistancebetweencontrolpoints` | Maintain distance between control points | 锁定在两 CP 之间 |
| `maintaindistancetocontrolpoint` | Maintain distance to control point | 与 CP 保持定距 |
| `movement` | Movement | 运动 + 重力 |
| `oscillatealpha` | Oscillate alpha | 两值间振荡不透明度 |
| `oscillateposition` | Oscillate position | 沿轴振荡位置 |
| `oscillatesize` | Oscillate size | 两值间振荡大小 |
| `reducemovementnearcontrolpoint` | Reduce movement near control point | CP 附近减速 |
| `remapvalue` | Remap value | **每帧**读属性或 CP 值并变换 |
| `sizechange` | Size change | 寿命内两值混合大小 |
| `turbulence` | Turbulence | 湍流力 |
| `vortex` | Vortex | 绕 CP 旋涡力 |
| `vortex_v2` | Vortex（同名） | 绕 CP 旋涡力；v2 与 v1 在 UI 中同名，区分只在 wire 层 |

### 3.4 Renderer（4）

| wire 名 | 官方 title | 官方描述要点 |
|---|---|---|
| `sprite` | Sprite | 基本平面 quad |
| `spritetrail` | Sprite trail | 沿运动方向的条痕 |
| `rope` | Rope | **所有粒子按 spawn 时间连成一条绳** |
| `ropetrail` | Rope trail | 每个粒子一条尾随绳 |

`required_movement_tip` / `required_angular_movement_tip` 两个 tag 说明部分组件在编辑器里**强制要求 Movement / Angular movement operator 存在**（具体是哪些组件挂 tag 需查编辑器逻辑，本表只固定标签存在；C 级）。

### 3.5 Remap 枚举官方标签

`remapinitialvalue` / `remapvalue` 的三组枚举（与 preset corpus §19 的字段值互证）：

- **operation（4）**：`add`=Add、`multiply`=Multiply、`remap`=**Assign**（官方把 `remap` 操作叫 Assign）、`subtract`=Subtract。
- **input/output option（24）**：Angular speed、Color、Control point、Delta to control point、Direction to control point、Distance to control point、**Layer origin、Layer time、Lifetime fraction、Maximum lifetime**、Opacity、Particle system time、Position、Position between two control points、Rotation、**Runtime、Time of day**、Size、Speed、Velocity 等。`Time of day`/`Layer time`/`Runtime`/`Particle system time` 构成粒子可读的**四种时间源**。
- **transform_function（7）**：`none`、`saw`=Saw wave、`simplexnoise`=Simplex noise、`sine`=Sine wave、`square`=Square wave、`triangle`=Triangle wave、`fbmnoise`=Organic FBM noise。preset corpus 只观察到其中 3 种被使用，此处是完整值域。

### 3.6 Inherit from event 模式（14）

`inheritinitialvaluefromevent` / `inheritvaluefromevent` 的模式枚举，按「动词 × 属性」构成：

| 动词 | 可作用属性 |
|---|---|
| Set | velocity、rotation、angular velocity、color、opacity、color+opacity、size |
| Add | velocity、rotation、angular velocity |
| Multiply | color、opacity、color+opacity、size |

这是 child event 值继承的完整作者面；项目当前 census 里该组件使用为 0，等级 `L1`，本表为将来实现固定值域。

### 3.7 Control point 属性标签

`Lock to control point`、`Control point {{index}} (Origin)`（**index 0 是 Origin** 的 UI 佐证）、`Parent control point index`（child 继承父 CP，对应 changelog REV 4127）、`Input/Output control point (2)`（remap 的 CP 输入输出各可指定两个）、`Set control points to particle positions`。

## 4. Blend mode 官方名单（35）

`ui_editor_blending_*`。官方分两组（`ui_editor_blending_group_*`）：**Native (fast)** 与 **Emulated (slow)**；哪个模式属于哪组由编辑器逻辑决定，字符串表只固定组名存在（分组归属为 C 级待查项）。

按字母序：Add、Average、Color、Color burn、Color dodge、Darken、Darker color、Difference、Diffuse light、Exclusion、Glow、Hard light、Hard mix、Hue、Lighten、Lighter color、Linear burn、Linear dodge、Linear light、Luminosity、Multiply、Negation、Normal、Overlay、Phoenix、Pin light、Reflect、Saturation、Screen、Soft light、Subtract、Tint、Vivid light。

计 33 个模式名 + 2 个组名 = 35 key。`Diffuse light` 由 changelog REV 3982 确认为后加模式。项目 Tint backend 的 32 模式表与此名单的差集（33 对 32）与编号映射，须以 `common_blending.h` 的 `ApplyBlending` switch 为准核对，本表只提供名称全集；`Tint` 同时是 blend mode 名与 effect 名，语境需区分。

## 5. Timeline 编辑器合同（`ui_editor_animation_*`，60 keys）

| 合同项 | 官方字符串证据 |
|---|---|
| 模式三选 | `modal_loop`=Loop、`modal_mirror`=Mirror、`modal_single`=Single |
| 起始暂停 | `modal_start_paused`=Start paused |
| 随机起帧 | `modal_random_start_frame`=Random start frame |
| 平滑循环 | `modal_loop_wrap`=Create smooth animation loop；help 正文：*"Sets the last frame of the animation equal to the first frame, resulting in a smooth loop that ends exactly where it starts."* |
| 时长口径 | `modal_fps`/`modal_frames`/`modal_seconds`，可在 FPS 与 frames 两种口径间切换 |
| Bézier 切线 | `toggle_bezier`：*"Toggle Bézier interpolation at keyframe (none, automatic, left, right, both)"* —— **五态枚举** |
| 逐属性合并 | `modal_combine_property_animation`=Combine property animation |
| 动画事件 | `events_modal_header`=SceneScript Animation Events，表列 `Frame` + `Name`（事件按帧号登记、以名字派发给同层脚本） |
| CP 锁定 | `lock_control_point_angles` / `lock_control_point_lengths`（曲线编辑器的 Bézier 控制柄也叫 control point，与粒子 CP 无关） |

与 [运行输入与属性覆盖表](runtime-input-property-coverage.md) 的 Timeline `L0` 行对照：本节把官方页面已知的 Loop/Mirror/Single/paused/wrap 合同补上了 `Random start frame`、FPS/frames 双口径与 Bézier 五态三个此前未固定的细节。

## 6. Scene options 全集（`ui_editor_scene_options_*`，38 keys）

| 组 | 字段（官方标签） |
|---|---|
| General | Background color、Enabled、Physics、Transparent object sorting |
| Bloom（标准） | Bloom、Strength、Threshold、Tint；hint 注明 *"Bloom effects require post-processing to be enabled in Wallpaper Engine performance settings"* |
| Bloom（Ultra HDR） | `hdr`=**Ultra post-processing (HDR)**、HDR iterations、HDR scatter、HDR strength、HDR threshold、HDR threshold smoothing；hint 要求作者同时测试标准与 HDR 两种模式 |
| Camera | Camera、Camera preview、FOV、Near Z、Far Z、Camera zoom、Mouse influence |
| Camera parallax | Camera parallax、Amount、Delay |
| Camera shake | Camera shake、Amplitude、Roughness、Speed |
| Distance Fog | Start、End、Start density、End density、Color |
| Height Fog | 同上一组共用 start/end/density/color 键族 |

对照 [高级对象覆盖表](advanced-object-coverage.md)：官方 Scene 级 Bloom 是「标准 + Ultra HDR」双模式、共 10 参数的系统；Camera shake 的三参数（Amplitude/Roughness/Speed）与 Camera parallax 的 Amount/Delay 分属 [coverage-ledger](coverage-ledger.md) 的独立能力行。字符串表只证明作者面，不证明运行 evaluator；现役 bounded Camera Shake 代码与证据见 [运行输入与属性覆盖表](runtime-input-property-coverage.md#op-camera-shake)。Distance/Height 双 Fog 是项目未建模的场景级系统（`ui_editor_properties_fog` 另有逐层 Fog 标签一枚）。

## 7. 层类型与属性绑定

### 7.1 层创建面板官方定义（`ui_editor_effects_modal_*`）

| wire 名 | 官方名 | 官方定义要点 |
|---|---|---|
| `composelayer` | **Adjustable Composition Layer** | 指定尺寸的半透明层；把子对象合成为单一纹理后可整体套 effect |
| `projectlayer` | **Full Composition Layer** | 自动覆盖整个壁纸；影响之前绘制的对象；比 Post-processing Layer 更耗性能；用于需要与壁纸精确对齐的全屏效果 |
| `fullscreenlayer` | **Post-processing Layer** | 覆盖整个屏幕；影响之前绘制的对象；**永远对齐屏幕、不随壁纸移动**；适合不需要精确对齐或 mask 的全屏效果 |
| `postprocessing_controller` | Built-in Post-processing Controller | 把 WE 某些内置后处理提前到自己的部分图层之前渲染 |
| `replaceablesolidlayer` | Solid Placeholder | 纯色层，**可被 user texture 或 album cover 动态替换** |
| `solidlayer` | Solid Layer | 纯色层 |
| `imagelayer` / `model` / `particle_system` / `light` / `camera` / `sound` | Image Layer / Model / Particle System / Light / Camera / Sound | Sound 定义为 *"looping background music or randomly playing ambient sounds"*；Light 只影响启用 lighting 的图像或 3D 模型 |

前三行是项目 `Utility composition`（typed composition/project/fullscreen）`L3` 行的官方语义原文；「fullscreen 不随壁纸移动、project 随壁纸对齐」是两者的判据性差异。Solid Placeholder 与 Built-in Post-processing Controller 是项目尚未建模的层类型。

### 7.2 属性绑定五源（`ui_editor_properties_context_menu_*`）

每个可绑定属性的右键菜单提供 Bind/Edit/Unbind 三态 × 五种来源：

1. **User Property**（Bind User Property）
2. **Timeline Animation**（Bind Timeline Animation）
3. **Script**（Bind Script）
4. **Album Cover**（Bind Album Cover，键名为 `bind_system_resource`——**system resource 的 UI 名就是 Album Cover**，与 `$mediaThumbnail` identity 对应）
5. **Attachment**（Bind to Attachment；确认文案 *"This will replace the current script on the property"*，即该绑定以 script 形式写入属性——C 级推断：attachment follow 复用 SceneScript 通道，而非独立 wire 字段）

另有 `Restore Default Value`。这与 [能力依赖图 D3](capability-dependency-map.md#d3) 的 `authored -> property -> Timeline -> SceneScript` 优先级模型相容，并把 system resource 与 attachment 两种来源补进完整作者面。

### 7.3 Text 层字段对照

| wire 字段（interpretation v29 已消费） | 官方标签 |
|---|---|
| `limitrows` | Limit rows |
| `maxrows` | Max rows |
| `limitwidth` | Limit width |
| `limituseellipsis` | Overflow ellipsis |
| `anchor` | Screen anchor |
| `horizontalalign` / `verticalalign` | Horizontal / Vertical Alignment |

另有 `Font`、`Font Effects`（对应 changelog 的 MSDF text effects 面板）。`maxwidth` 的标签在 `ui_editor_properties_limit_width` 数值对中，无独立 key。

### 7.4 Audio response 字段族

`ui_editor_properties_audio_*`：Audio response（开关）、Audio amount、Audio bounds、Audio exponent、Audio frequency、**Audio attenuation start distance**（空间化衰减起始距离，与 changelog REV 4167-4168 的 sound spatialization 对应）。另有独立 `frequency_min/max/start/end` 键族。这是 [粒子组件覆盖表](particle-component-coverage.md) audio-response 行与 Sound layer `L0` 行的作者字段面。

## 8. 维护与边界

1. 本表是字符串证据：**字段在 UI 里存在不等于 runtime 语义已知**，数值行为仍以 `assets/**` 源码、preset corpus 与运行门为准。
2. `ui_en-us.json` 会随版本变化；重跑提取脚本比对 `locale.json` 的 keyCount 与本表计数即可发现漂移。
3. 浏览器（`ui_browse_*`）、设置（`ui_settings_*`）、工坊、角色创建（`ui_editor_character_*` 79 keys）、骨骼编辑（`ui_editor_bone_*` 66 keys）与模型编辑域未逐 key 收录；其中 bone/character 域在 Puppet 批次推进时应按需补充。
4. 不应从官方描述的措辞反推数值公式（如 boids 的「minimum distance」不给出距离度量）；描述只界定能力面与启用条件。
