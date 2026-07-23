# Wallpaper Engine Scene 壁纸特效特性与兼容能力梳理

> 面向：在 macOS 上开发 Windows 端 Steam Wallpaper Engine（俗称“小红车”）Scene 壁纸兼容播放软件
> 范围：Wallpaper Engine 官方 Scene / Editor / Effects / SceneScript / Particles / Timeline / 3D / Shader 等能力
> 说明：本文依据 Wallpaper Engine 官方文档整理，偏向第三方播放器兼容实现视角。
>
> 核验边界（2026-07-22）：官方资料描述的是编辑器与官方运行时行为，并未公开稳定的 Workshop 序列化格式规范。本文用于能力地图，不直接充当 MyWallpaperX parser / renderer 实现规范；项目当前事实与实施顺序以 [Scene 播放能力开发计划](scene-capability-development-plan-2026-07-22.md) 为准。
>
> 执行语义入口（2026-07-23）：179 个官方页面的逐页归属、Effect/Particle/SceneScript/Graph/Shader/运行输入/高级对象专项能力表、公共依赖图和运行证据已关联到 [Scene 语义手册](semantics/README.md)。后续实现以专项能力表和 [能力依赖图](semantics/capability-dependency-map.md) 为准，本文继续作为上层能力地图，不再重复维护底层 pass 表。

---

## 1. Scene 壁纸的核心模型

Wallpaper Engine 的 **Scene wallpapers** 是基于官方编辑器构建的实时场景壁纸。它不是单纯的视频或网页，而是由多个图层、资产、效果、动画、脚本、粒子和后处理共同组成的动态场景。

官方 Scene 编辑器支持：

- 导入图片、音频等外部资源；
- 添加内置资产；
- 使用类似图像编辑软件的图层结构；
- 对图层应用位置、旋转、缩放、透明度等变换；
- 为图层添加效果栈；
- 使用 Timeline 动画；
- 使用 Puppet Warp 骨骼变形；
- 使用粒子系统；
- 使用 SceneScript 脚本；
- 使用音频响应；
- 使用鼠标交互、视差、媒体信息、3D 模型、灯光、Shader 等高级能力。

官方来源：
https://docs.wallpaperengine.io/en/scene/overview.html

### 1.1 兼容播放器需要抽象的基础结构

| 模块 | 兼容抽象 |
|---|---|
| Scene / Project | 画布尺寸、项目设置、全局后处理、HDR/Bloom 参数 |
| Asset / Layer | 图层顺序、可见性、透明度、位置、旋转、缩放、父子层级 |
| Effects | 图层效果栈、效果参数、遮罩、混合、实时更新 |
| Timeline | 属性关键帧、Loop / Mirror / Single 播放模式 |
| SceneScript | 生命周期、属性绑定、事件、输入、音频、时间、用户属性 |
| Particles | 发射器、初始化器、操作器、渲染器、控制点、子粒子 |
| Audio / Media | 音频频谱、播放状态、歌曲信息、专辑封面、媒体主色 |
| 3D | 模型、相机、材质、骨骼动画、附件、灯光、阴影、体积光 |
| Shader | 内置 shader、自定义 effect shader、uniform、平台差异 |

### 1.2 Composition 与动态图层引用

官方 RGB 文档明确说明 Composition layer 像相机一样记录其下方图层；Effects 与 Blend 文档还允许效果链接其他动态 image layer，shader sampler 也可能指向内部 render target。这说明兼容播放器需要保留 source order、离屏目标和跨层纹理读取语义。

官方来源：
https://docs.wallpaperengine.io/en/scene/rgb/introduction.html
https://docs.wallpaperengine.io/en/scene/effects/introduction.html
https://docs.wallpaperengine.io/en/scene/effects/effect/blend.html
https://docs.wallpaperengine.io/en/scene/shader/variables.html

官方没有公开 Workshop named-target 名称、dependency DAG 或 `projectlayer/fullscreenlayer` 的稳定序列化格式。第三方播放器可依据真实样本建立内部 typed contract，但不能把样本观察包装成官方格式保证。

官方 shader 变量还区分纹理的物理尺寸与有效映射尺寸：`g_TextureNResolution.xy` 是物理 texture size，`.zw` 是 mapped size；例如纹理补齐到下一个 2 次幂后，mapped size 会小于物理尺寸。Effect、mask 和 dependency input 不能默认两者相同，否则 blur 半径、UV 位移和局部合成会随资源布局产生错误。

---

## 2. 官方内置 Effects 分类

官方 Effects Overview 将默认效果分为多个类别，包括 Animation、Blur、Interactive、Colorization、Distortion、Enhancement 等。

官方来源：
https://docs.wallpaperengine.io/en/scene/effects/overview.html

---

## 3. Animation Effects：动画类效果

| 效果 | 能力说明 | 兼容要点 |
|---|---|---|
| Foliage Sway | 树叶、草、灌木风吹摆动 | 必须区分逐像素 UV 与整层 Vertex 两种模式，保留作者参数与 opacity mask |
| Iris Movement | 角色眼睛运动 | 常用于二次元角色眼球跟随或循环运动 |
| Pulse | 颜色或亮度脉冲 | 可用于灯光闪烁、呼吸光、魔法阵 |
| Cloud Motion | 云层运动 | 通常是噪声/纹理偏移 |
| Scroll | 图像持续滚动 | 常见于背景、星空、雨雪、UI 条纹 |
| Shake | 往复晃动 | 可用于呼吸、震动、角色细微运动 |
| Spin | 持续旋转 | 需要处理中心点与速度 |
| Swing | 摆动 | 常用于旗帜、招牌、吊灯等 |
| Twirl | 螺旋扭曲动画 | 需要支持局部扭曲和动画参数 |
| Water Flow | 局部连续流动 | 可用于水、云、烟、能量流 |
| Water Ripple | 水波纹变形 | 需要波纹传播或法线扰动 |
| Water Waves | 抽象水波 | 可用于水面、布料、头发 |

Foliage Sway 官方定义了两种不同语义。**UV** 模式逐像素作用，可用于普通 image layer，作者可调 phase、power、ratio、scale、direction、speed、strength；**Vertex** 模式会摆动完整 image layer，适合已用透明背景切出的对象，并使用 corner/direction weights 等整层参数。Opacity mask 决定效果实际覆盖的区域。兼容实现不能把 Vertex 当成局部头发网格，也不能忽略 mask 或把统一强度/速度套到所有图层；没有作者声明的图层必须保持不动。

官方来源：
https://docs.wallpaperengine.io/en/scene/effects/effect/sway.html

---

## 4. Blur Effects：模糊类效果

| 效果 | 能力说明 | 兼容要点 |
|---|---|---|
| Blur | 粗略高斯模糊，性能较好 | 可用低成本 separable blur 近似 |
| Blur Precise | 精确高斯模糊 | 用于轮廓、光束、柔光等视觉 |
| Motion Blur | 累积运动模糊 | 需要历史帧或速度近似 |
| Radial Blur | 围绕指定点的径向模糊 | 常用于爆发、速度线、光晕 |

---

## 5. Interactive Effects：交互类效果

| 效果 | 能力说明 | 兼容要点 |
|---|---|---|
| Cursor Ripple | 鼠标经过产生涟漪 | 需要鼠标坐标、点击/移动状态 |
| Advanced Fluid Simulation | 高级流体/烟/火模拟，可响应鼠标 | 计算开销高，可先降级实现 |
| Depth Parallax | 鼠标移动驱动深度视差 | 需要深度图、鼠标归一化坐标 |
| X-Ray | 根据鼠标位置在两张图之间混合 | 需要圆形/渐变遮罩与鼠标坐标 |

Camera Parallax 必须先在 Scene options 中启用，并逐层读取 `parallax depth`；某层 depth 为 0 时该层不参与普通相机视差。Depth Parallax 是独立 effect，官方要求同时启用 Camera Parallax，并把当前层的普通 parallax depth 设为 0。兼容播放器不得因识别到深度图或鼠标输入就对所有壁纸全局启用视差。

官方来源：
https://docs.wallpaperengine.io/en/scene/parallax/introduction.html
https://docs.wallpaperengine.io/en/scene/effects/effect/depthparallax.html

---

## 6. Colorization Effects：色彩与叠加类效果

| 效果 | 能力说明 | 兼容要点 |
|---|---|---|
| Blend | 图像/图层混合 | 需要支持多种 blend mode |
| Blend Gradient | 渐变遮罩混合 | 需要渐变 mask |
| Chromatic Aberration | 色差失真 | RGB 通道偏移 |
| Clouds | 添加云层 | 噪声纹理动画 |
| Color Key | 类似绿幕抠像 | 按颜色透明化 |
| Film Grain | 胶片颗粒 | 随机噪声叠加 |
| Glitter | 随机闪光高光 | 高亮随机闪烁 |
| Shimmer | 移动光泽 | 扫光效果 |
| Fire | 火焰区域动画 | 噪声、颜色梯度、遮罩 |
| Light Shafts | 光束 | 常与模糊/遮罩结合 |
| Nitro | 静电噪闪 | 高频噪声与颜色扰动 |
| Opacity | 局部透明 | alpha mask |
| Reflection | 动态反射 | 反射纹理、扰动、渐隐 |
| Tint | 改变图层颜色 | 色彩矩阵或乘色 |
| VHS | 老录像带失真 | 扫描线、色偏、噪声、水平偏移 |
| Water Caustics | 水下焦散 | 动态光纹，需透视参数 |

---

## 7. Distortion Effects：变形类效果

| 效果 | 能力说明 | 兼容要点 |
|---|---|---|
| Fisheye | 鱼眼变形 | UV 径向扭曲 |
| Perspective | 透视变形 | 四角/矩阵变换 |
| Refraction | 基于法线贴图折射 | 需要 normal map 和采样偏移 |
| Skew | 边缘偏移 | 2D 几何/UV 偏移 |
| Transform | 旋转、缩放、偏移 | 可与基础 transform 合并处理 |

---

## 8. Enhancement Effects：增强类效果

| 效果 | 能力说明 | 兼容要点 |
|---|---|---|
| Edge Detection | Sobel 边缘检测 | 图像卷积 |
| God Rays | 从亮区生成径向或方向光束 | 需要多次采样/径向 blur |
| Local Contrast | 局部对比度增强 | 类似 clarity / local tone mapping |
| Shine | 在亮区生成闪耀高光 | 亮度阈值 + 光泽动画 |

---

## 9. Bloom / HDR / 全局后处理

Bloom 是 Scene 级效果，不同于普通图层效果，它在 Scene options 中启用，并影响整个场景。官方还提到 HDR scatter 等参数会影响发光扩散范围。

官方来源：
https://docs.wallpaperengine.io/en/scene/effects/bloom.html

### 9.1 兼容建议

建议实现一个全局后处理链，至少包括：

- Bloom enable / disable；
- 标准 Bloom strength / threshold；
- Ultra HDR Bloom 的 strength / scatter / threshold / threshold smoothing；
- 每层 HDR brightness；
- 颜色空间与 alpha 处理。

很多高质量壁纸依赖 Bloom 产生霓虹、赛博、魔法阵、发光眼睛、灯牌、星空等效果。如果 Bloom 不兼容，整体视觉会明显偏暗或缺少氛围。

---

## 10. 粒子系统能力

官方粒子系统支持复杂、可交互、可音频响应的粒子效果。粒子由大量小图像 sprite 构成，可用于火焰、雨、雪、烟、落叶、光点、魔法粒子、运动物体等。

官方来源：
https://docs.wallpaperengine.io/en/scene/particles/introduction.html

### 10.1 粒子系统核心组件

| 组件 | 作用 | 兼容要点 |
|---|---|---|
| General | 粒子纹理、基础设置、生成数量 | 需要解析粒子系统主配置 |
| Renderers | 控制粒子如何绘制 | Sprite、Sprite Trail、Rope、Rope Trail |
| Emitters | 控制粒子何时、何处、如何生成 | Sphere random、Box random、Layer image，以及 rate、instantaneous、duration、delay、periodic |
| Initializers | 设置粒子初始状态 | 初始速度、尺寸、颜色、寿命、旋转 |
| Operators | 随时间修改粒子属性 | 重力、阻尼、颜色变化、尺寸变化、噪声 |
| Child Particle Systems | 子粒子系统 | 粒子死亡或事件触发子粒子 |
| Control Points | 控制点 | 可绑定鼠标、脚本、动画或其他对象 |
| Audio Response | 跨组件能力，不是第八类粒子 component | emitter 和部分 operator 可直接响应音频，脚本也可驱动相关属性 |

### 10.2 Particle Renderer 语义

官方 Renderer 文档把 Sprite、Sprite Trail、Rope、Rope Trail 定义为不同渲染器。**Sprite Trail** 会让单个 sprite 沿当前速度方向朝向，并按速度拉伸；其理想拉伸长度为 `speed * length`，随后受作者 `Min Length` / `Max Length` 限制。它不保存粒子路径，也不等于 Rope Trail 的历史 segments；把 Sprite Trail 实现成历史绳带会产生错误轨迹、成本和生命周期语义。

官方来源：
https://docs.wallpaperengine.io/en/scene/particles/component/renderer.html

### 10.3 Sprite Sheet

官方粒子系统支持 sprite sheets，一个粒子系统内可使用序列图或多贴图表现动画粒子。

兼容实现需要支持：

- 单贴图粒子；
- 序列帧粒子；
- Sequence / Random frame；
- 按粒子寿命或作者配置推进序列；
- Additive / Translucent / Normal 混合方式。

---

## 11. Timeline 动画

Timeline animations 用于给壁纸组件的属性创建固定时长动画。官方说明 Timeline 可以驱动 Origin、Scale、效果强度、粒子数量等任意可绑定属性。

官方来源：
https://docs.wallpaperengine.io/en/scene/timeline/introduction.html

### 11.1 播放模式

| 模式 | 含义 | 兼容处理 |
|---|---|---|
| Loop | 播完后跳回开头继续播放 | `t % duration` |
| Mirror | 正放后倒放，循环往复 | ping-pong 时间 |
| Single | 播放一次并停在最后状态 | clamp 到 duration |

### 11.2 Timeline 关键能力

- 属性级关键帧；
- 多属性组合动画；
- 时间单位支持秒数和帧数；
- 起始暂停；
- 动画命名；
- 默认 Bézier 插值及左右切线控制；
- Wrap loop frames 平滑首尾；
- 事件点；
- 与 SceneScript 互操作。

官方还说明 Timeline 和 Puppet Warp 动画可加入事件。事件本身不会直接操作声音或图层，而是调用同层 SceneScript 的 `animationEvent`，再由脚本触发效果、声音、可见性或其他逻辑。

官方来源：
https://docs.wallpaperengine.io/en/scene/timeline/animationevents.html

---

## 12. Puppet Warp / 骨骼变形

Puppet Warp 用于对图像角色或局部对象做骨骼式变形动画。它可以为图片绑定骨骼网格，并通过关键帧或物理模拟实现角色呼吸、头发摆动、衣物飘动、尾巴、翅膀、触手等效果。

官方来源：
https://docs.wallpaperengine.io/en/scene/puppet-warp/introduction.html

### 12.1 需要兼容的能力

| 能力 | 说明 |
|---|---|
| 骨骼层级 | 图像绑定骨骼，骨骼有父子关系 |
| 网格变形 | 根据骨骼影响权重变形图像 |
| 关键帧动画 | 骨骼位置/旋转随时间变化 |
| Spring simulation | 骨骼弹性回弹 |
| Rigid simulation | 拖拽式模拟并保持最终位置，不等同完整刚体求解器 |
| Rope / chain | 绳状或链式结构 |
| Wind | kinematic-chain rope physics 中的风力，且需要 Puppet 已有启用动画 |
| Animation events | 动画帧事件先触发同层 SceneScript，再由脚本执行声音或图层逻辑 |

### 12.2 风险点

Puppet Warp 是兼容难点之一，因为它同时涉及：

- 骨骼求解；
- 网格蒙皮；
- 关键帧插值；
- 实时物理；
- FPS 相关行为；
- 与 SceneScript 和 Timeline 的事件交互。

---

## 13. 音频响应与媒体集成

Wallpaper Engine SceneScript 支持注册音频缓冲，读取系统音频频谱，用于音乐可视化和节拍响应。

官方来源：
https://docs.wallpaperengine.io/en/scene/scenescript/tutorial/audio.html

### 13.1 音频频谱

SceneScript 通过 `engine.registerAudioBuffers()` 选择 16、32 或 64 个频段，并取得 `left`、`right`、`average` 三组等长数组；内容随每个渲染帧自动更新。Web 壁纸的固定 64+64 布局和约 30 次/秒回调不能直接当成 SceneScript 合同。

官方来源：
https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AudioBuffers.html

兼容用途：

- 音频柱状图；
- 粒子发射量随音乐变化；
- 灯光强度随低频变化；
- 图层缩放随节拍变化；
- Shader 参数随频谱变化；
- 背景颜色随音乐变化。

### 13.2 媒体播放数据

官方支持媒体播放事件，例如：

- 播放状态；
- 歌曲标题；
- 艺术家；
- 专辑名；
- 专辑封面缩略图；
- 封面主色、次色、三色等。

官方来源：
https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/media.html

兼容建议：

- 媒体数据不可用时不能崩溃；
- 专辑封面缺失时应 fallback；
- 播放器不暴露元数据时应保持默认 UI；
- 频谱数据需要平滑处理，避免跳动过猛。

---

## 14. SceneScript 能力

SceneScript 是 Wallpaper Engine 的属性绑定型脚本环境，遵循 ECMAScript 2018，移除了 Web 相关功能，并加入壁纸专用 API。官方当前声明文件标为 v2.8；实现应以 `lib.sceneScript.d.ts` 与事件参考为合同，不能先造一个脱离 layer/effect/text/particle target 的泛化 JavaScript 执行器。

官方来源：
https://docs.wallpaperengine.io/en/scene/scenescript/introduction.html
https://docs.wallpaperengine.io/en/scene/scenescript/reference.html
https://docs.wallpaperengine.io/reference/lib.sceneScript.d.ts

SceneScript 可用于：

- 动态修改图层属性；
- 根据时间改变画面；
- 根据鼠标位置响应；
- 实现点击事件；
- 读取音频频谱；
- 读取媒体信息；
- 响应用户属性变更；
- 控制粒子、动画、灯光、Shader 参数。

### 14.1 engine 全局对象

官方 `engine` 全局对象暴露了很多运行时信息和函数。

官方来源：
https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html

重要字段和能力包括：

| 能力 | 说明 |
|---|---|
| `screenResolution` | 当前屏幕分辨率 |
| `canvasSize` | 壁纸画布尺寸 |
| `userProperties` | 用户自定义属性 |
| `timeOfDay` | 一天中的时间 |
| `frametime` | 当前帧耗时 |
| `runtime` | 壁纸运行时间 |
| desktop/mobile 判断 | 判断运行环境 |
| wallpaper/screensaver 判断 | 判断壁纸或屏保模式 |
| 横竖屏判断 | 判断屏幕方向 |
| 编辑器判断 | 判断是否在编辑器里运行 |
| `registerAudioBuffers()` | 注册音频缓冲 |
| `setTimeout` / `setInterval` | 定时器能力 |
| 用户快捷方式 | 可打开用户定义的 shortcut |

### 14.2 兼容重点

SceneScript 是高级 Scene 兼容的关键。如果播放器只实现图层和 Timeline，而不实现 SceneScript，很多壁纸会出现：

- 音频响应无效；
- 鼠标交互无效；
- 时间/时钟类壁纸失效；
- 用户设置无法实时生效；
- 图层可见性和效果参数不变化；
- 自定义 shader 参数不更新。

---

## 15. 用户属性 User Properties

官方 Scene 支持用户配置壁纸参数。

官方来源：
https://docs.wallpaperengine.io/en/scene/userproperties/overview.html

### 15.1 属性类型

| 类型 | 功能 | 兼容要点 |
|---|---|---|
| Color | 用户选择颜色 | 需要颜色 picker 与脚本绑定 |
| Slider | 数值滑块 | 支持 min / max、整数或小数模式与 default |
| Checkbox | 布尔开关 | 控制图层、效果、脚本逻辑 |
| Combo | 下拉选项 | 多选项枚举 |
| Text | 文本输入 | 常用于名字、标题、时钟格式 |
| Texture | 用户替换图片或视频 | 需要加载用户本地资源 |
| User Shortcut | 用户定义系统快捷方式 | macOS 可考虑禁用或安全降级 |
| Group | 设置分组 | 设置 UI 组织能力 |
| Display Condition | 条件显示 | 根据其他属性显示/隐藏选项 |

其中 Slider 官方区分整数与小数模式，并未给出任意 `step` 的通用运行时契约。Texture 还支持由 Checkbox / Combo 控制的 Texture Variants；官方明确说明 Texture Variants 不能由 SceneScript 切换。

官方来源：
https://docs.wallpaperengine.io/en/scene/userproperties/texturevariant.html

### 15.2 applyUserProperties

官方说明 `applyUserProperties` 会在壁纸加载时调用一次，并在用户修改属性后再次调用。首次初始化之后的回调只包含发生变化的键，脚本不能假设每次都收到完整属性表。

官方来源：
https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/applyUserProperties.html

兼容建议：

- 加载壁纸时先应用默认属性；
- 用户修改属性后触发脚本回调；
- 属性名、类型、默认值必须与项目文件保持一致；
- 缺失属性需要 fallback，不能导致脚本异常终止。

---

## 16. 灯光、反射、阴影、体积光

Wallpaper Engine Scene 支持实时灯光和反射。官方高级灯光文档列出多种光源：

- Point Light；
- Spot Light；
- Tube Light；
- Directional Light。

官方来源：
https://docs.wallpaperengine.io/en/scene/lighting/lights.html

Spot Light 可以投射纹理，纹理来源可以是图片、视频，甚至是带效果的图层。灯光也可以通过 Timeline 或 SceneScript 移动、闪烁、音频响应，甚至绑定到鼠标位置。

### 16.1 3D 阴影与体积光

官方 3D 文档说明，Scene 支持模型和灯光的 3D shadow casting，阴影支持 point、spot、directional lights。Point Light 和 Spot Light 还支持 volumetric lighting，但官方明确提示体积光性能开销很高。

官方来源：
https://docs.wallpaperengine.io/en/scene/models/lighting.html

### 16.2 兼容要点

| 能力 | 说明 |
|---|---|
| 2D PBR 贴图光照 | 2D 图层可使用 normal / metallic / roughness / reflection maps |
| Point Light | 点光源 |
| Spot Light | 聚光灯，可投射纹理 |
| Tube Light | 管状灯 |
| Directional Light | 方向光 |
| Reflection | 动态反射 |
| 3D Shadows | 模型和灯光阴影 |
| Volumetric Lighting | 体积光，高性能开销 |
| Audio-reactive Lighting | 音乐驱动灯光 |
| Cursor-bound Lighting | 鼠标驱动光源位置 |

官方当前限制每个 Scene 最多四盏实时灯；这类能力必须与性能门一起实现。

---

## 17. 3D 模型能力

Wallpaper Engine Scene 支持 3D Models，包括相机、模型动画、模型附件、模型 shader、物理模拟、灯光和阴影等能力。

官方来源：
https://docs.wallpaperengine.io/en/scene/models/camera.html

### 17.1 需要兼容的 3D 模块

| 模块 | 能力 |
|---|---|
| Camera | 3D 场景视角、投影、观察方向 |
| Model | 网格、材质、纹理、节点层级 |
| Animation | 骨骼动画播放 |
| Attachments | 其他资产挂载到模型骨骼点 |
| Physics | 骨骼或局部物理模拟 |
| Lighting | 3D 灯光、阴影、体积光 |
| Shader | 模型 shader / effect shader |

### 17.2 兼容风险

3D Scene 对播放器架构要求较高，尤其是：

- 模型格式解析；
- 材质通道兼容；
- 骨骼动画插值；
- 附件坐标空间；
- 物理模拟时间步；
- 与 2D 场景混合渲染；
- 阴影贴图和灯光一致性。

---

## 18. 自定义 Shader

官方支持创建自定义图像效果 shader。官方文档说明 shader 大体按 GLSL 编写，必要时转换成 HLSL。官方主要支持 effect shaders，并承诺保持这类 shader 的向后兼容；但不建议替换系统 shader，例如 particle shader，因为官方不保证此类替换的兼容性。

官方来源：
https://docs.wallpaperengine.io/en/scene/shader/overview.html

### 18.1 兼容要点

| 点 | 说明 |
|---|---|
| GLSL-like 输入 | 官方 shader 语法并非完全等同标准 GLSL |
| HLSL 转译 | Windows 端可能通过 DirectX 11 / HLSL 执行 |
| 自定义 effect shader | 创作者可添加自定义效果 |
| Uniform / 参数绑定 | shader 变量可绑定用户属性或脚本 |
| 平台差异 | 需要考虑 GLSL ES、Metal、HLSL 等差异 |
| 系统 shader 替换 | 官方不保证 particle shader 等替换的长期兼容性 |

### 18.2 macOS 实现建议

如果使用 Metal 渲染，建议建立：

1. 官方 shader 语义解析层；
2. GLSL-like 到 Metal Shading Language 的转译或解释层；
3. 内置 uniform 映射表；
4. 纹理采样兼容层；
5. user properties / SceneScript 到 shader 参数的绑定层；
6. shader 编译失败 fallback。

---

## 19. RGB 设备集成

Wallpaper Engine Scene 支持 RGB 硬件同步，可把壁纸颜色镜像到兼容设备，也可以指定单一图层负责 iCUE / Chroma 灯效。Composition layer 在 RGB 场景中可像摄像机一样记录其下方图层并映射到硬件。

官方来源：
https://docs.wallpaperengine.io/en/scene/rgb/introduction.html

### 19.1 兼容建议

如果 macOS 兼容播放器不计划支持 RGB 硬件，可采用降级策略：

- 正确解析 RGB 相关配置；
- 忽略硬件输出；
- 不让 RGB 字段导致项目加载失败；
- 保留 Composition 的非 RGB 渲染语义，但不能仅因 RGB 配置就假定该 layer 必须直接合入主画面；
- 后续若支持外设，再接入 OpenRGB、Razer、Corsair 等生态。

---

## 20. 推荐兼容开发优先级

本节是通用第三方播放器的能力依赖建议，不是对 Workshop 覆盖率的官方统计，也不直接代表 MyWallpaperX 当前优先级。“绝大多数”“热门”等覆盖结论必须由项目自己的隔离样本矩阵支持。

对 MyWallpaperX 当前阶段，bounded named-target capture/binding、两个严格 Blur 子图、typed frame registry/property authored-fallback、授权 PNG/JPEG `sceneTexture` 的受限静态 consumer、统一 Frame Context 第一阶段和首批 9 个 built-in 粒子纹理已经落地，不应继续写成待启动项。当前采用 coverage-first：先完成 typed dynamic target/snapshot，并横向接通 Timeline core、SceneScript core、动态文字、audio/media 输入；同时补 provider 与高命中粒子骨架，使跨系统冲突在共同合同上暴露。之后再扩通用 material、RT history 和 45 类 effect backend，最后集中做 Windows golden 精度校准。能力等级以 [官方语义与实现覆盖台账](semantics/coverage-ledger.md) 为准，具体执行顺序以 [Scene 播放能力开发计划](scene-capability-development-plan-2026-07-22.md) 为准。

### P0：基础播放可见

目标：绝大多数简单 Scene 能显示基本画面。

应实现：

- 项目文件解析；
- 图层树；
- 图片/音频/视频资产加载；
- 基础变换：位置、旋转、缩放、透明度；
- 图层顺序与混合；
- Composition/render-target 顺序、跨层纹理引用与 mask fail-closed；
- effectful/media/sceneTexture provider 与 nested/child composition；
- 常见内置 effects；
- Timeline 的 Loop / Mirror / Single；
- 用户属性默认值；
- 基础粒子渲染。

### P1：主流高质量壁纸兼容

目标：大量 Workshop 热门 Scene 可接近原始视觉。

应实现：

- SceneScript 属性绑定；
- 鼠标输入；
- 音频频谱；
- Depth Parallax；
- Bloom / HDR；
- 粒子 operators；
- 粒子 control points；
- 时间、媒体、音频与用户属性 live-value runtime；
- 用户属性变更回调。

### P2：高级壁纸兼容

目标：兼容复杂角色、音乐可视化、3D 场景。

应实现：

- 实时灯光；
- normal / metallic / roughness / reflection maps 参与 2D 光照；
- 反射；
- 3D 模型；
- 骨骼动画；
- 模型附件；
- 骨骼/布料/绳状物理；
- 媒体播放信息；
- 专辑封面；
- 专辑主色提取或传递；
- 高级粒子行为；
- Puppet Warp 基础骨骼动画。

### P3：边缘与创作者高级功能

目标：尽可能接近官方运行时。

应实现：

- 自定义 effect shader；
- shader 用户参数绑定；
- 3D 阴影；
- 体积光；
- RGB 设备集成；
- 用户快捷方式；
- 复杂 SceneScript API；
- 自定义资产与异常项目兼容。

---

## 21. 关键兼容风险清单

### 21.1 Shader 兼容

风险：

- 官方 shader 语法与标准 GLSL / Metal 不完全一致；
- Windows HLSL 与 macOS Metal 行为差异；
- 内置 uniform、sampler、blend mode 不一致会导致画面偏差。

建议：

- 先实现官方内置 shader 效果；
- 自定义 shader 做白名单或 fallback；
- 记录 shader 编译错误；
- 提供开发者调试模式。

### 21.2 SceneScript 生命周期

风险：

- 脚本初始化顺序不一致；
- `update()` 调用频率不一致；
- 用户属性回调时机不一致；
- 音频、鼠标、媒体事件缺失。

建议：

- 模拟官方事件生命周期；
- JS/ECMAScript 运行时独立沙盒；
- 严格限制危险 API；
- 所有脚本异常捕获，不影响主渲染。

### 21.3 粒子系统

风险：

- 粒子 operators 种类多；
- 控制点可能绑定脚本、鼠标、动画；
- 音频响应影响大量参数；
- 性能压力大。

建议：

- 先支持高频常见粒子类型；
- 对高级 operator 做渐进式兼容；
- 提供粒子数量上限；
- 支持低性能模式。

### 21.4 Puppet Warp / 物理

风险：

- 骨骼变形复杂；
- 物理模拟受 FPS 和时间步影响；
- 与关键帧动画混合困难。

建议：

- 先实现关键帧骨骼动画；
- 再实现 spring / rigid simulation；
- 采用固定 timestep；
- 与官方表现进行视频对比测试。

### 21.5 色彩与混合

风险：

- Bloom / HDR / alpha / 颜色空间差异会让画面观感明显不同；
- 预乘 alpha 与非预乘 alpha 混用会出现黑边或亮边；
- 叠加模式不一致会导致发光和阴影错误。

建议：

- 明确内部颜色空间；
- 统一 alpha 策略；
- 对常见 blend mode 做像素级测试；
- 建立官方截图对比工具。

### 21.6 性能与资源预算

官方建议持续关注纹理显存，并说明 DXT 纹理可能按 2 的幂补齐，物理尺寸与映射尺寸并不总相同。HDR、体积光、rope trail、碰撞和粒子预热都有显著成本。兼容播放器从早期就应记录纹理内存、粒子上限、加载时间、帧时和降级原因，而不是等功能堆满后再补性能门。

官方来源：
https://docs.wallpaperengine.io/en/scene/performance/texture.html

---

## 22. macOS 兼容播放器架构建议

### 22.1 推荐模块划分

```text
Project Loader
  ├─ Asset Resolver
  ├─ Scene Graph Builder
  ├─ User Property Parser
  └─ Compatibility Metadata

Runtime Core
  ├─ Timeline Engine
  ├─ SceneScript VM
  ├─ Event Dispatcher
  ├─ Audio / Media Bridge
  └─ Input Bridge

Render Engine
  ├─ Layer Renderer
  ├─ Effect Stack Renderer
  ├─ Particle Renderer
  ├─ Puppet Warp Renderer
  ├─ 3D Renderer
  ├─ Lighting / Shadow Renderer
  └─ Post-processing Pipeline

Platform Layer macOS
  ├─ Metal / OpenGL Backend
  ├─ Desktop Wallpaper Integration
  ├─ Audio Capture
  ├─ Media Metadata Bridge
  ├─ File Sandbox
  └─ Performance / Power Management
```

### 22.2 最小可用兼容目标

建议第一个版本优先实现：

1. 项目解析；
2. 图层与资产加载；
3. 2D 渲染；
4. 基础变换；
5. 常见 effects；
6. Timeline；
7. Bloom；
8. 用户属性默认值；
9. 基础音频频谱；
10. SceneScript 的核心生命周期。

这样可以覆盖相当一部分静态增强型和轻度动态型 Scene 壁纸。

---

## 23. 测试建议

建议建立一组基准 Scene 壁纸测试集，按能力分类：

| 测试类型 | 用例 |
|---|---|
| 基础图层 | 多图层、透明度、旋转缩放、裁切 |
| Utility / Render target | capture 范围与顺序、局部/全画布 geometry、named target、隐藏 provider、nested/child、mask、cycle 与 GPU failure fail-closed |
| Effects | 每个官方内置 effect 单独测试 |
| Timeline | loop、mirror、single、多个属性动画 |
| 粒子 | 雨、雪、火、落叶、魔法粒子、音频粒子 |
| SceneScript | 时间、鼠标、用户属性、音频、媒体事件 |
| Puppet Warp | 角色呼吸、头发摆动、物理骨骼 |
| 音频响应 | 频谱柱、低频缩放、灯光节拍 |
| 3D | 模型、骨骼动画、灯光、阴影 |
| Shader | 自定义 shader、参数绑定、fallback |
| 后处理 | Bloom、HDR、颜色空间、混合模式 |

每个测试壁纸建议保存：

- 官方 Wallpaper Engine 截图；
- macOS 播放器截图；
- 差异图；
- FPS / GPU / CPU 数据；
- 不兼容字段日志。

---

## 24. 官方文档索引

| 主题 | 链接 |
|---|---|
| Scene Overview | https://docs.wallpaperengine.io/en/scene/overview.html |
| Effects Overview | https://docs.wallpaperengine.io/en/scene/effects/overview.html |
| Bloom | https://docs.wallpaperengine.io/en/scene/effects/bloom.html |
| Foliage Sway | https://docs.wallpaperengine.io/en/scene/effects/effect/sway.html |
| Particles Introduction | https://docs.wallpaperengine.io/en/scene/particles/introduction.html |
| Particle Renderers | https://docs.wallpaperengine.io/en/scene/particles/component/renderer.html |
| Timeline Introduction | https://docs.wallpaperengine.io/en/scene/timeline/introduction.html |
| Animation Events | https://docs.wallpaperengine.io/en/scene/timeline/animationevents.html |
| Puppet Warp Introduction | https://docs.wallpaperengine.io/en/scene/puppet-warp/introduction.html |
| SceneScript Introduction | https://docs.wallpaperengine.io/en/scene/scenescript/introduction.html |
| SceneScript Audio | https://docs.wallpaperengine.io/en/scene/scenescript/tutorial/audio.html |
| SceneScript Media Event | https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/media.html |
| SceneScript IEngine | https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html |
| User Properties | https://docs.wallpaperengine.io/en/scene/userproperties/overview.html |
| Texture Variants | https://docs.wallpaperengine.io/en/scene/userproperties/texturevariant.html |
| applyUserProperties | https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/applyUserProperties.html |
| Camera Parallax | https://docs.wallpaperengine.io/en/scene/parallax/introduction.html |
| Depth Parallax | https://docs.wallpaperengine.io/en/scene/effects/effect/depthparallax.html |
| SceneScript AudioBuffers | https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AudioBuffers.html |
| Lights | https://docs.wallpaperengine.io/en/scene/lighting/lights.html |
| 2D Lighting | https://docs.wallpaperengine.io/en/scene/lighting/introduction.html |
| 3D Model Camera | https://docs.wallpaperengine.io/en/scene/models/camera.html |
| 3D Model Lighting | https://docs.wallpaperengine.io/en/scene/models/lighting.html |
| Shader Overview | https://docs.wallpaperengine.io/en/scene/shader/overview.html |
| Shader Variables | https://docs.wallpaperengine.io/en/scene/shader/variables.html |
| Effects Introduction | https://docs.wallpaperengine.io/en/scene/effects/introduction.html |
| Blend Effect | https://docs.wallpaperengine.io/en/scene/effects/effect/blend.html |
| RGB Introduction | https://docs.wallpaperengine.io/en/scene/rgb/introduction.html |
| Texture Performance | https://docs.wallpaperengine.io/en/scene/performance/texture.html |

---

## 25. 总结

Wallpaper Engine 的 Scene 壁纸本质上是一个实时渲染场景系统，而不是简单媒体播放器。它包含图层、效果栈、时间轴动画、脚本、粒子、音频响应、用户属性、灯光、3D 模型、自定义 shader 和后处理等能力。

对 MyWallpaperX 当前阶段，兼容优先级应按主构图影响和真实样本命中推进：

1. **先建立 live-value 公共底座**：typed target、同帧 snapshot、属性/Timeline/SceneScript 优先级、动态文字和 cursor/audio/media 输入；
2. **并行闭合 provider 与粒子骨架**：system/media/Texture Variants、视频、通用 material、effectful/nested/child provider，以及高频 atlas/world/child/control point/operator；
3. **再扩通用 Render Graph**：copy/swap/compose、RT history、shader/material family 和 45 类 effect backend；
4. **再集中校准视觉精度**：字体、视差、粒子、Bloom/HDR、water/lighting 与 Windows WE golden；
5. **后置高成本长尾**：Puppet Warp、3D、任意自定义 shader、RGB 与高级物理。

SceneScript、粒子、Bloom/HDR、Timeline、Puppet Warp 都是重要能力方向，但官方没有给出它们在 Workshop 热门壁纸中的覆盖率统计。具体项目仍应按隔离样本命中频率、主构图影响和可验证性排序；MyWallpaperX 当前只实现 bounded named-target、property fallback、受限 PNG/JPEG property source、11 个 L3 effect 子集、9 个确定性 built-in 粒子 key 和 Sprite Trail 等边界，不能据此宣称完整 sceneTexture、Scene、Effect、Particle 或 Wallpaper Engine 兼容。当前精确等级统一查 [覆盖台账](semantics/coverage-ledger.md)。
