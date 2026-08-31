# SceneScript 固定客户端实现层静态取证（2.8.42）

审查日期：2026-07-25；Ghidra engine 增补：2026-07-30；32/64 位交叉复核：2026-07-31；项目路线复核：2026-08-15
取证快照：Wallpaper Engine 2.8.42 随包文件
审查方式：静态检查

> 本文只覆盖在线文档未公开、但客户端取证记录到的实现层事实。`lib.sceneScript.d.ts` 的 API 表面（接口、签名、生命周期钩子）已在 [SceneScript API 覆盖表](scenescript-api-coverage.md) 建立，本文不重复。
>
> 本文回答的是 API 覆盖表回答不了的问题：**声明背后的实际数值行为、宿主与 VM 的桥接协议、以及编辑器声明的 authoring/type surface**。
>
> VM 技术选型与准入由[技术栈与架构路线边界](../../architecture/technology-stack-boundaries.md#5-scenescript-路线)和[兼容运行时架构](../runtime-architecture.md)统一约束。MyWallpaperX 的现役目标是 QuickJS-NG per-scene runtime/context + Swift typed host bridge；JavaScriptCore 只保留为历史候选和对照。官方公开合同只确认 SceneScript 基于 ECMAScript 并使用 wallpaper host API，不公开 QuickJS-NG、MyWallpaperX owner/预算策略或内部帧提交协议；下文 V8、record、timer 和 teardown 结论均是 2.8.42 固定客户端静态观察。
>
> **文档角色：`official-client-static-observation / research-context-only`。** 本页不是稳定实现合同，不得直接交给 implementation agent，也不授权照译其中的客户端常量、公式、布局、record 或顺序。研究任务只能按[官方客户端行为研究工作流](official-client-behavior-research-workflow.md)把当前有界问题压缩成经审查的中性行为合同；fresh implementation context 只接收该合同、项目自有 fixture 与官方黑盒协议。产品策略、失败边界和验收门只以本文链接的现役合同为准。

## 1. 为什么需要这份文档

[资料来源与证据索引](source-index.md) 已收录在线版 `lib.sceneScript.d.ts`。但声明文件只给类型，不给行为：

- `equals()` 声明返回 `Boolean`，但**判等用什么容差**，声明里没有；
- `new Vec3(x)` 声明接受多种重载，但**标量如何广播到 y/z**，声明里没有；
- 用户属性怎么跨 native/JS 边界传递、怎么反序列化成 `Vec3`，声明里完全没有；
- SceneScript 自定义属性 UI（slider/combo/color）的构建协议，声明里**一个字都没有**。

这些都是行为 conformance test 和后续视觉对齐需要的输入。客户端取证提供的是数值、桥接与生命周期规格，不单独证明最终像素等价。

## 2. 证据来源与等级

| 代号 | 文件 | 规模 | 等级 |
|---|---|---:|:---:|
| `JS` | `assets/scripts/jsclasses/baseclasses.js` | 1456 行 | A |
| `JM` | `assets/scripts/jsmodules/{wemath,wevector,wecolor}.js` | 13/15/47 行 | A |
| `DT` | `ui/dist/monaco/autocomplete/lib.sceneScript.d.ts` | 2570 行 | A |
| `LB` | `ui/dist/monaco/autocomplete/lib.es*.d.ts` 清单 | 23 个文件 | A |
| `GB` | 32/64 位 `wallpaper` + `scenescript` 的 Ghidra 有界静态路径 | module/engine/event/timer/teardown 与跨 ABI 结构邻域 | B |

等级沿用 [Windows 官方客户端取证记录](../../history/scene/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md)：A = 客户端快照中的结构化文件直接确认。

### 2.1 与当前项目状态的关系

本文把结构化随包文件和 Ghidra 证据整理为**研究候选观察**，不是待实现合同，也不维护 MyWallpaperX 的能力等级、route 或产品 owner 快照。当前能力只查[SceneScript API 覆盖表](scenescript-api-coverage.md)，当前运行深度与失败边界只查[运行证据索引](runtime-evidence-index.md)，现役顺序只查[唯一现役路线](../scene-compatibility-roadmap.md)。候选观察必须经官方黑盒区分、去除静态实现细节并通过交接审查，才能形成新的中性行为合同；需要新的官方非公开行为时，必须由独立研究任务产生该合同。

## 3. 编辑器 authoring/type surface（`LB`）

以下 Monaco 自动补全 lib 清单只描述固定官方客户端快照中的 authoring/type surface；它不声明 MyWallpaperX 当前 VM 能力、产品 route 或运行证据：

| 随包 lib 文件 | 含义 |
|---|---|
| `lib.es5.d.ts` | 基线 |
| `lib.es2015.{core,collection,generator,iterable,promise,proxy,reflect,symbol,symbol.wellknown}.d.ts` | ES2015 全量 |
| `lib.es2016.array.include.d.ts` | ES2016 |
| `lib.es2017.{intl,object,sharedmemory,string,typedarrays}.d.ts` | ES2017 |
| `lib.es2018.{asynciterable,intl,promise,regexp}.d.ts` | ES2018 |
| `lib.es2019.{array,string,symbol}.d.ts` | ES2019 |

可直接确认的两条 authoring 边界：

1. **随包类型库到 ES2019 为止**。没有任何 `lib.es2020.*` 及以上，因此官方编辑器不向作者承诺 ES2020+ 类型/补全表面。
2. **无 `lib.dom.d.ts`**。官方编辑器不向 SceneScript 作者暴露 DOM 类型；同样缺席的还有 Node 与 WebWorker lib。

声明文件首行是 `/// <reference no-default-lib="true"/>`，即官方显式关闭默认 lib，只挂上述白名单。

**证据边界**：Monaco type lib 不是 runtime syntax probe。它不能单独证明官方 VM 必然接受全部 ES2019 语法，也不能证明 `??`、`?.`、`BigInt`、`globalThis` 在 runtime 必然失败。它只提供一个中性评审问题：随包 ES2019 authoring surface 中哪些语法和 globals 能由官方黑盒正反门确认。QuickJS-NG、module loader、global allowlist 和产品准入仍只由现役合同决定，不能因选用了真实 ECMAScript VM 就直接记为兼容。

## 4. 宿主 ↔ VM 桥接协议（`JS`）

`baseclasses.js` 末尾（1375-1456 行）是宿主注入层。这部分**不在 `.d.ts` 中**，是本地独有证据。

### 4.1 prototype 导出

文件在顶层 `this` 上导出 5 个 prototype 引用，键名为 `_Vec2`、`_Vec3`、`_Vec4`、`_Mat3`、`_Mat4`。

顶层 `this` 可用（而非 `undefined`），说明该随包文件在观察到的包装上下文中获得了宿主对象；是否直接脚本求值、是否另有 wrapper 以及严格模式边界仍属于 C 级解释。用户模块源码则明确使用 `'use strict'` 与 ES `export`。

推断（等级 C）：原生侧可能在构造向量/矩阵时挂这些 prototype，以避免每次跨边界重新构造 JS 对象。可提交给黑盒研究的问题只有 prototype identity 是否在同一 scene/context 内稳定、跨 scene 是否隔离；本静态观察不授权 QuickJS-NG bridge 的 root 持有方式、constructor/handle 形态或具体 C API。

### 4.2 token 句柄机制

`IModelData` 定义在宿主注入段而非主体类区，其 `toConfigString()` 返回实例上的 `__modelDataToken` 字段。

即：**原生资源对象跨边界时不传结构，只传 token 字符串**。序列化时 token 就是该对象的配置表示。

`IModelData` 的静态常量（`DT` 未给出这些值）：

| 常量 | 值 |
|---|---|
| `POSITION` | `'position'` |
| `NORMAL` | `'normal'` |
| `UV` | `'uv'` |
| `TANGENT_SIGNED` | `'tangentSigned'` |
| `COLOR` | `'color'` |

### 4.3 `_Internal` 三个宿主回调

宿主在 `this._Internal` 上挂三个函数，均由原生侧调用：

| 函数 | 入参 | 行为合同 |
|---|---|---|
| `updateScriptProperties(script, vars)` | `vars` 是 **JSON 字符串** | 解析后逐 key 写入 `script.scriptProperties`。**只更新已存在的 key**（`hasOwnProperty` 守卫，未声明的 key 静默丢弃）。若目标现值是 `Vec3` 实例，则用新值**重新构造** `Vec3`；否则直接赋值 |
| `convertUserProperties(p)` | `p` 是 **JSON 字符串** | 按每项的 `type` 字段做类型映射，返回普通对象 |
| `stringifyConfig(obj)` | 任意对象 | `JSON.stringify` + replacer；replacer 对任何**具有 `toConfigString` 方法**的值调用之，其余原样返回 |

`convertUserProperties` 的类型映射表：

| `type` | 输出 |
|---|---|
| `color` | `Vec3`（由字符串值构造，见 5.1） |
| `usershortcut` | 对象 `{isbound, commandtype, file}`，**仅这三个字段** |
| 其他全部 | `value` 原值 |

**中性交接候选**：可用官方黑盒区分 `usershortcut` 是否只投影三字段、未声明 key 是否静默丢弃，以及向量更新是否产生新对象。这些静态观察不构成 `SceneDynamicSnapshot` 或用户属性桥的实现依据；只有通过交接评审后写入现役行为合同的结论才可约束产品。

## 5. 数值行为合同（`JS`）

### 5.1 构造分派

`Vec2`/`Vec3`/`Vec4` 的构造函数按入参类型分派。以 `Vec3` 为例（`Vec2`/`Vec4` 同构）：

| 入参形态 | 结果 |
|---|---|
| `string` | 按**单个空格**切分，各分量 `parseFloat`。分量不足时为 `NaN` |
| `Vec3` 实例 | 逐分量拷贝 |
| `Vec2` 实例 | `(v.x, v.y, 0)` |
| `(x)` 单标量 | `(x, x, x)` —— 广播 |
| `(x, y)` | `(x, y, 0)` |
| `(x, y, z)` | `(x, y, z)` |
| 无参 | `(0, 0, 0)` |

标量广播规则不是平凡的「缺省补 0」，判定链是：`z` 为 number 则取 `z`；否则若 `y` 为 number 则 `z = 0`；否则 `z = x`。`Vec2` 对应规则为 `y` 为 number 则取 `y`，否则 `y = x`。

这条需要进入兼容测试：`new Vec3(2)` 得到 `(2,2,2)` 而非 `(2,0,0)`；本地 corpus 没有提供其在第三方作者脚本中的使用频率。

### 5.2 判等容差

全部 `equals()` 使用同一常量：

```
_Epsilon = 0.00001
```

`Vec2`/`Vec3`/`Vec4`：逐分量 `Math.abs(a-b) < _Epsilon`，全部满足才为真。`Vec2.equals` 还先做 `instanceof Vec2` 检查，非同类型直接返回 `false`。

`Mat3`/`Mat4`：遍历 `m[]`，任一元素 `Math.abs(diff) >= _Epsilon` 即返回 `false`。

注意是**严格小于** `_Epsilon` 为相等、**大于等于**为不等。边界值 `0.00001` 本身判为不等。

### 5.3 序列化格式

`toString()` 一律为**空格分隔的十进制**，无括号无逗号：

| 类型 | 格式 | 分量数 |
|---|---|---:|
| `Vec2` | `x y` | 2 |
| `Vec3` | `x y z` | 3 |
| `Vec4` | `x y z w` | 4 |
| `Mat3` | `m0 … m8` | 9 |
| `Mat4` | `m0 … m15` | 16 |

`toConfigString()` 在这 5 个类中**全部等价于 `toString()`**，但它是独立方法名，且是 `stringifyConfig` replacer 的识别依据。

这个格式与 5.1 的字符串构造互为逆运算，也就是 `scene.json` 中向量字面量的格式。

### 5.4 矩阵布局与 compose

Mat3/Mat4 的乘法索引和向量变换直接确认其数组为 column-major 语义：

| 合同 | Mat3 | Mat4 |
|---|---|---|
| translation index | `m[6],m[7]` | `m[12],m[13],m[14]` |
| basis | 每 3 项一列 | 每 4 项一列 |
| compose | translation -> rotation -> scale | translation -> Euler rotation -> scale |
| angle unit | degree | degree |

`Mat4.fromEuler` 接受 Vec3 或 x/y/z；`extractEuler()` 和 `decompose().rotation` 也返回 degree。可交接的行为问题是序列化数组的 basis/translation 方向和角度单位在官方黑盒往返中是否保持；项目矩阵布局与 bridge 单位只由审定后的现役合同决定。

### 5.5 实现与声明的差异

`JS` 与 `DT` 逐类比对结果：

| 类 | JS 成员 | d.ts 成员 | 差异 |
|---|---:|---:|---|
| `Vec2` | 36 | 37 | JS 多 `toConfigString`；d.ts 多数据成员 `x,y` |
| `Vec3` | 37 | 39 | JS 多 `toConfigString`；d.ts 多 `x,y,z` |
| `Vec4` | 32 | 35 | JS 多 `toConfigString`；d.ts 多 `x,y,z,w` |
| `Mat3` | 29 | 26 | JS 多 `forward`/`right`/`up`/`toConfigString` |
| `Mat4` | 31 | 31 | JS 多 `toConfigString`；d.ts 多 `m` |
| `MediaPlaybackEvent` | 3 | 1 | JS 是三个静态常量；d.ts 只声明实例成员 `state` |
| `CameraTransforms` | 0 | 4 | **JS 无实现** |

可确认的三点：

1. `toConfigString` 是这些类在固定随包脚本中共用的**未公开序列化入口**；`stringifyConfig` 在该脚本内依赖它处理向量。它是否属于作者可观察兼容表面、是否必须由 host bridge 暴露，仍需公开合同或黑盒用例确认，本观察不直接规定项目桥接层。
2. `Mat3` 实际具备 `forward`/`right`/`up` 方向向量访问，官方只在 `Mat4` 声明了它们。属于未公开但存在的能力。
3. `CameraTransforms` 在 JS 层无实现，是**真正由引擎原生提供**的类。其余 Vec/Mat 全部有 JS 实现。

`MediaPlaybackEvent` 的静态枚举值（`DT` 未给出）：

| 常量 | 值 |
|---|---:|
| `PLAYBACK_STOPPED` | 0 |
| `PLAYBACK_PLAYING` | 1 |
| `PLAYBACK_PAUSED` | 2 |

## 6. 自定义属性 UI 协议：`createScriptProperties`（`JS`）

**`d.ts` 中完全未声明，[SceneScript API 覆盖表](scenescript-api-coverage.md) 零覆盖。** 这是本地独有的完整协议。

宿主在全局注入 `createScriptProperties()`，返回一个链式 builder：

| 方法 | 写入的默认值 | `_config` 附加字段 |
|---|---|---|
| `addSlider(options)` | `options.value` | `min`、`max`、`mode`（`options.integer === true` 时为 `'int'`，否则 `undefined`） |
| `addCheckbox(options)` | `options.value` | 无 |
| `addText(options)` | `options.value` | 无 |
| `addCombo(options)` | **`options.options[0].value`** | `options`（整个选项数组）、`mode: 'combo'` |
| `addColor(options)` | `options.value` | 无 |
| `finish()` | — | 返回累积的 vars 对象 |

**双键命名协议**：每次 `addXxx` 在结果对象中写入**两个** key：

- `options.name` → 属性当前值
- `options.name + '_config'` → 元数据对象

`_config` 的公共字段为 `{ order, label }`，`order` 是从 0 开始、每次 `addXxx` 调用后自增的整数，即**声明顺序即 UI 顺序**。

三条易漏细节：

1. combo 的默认值取**第一个选项**的 `value`，不取 `options.value`；
2. slider 的 `mode` 在非整数时显式为 `undefined`（key 存在，值为 undefined），这影响 `JSON.stringify` 后的形态；
3. 全部 `addXxx` 返回 builder 自身，支持链式；`finish()` 才返回数据。

**中性交接候选**：这是当前随包证据中观察到的 SceneScript 自定义属性声明通路。黑盒研究可区分双键命名是否都可见、`_config.order` 是否影响作者可观察顺序；是否还存在 native/editor 私有入口不由本文件证明，产品支持范围只由现役合同决定。

同一注入段还把全局 `shared` 初始化为空对象。它确认初始 identity，但不确认多脚本、跨 layer、跨 surface 或壁纸切换时的共享/销毁范围；这些生命周期仍需运行门。当前launch-origin能力只静态证明作者`shared=false` initializer及master/follower cohort，再编译为项目typed scene/host state；它不是这里所述mutable JavaScript `shared` object的实现。

## 7. 官方模块实现级语义（`JM`）

三个模块在 [SceneScript API 覆盖表](scenescript-api-coverage.md) 中已有签名级记录。本地源码补充实现级事实：

### 7.1 模块解析规则

`wevector.js` 首行 `import * as WEMath from 'WEMath'`。可确认：

- 模块名是**裸标识符**，无路径、无 `./` 前缀、无 `.js` 扩展名；
- 模块名**大小写与文件名不一致**（文件 `wemath.js`，模块名 `WEMath`），因此存在独立的模块名注册表，不是按文件名解析；
- 模块之间可互相 import（`WEVector` 依赖 `WEMath`）；
- 三个模块均声明 `'use strict'`，均用 ES `export`。

模块内直接使用 `Vec2`/`Vec3` 而**不 import** —— 印证 4.1：Vec/Mat 是预注入全局，不是模块导出。

### 7.2 `WEMath`

| 导出 | 类型 | 行为 |
|---|---|---|
| `deg2rad` | `let` | `Math.PI / 180` |
| `rad2deg` | `let` | `180 / Math.PI` |
| `smoothStep(min, max, v)` | function | 先 `clamp((v-min)/(max-min), 0, 1)`，再 `x*x*(3-2*x)`。标准 Hermite |
| `mix(a, b, v)` | function | `a+(b-a)*v`，**不 clamp** `v` |

`deg2rad`/`rad2deg` 导出为 `let` 而非 `const` —— 可被作者脚本重新赋值。

### 7.3 `WEVector`

| 导出 | 行为 |
|---|---|
| `angleVector2(angle)` | 入参**角度制**，返回 `Vec2(cos, sin)` |
| `vectorAngle2(direction)` | `Math.atan2(y, x)`，返回**角度制** |

两者的角度单位都是度不是弧度，且互为逆运算。

### 7.4 `WEColor`

| 导出 | 行为 |
|---|---|
| `rgb2hsv(v)` | 入参 `Vec3`，返回 `Vec3(h,s,v)`，**三分量均归一化到 [0,1]**（h 不是 0-360） |
| `hsv2rgb(v)` | 逆运算，h 取 [0,1] |
| `normalizeColor(c)` | 各分量 `/255` |
| `expandColor(c)` | 各分量 `*255` |

`rgb2hsv` 在 `max === 0` 时 `s = 0`；`max === min` 时 `h = 0`。色相计算按 max 分支走 6 分区并整体 `/(6*d)`。

**注意与 shader 侧的差异**：`assets/shaders/common.h` 中同名的 `rgb2hsv`/`hsv2rgb` 是**另一套实现**（GLSL 无分支版，用 `1e-10` 防除零）。JS 侧与 shader 侧算法不同，数值在边界处不保证逐位一致。跨侧比对时不能互为 golden。

## 8. Engine 与宿主生命周期静态互证（`GB`）

本节只记录高层行为合同，不保存地址、伪代码、函数体、字节或客户端算法表达；静态 executable 证据也不改变 Generic VM/Event 的 `L0` 等级。

### 8.1 Module、engine 与预算边界

- 主程序要求 SceneScript module 返回精确匹配的版本身份；缺导出或版本不符时不创建 engine，属于 fail-closed。
- module `Init`/`Shutdown` 是进程级引用计数边界；每个 engine 另有独立 isolate、script/timer/property/audio 表与 host bridge。
- 每个 engine 有独立 watchdog。连续执行长时间不退出会使该实例进入永久中断并跳过后续 event/timer，不是“下一帧自动恢复”。
- event 与 timer callback 会累计真实执行耗时，宿主可读取并清零。这只表明客户端存在耗时观测点；项目预算与 watchdog policy 只见[现役 SceneScript 目标合同](scenescript-api-coverage.md#11-mywallpaperx-v2-目标运行时合同)，客户端阈值不得由本页转成实现参数。

2026-07-31 的独立 32/64 位 Ghidra 交叉进一步确认：两份 DLL 共同公开上述四个宿主入口；`thisLayer`、`engine`、`localStorage`、`registerAudioBuffers`、`setTimeout` 与 `setInterval` 在两个架构中形成相同的共址集合，并可达独立 worker 与同步参与者。它支持这些能力属于 per-engine owner bridge，而不是 64 位特例或互不相关的全局 helper；函数数、xref、TLS/异常导出与 CRT 细节不同，因此不证明逐函数或 ABI 等价。完整输入身份和方法见 [官方客户端运行机制静态取证](client-runtime-static-forensics.md)。

### 8.2 Event、effective time、timer 与 audio tick

- 每个 script record 固定保存 19 个 event slot：init/update/resize/destroy、用户属性、通用设置、animation、六个 cursor 与五个 media。
- 每个 slot 有独立存在/禁用位；单一 handler 被禁用不等于停掉整份脚本。
- init、update 与 animationEvent 的返回值进入绑定 property writeback；其他 event 只产生副作用。
- 主程序在恢复出的 frame 路径中先派发已排队的 media 与 animation 事件，再调用 engine tick；tick 内先刷新 audio arrays、后遍历 timer，tick 返回后才派发普通 `update`。
- scene 时间先后经过 FPS/pause admission、smoothed time scale、authored playback scale 与 clamp，输出 effective delta。`frametime`、`runtime` 累计、engine tick 与 timer 都使用这一个时间域；具体 smoothing/clamp 数值不是跨平台兼容常量。
- pause 渐变阶段随 effective delta 同步减速；完全暂停后不 tick、不累计。恢复时先重置性能计时基线，暂停 wall time 不进入首帧，也不产生 timer catch-up。`timeOfDay` 每帧采样本地 wall clock，与累计 runtime 分离。
- `registerAudioBuffers` 只允许 global phase，只接受 16/32/64，默认 16；首次注册建立三档 left/right/average backing arrays，后续 tick 原地刷新，VM object/array identity 跨帧稳定。
- timer 属于 owner。scheduler 每轮先复制 timer pointer snapshot，因此回调中新建 timer 不会同轮执行，取消/删除不破坏当前遍历。one-shot 执行后按 identity 删除；interval 每帧至多执行一次，执行后从完整周期重新计时，不追补也不累积 overshoot；owner removal 逐条释放 timer。
- 普通 `update` 则直接 live 遍历 script-record 双向链表。新 record 尾插且同步执行 `init`：cursor/media/timer 阶段创建的 owner 会获得同帧 `update`，`update` callback 创建的 owner 会在本轮后段首次 `update`。destroy 只排队，pending destroy 在普通 `update` 后 drain；destroy callback 创建的 owner 已错过本轮 `update`。
- DLL 内部虽注册 `clearTimeout` 名称，公开取消合同仍以注册函数返回的 cancel function 为准，不能据此扩张 v2.8 公共 API。

### 8.3 Cursor hit、传播与状态失效

- cursor 先使用当前帧候选快照遍历，再对 `solid=true` 的 layer 调用 native hit-box/detail virtual；这不是公开 SceneScript `cursorHitTest` hook，v2.8 声明也没有该成员。
- layer flag word 中 `visible=bit 0`、`solid=bit 13`、`disablepropagation=bit 14`。`visible=false` 不会让 solid layer 退出 hit test；隐藏 solid 仍可接收 enter/move/down/up/click 并保留 hover 与 pressed/capture。
- `disablepropagation` 只有当前 layer 与祖先都 effective-visible 时才阻断后续候选。因此隐藏 solid 可以作为透明交互区，但不会遮断后续命中对象。
- visible setter 不清理输入状态。native object 真正销毁时才静默清除 hover 和 pressed/capture identity，不补发 leave/up/click；click 必须由仍有效的同一 pressed identity 完成 down/up 配对。
- `input.cursorWorldPosition` 与 `cursorScreenPosition` 共用 scene 的 cursor pixel snapshot；前者经当前 view/projection 逆变换为 Vec3并可按 2D policy 把 z 置 0，后者按 canvas/viewport scale 与 Y-axis policy 输出像素坐标。`cursorLeftDown` 固定查询 left-button identity并读取当前 input bool。三个 getter 都拒绝 global phase。
- `CursorEvent` 在 dispatch 前把 world/local/hit-box 构造成独立 snapshot，不应在 JS callback 中再次读取轮询 getter来拼事件。
- 可交接的黑盒区分问题包括 visible、solid、parent visibility、propagation、hover/capture 与销毁失效；event-local/puppet 坐标、候选前后顺序和多按钮仍缺动态结果。本页不直接生成项目 fixture 或验收门。

### 8.4 Asset、dynamic layer、model data 与 storage

- `registerAsset` 只允许 global phase，按传入路径去重；重复注册不会改写首次 precache 选择。VM 边界可得到路径值。项目公共 API 是否以及如何使用 opaque `IAssetHandle` 只由[现役 SceneScript 目标合同](scenescript-api-coverage.md#11-mywallpaperx-v2-目标运行时合同)规定，不由该静态路径授权。
- `createLayer` 同步请求宿主并立即取得 native identity；wrapper cache 按该 identity 复用 handle。bridge-managed identity vector 最多 2048 项：2047 项时可再创建，已有 2048 项时返回空值；不能假定该容器只统计动态 layer。
- `getLayerIndex` 对未知 identity 返回 `-1`，`sortLayer` 对未知 identity 返回失败；native sort 把超过当前长度的 index 夹到尾部，负数是否在 VM boundary 被拒绝仍待闭合。sort 只改变 native/render topology，不改变 script-record 注册顺序。
- `destroyLayer` 同步返回请求状态，实际 topology removal 在普通 `update` 后的 pending-destroy drain 执行。destroy callback 创建的新 layer 已加入 native/render registry；若满足类型与 effective-visible 门，可能在本帧 render preparation 中出现，但到下一帧才第一次普通 `update`。
- `setParent` 不是 pending-destroy mutation：宿主同步解析 parent identity 与可选 attachment name/index，从旧 parent 的 child vector 摘除，再切换 parent/attachment。`adjustTransforms=true` 以旧 world transform 和新 parent/attachment transform 重算 local origin/angles/scale；false 直接切换关系。相同 parent+attachment 是 no-op success，`getParent` 读取当前 identity，`getChildren` 返回调用时 child vector snapshot。
- self-parent 或 native flag/child complexity guard 失败时，旧 parent 已被摘除且不会自动回滚；宿主保持 unparented 并报告 invalid configuration。可提交评审的问题是产品安全策略是否选择事务式提交，以及若选择后如何在官方对照中标记差异；该策略只由现役合同授权。descendant cycle、缺失 identity/attachment 与 guard 的准确公共含义仍需黑盒负向观察。
- 每个新 layer wrapper 会向 native object 注册 lifetime callback。native object 真正销毁时 callback 清除 identity/index 两张 wrapper 索引并释放 wrapper；这给失效 handle 提供了明确通知边界。
- `getInitialLayerConfig` 是宿主配置 serialize 后再 parse 得到的 detached object，不是 live alias。
- `createModelData` 返回 tokenized handle；`applyData` 与 `replaceData` 共用 native bridge，以 mode 区分，update phase 拒绝 `replaceData`。buffer 增长、非 dynamic 更新、shape/buffer 增删、material/vertex format 改变及 index/layout 不兼容分别 fail closed。仍被 layer 引用的 model-data destroy 请求延迟到引用解除。
- local storage 的四个操作都拒绝 global evaluation phase。默认 screen，只有字符串精确等于 `global` 才进入 global 域；key 必须是 string，`set(key, undefined)` 转 delete。value 经 VM 序列化并加版本 envelope；get 验证或反序列化失败返回 `undefined`，delete/clear 返回宿主状态。

官方 live traversal 允许 `update` callback 持续创建 owner 并继续延长同一轮，这形成一个可观察的无界工作量风险。项目预算、延后准入和差异标记只见[现役 SceneScript 目标合同](scenescript-api-coverage.md#11-mywallpaperx-v2-目标运行时合同)与[兼容运行时架构](../runtime-architecture.md)；本静态观察仅提供预算触发和同帧可见性的黑盒对照问题。

这些结论不闭合 asset canonicalization/precache 时点、负 index VM 行为、model-data 精确引用计数，也不闭合 storage namespace/quota/原子性/跨重启行为。

### 8.5 Camera、material、particle、video 与 animation handle

- `getCameraTransforms` / `setCameraTransforms` 都拒绝 global phase。DTO 是 `eye`、`center`、`up` 三个 Vec3 与 `zoom`；getter 返回 scene 保存的 base record，setter 将缺失成员保留为空指示，只更新实际提供的成员。构造默认为 `eye=(2,2,2)`、`center=(0,0,0)`、`up=(0,1,0)`、`zoom=1`；无 authored camera 的正交 fallback 使用 `eye=(0,0,0)`、`center=(0,0,-1)`、`up=(0,1,0)`，authored camera 覆盖同一 record。
- `setMaterialProperty` 按存储顺序遍历 effect 的 material instance records。每条 record 用 property name 查询自己的 metadata，再执行 scalar/Vec2/Vec3/Vec4 typed write；scalar 可由 metadata 控制 int/float 转换，单位 metadata 可触发 degree-to-radian。某个 instance 缺字段或类型不兼容只使它自身 no-op。
- `executeMaterialFunction` 对缺失名称或空 descriptor no-op；否则按 descriptor-defined ordered record set 逐条切换 active material/state、立即执行 function、再恢复原状态。它不是无序广播或跨帧队列；descriptor 到 authored pass 的完整映射仍待闭合。
- `emitParticles()` 与 count 0 规范为 1，正整数原样转交，负数 no-op；调用以零时间偏移进入正常 particle runtime 共用的 emitter/default-channel/initializer dispatcher。最终 GPU buffer 是否同 draw 可见仍需自有 fixture。
- video provider 缺失时 method no-op、getter 返回默认值。`play` 在 ended 时先 seek 0，`pause` 只暂停，`stop` 暂停并 seek 0；`isPlaying` 同时要求 active/playing 且未 ended。非 loop 以 arm 后首次 ended 为一次性边沿，loop 以 current time 小于上一帧识别自然回绕；主动 seek 清除待派发状态。ended callback 在 owner 内有序保存，经 scene engine batch 派发，owner teardown 后不得存活。底层媒体 controller 登记在宿主 manager-owned registry 中，并把 requested-playing、实际 running 与 frame-ready/dirty 分开；析构先停并等待 worker、退注册，再释放 output/media/GPU。该结构支持 host-owned provider generation，但 registry pump 顺序和 device reset 后 retained play/rate/loop/seek intent 的恢复 owner 仍未验证。
- `playSingleAnimation` 复用普通 animation-layer 创建、验证和 `autosort` / `index` 插入路径，只在成功创建后追加 one-shot marker。evaluator 到达 end 的 frame 先派发全部 ended callbacks，第二遍遍历才移除 layer，因此 callback 期间 handle 仍有效。显式 destroy 接受 handle、非负 index 或 name；name 删除全部同名项，无效输入 no-op/false，显式 destroy 不生成自然 ended。

这些结论只定义自有 host bridge 的类型、顺序与生命周期 fixture，不改变 API 覆盖等级，也不闭合视频像素、动画 blend/root-motion、粒子轨迹或 material function 的视觉结果。

### 8.6 Property return 与反射

property return 通过集中式 typed conversion 写回 number、bool、string 和 vector；标量可广播到向量，错类型、不完整向量或非法数值不得覆盖旧值。原生 property reflection 还保留 name、label、顺序、类型、数值范围、bool、归一化颜色、文本和 combo option。带单位字段的精确转换与全部异常边界仍需项目自有 fixture。

### 8.7 Destroy 与 teardown

- engine teardown 会先停止/唤醒 watchdog 并等待监督线程退出，再释放 script record、timer、音频注册、host wrapper 与 isolate。
- DLL 的 record removal / engine 析构不会替宿主调用用户 `destroy`。
- 主程序的公共 owner removal path 在同一 engine batch 中先派发存在的 `destroy`，再删除 engine script record，最后释放 host record。多类 layer/object owner 都调用这一路径。
- scene teardown 先释放这些 owner，再释放 scene engine；因此恢复出的完整顺序是 `destroy -> engine record removal -> host record release -> all owners complete -> engine release`。
- 当前静态路径只观察到同一 owner 进入一次公共 removal path，不能单独证明所有重入条件下的 exactly-once。可交接的负向问题包括 destroy 内自取消 timer、跨 handle 访问和异常；项目的 exactly-once 安全合同及验收门只见现役合同。

## 9. 已撤权的 2026-08-15 项目目标草案

本节是旧研究文档中混入的项目目标草案，现已撤销规范权。现役目标只见[SceneScript API 覆盖表 §1.1](scenescript-api-coverage.md#11-mywallpaperx-v2-目标运行时合同)和[兼容运行时架构](../runtime-architecture.md)；implementation agent 不得从本节取得顺序、常量、默认值或实现授权。本节以下内容统一按“旧草案曾记录的候选设计”理解，仅保留为起草取舍的研究 provenance。

### 9.1 Runtime、context 与 owner

- 旧草案曾为每个 scene execution domain 分配独立的 QuickJS-NG runtime/context、module registry、global `shared`、job queue 和预算账户，并假定不同 scene、reload generation 与测试 fixture 不共享 JS object 或 native handle；多 surface 的共享/复制与隔离当时被列为待定义项。
- 旧草案曾把 scene VM 设为 runtime/context owner，并给 scene、layer、effect、property binding 或动态对象脚本各配 typed script owner record；record 候选字段包括 source identity、phase、event/timer/job、mutation buffer 和 teardown state。
- 旧草案曾提出 typed opaque handle 形状 `{domain, ownerIdentity, objectIdentity, generation, capability}`，并把 domain、generation、owner、phase 与 capability 重验列为候选安全策略；这不是静态客户端观察，也不规定现役 handle 形态。
- 旧草案曾提出不向默认 global allowlist 暴露 DOM、Node、WebWorker、文件、网络或任意 native module，并限制裸模块名、路径、dynamic native load 与跨 scene import；现役 allowlist 只由上文链接的项目合同决定。

### 9.2 帧执行与 mutation commit

旧草案记录的候选产品链为：

```text
immutable Swift frame snapshot
  -> queued lifecycle/media/animation/input events
  -> due timers and bounded pending jobs
  -> owner init/update callback
  -> typed return + owner-local mutation buffer
  -> validate identity/generation/type/finite/conflict
  -> one ordered Swift mutation transaction
  -> next-frame snapshot / Program / graph consumer
```

- 旧草案把 owner `init` exactly-once、immutable frame snapshot、owner-local mutation buffer 与 callback 不直接改写正在遍历状态列为候选约束。
- 旧草案拟将 2.8.42 event/timer 静态顺序转成 fixture，并把未确认顺序、同帧可见性和 callback 重入标为项目 policy；这些内容尚未经过中性交接与黑盒确认。
- 旧草案描述了 callback 后按作者顺序、owner identity 和 mutation 类别做 typed validation/conflict resolution，再在帧边界提交 surface transaction 的候选方案，以及 value/resource/program/topology 的不同失效半径。
- 旧草案描述了 teardown、reload、pause 或 generation 变化时撤销旧 pending 工作，并让 terminal compositor 只消费已提交 Swift 状态的候选方案。

### 9.3 预算、故障隔离与销毁

- 旧草案列出 heap/stack、callback deadline、累计 CPU、callback、timer、job、owner mutation 和动态 identity 等预算维度，并设想按最小 owner 隔离无限循环、job 风暴、递归、OOM 与超限。
- 旧草案列出 exception、unhandled rejection、缺 API、错类型、NaN/Inf 与 stale handle 的 typed diagnostic 字段，以及不波及主 App 和无关可见内容的候选失败半径。
- 旧草案记录了 reload 建立新 generation/runtime/context、成功后撤销旧 owner，以及失败时保留已提交状态或无脚本 authored fallback 的候选切换策略。
- 旧草案记录了停止 dispatch、interrupt callback、取消 pending 工作、尝试 owner `destroy`、撤销 handle、释放 context/runtime 的候选 teardown 顺序和零残留检查。

旧草案曾把一个真实 property owner 的 source、`init/update`、mutation commit 与 teardown 作为第一门，把 event/timer 作为后续复用候选。该排程已经撤权；当前顺序只查[唯一现役路线](../scene-compatibility-roadmap.md)。

## 10. 静态研究候选的区分问题

下表仅把结构化文件与 executable 静态路径整理为研究任务可以区分的问题。它不是现役验收门、不是 implementation backlog，也不自动升级 API 等级；任何项目实现门都必须在 fresh-context 交接后重新写入现役 API 合同或路线。

| 能力 | 静态候选观察 | 可由独立研究区分的行为问题 |
|---|---|---|
| VM/runtime owner | §3 authoring surface；§9 只保存已撤权的项目草案 | source/module 的 scene 隔离、跨 scene/reload handle 结果、无限循环/OOM/异常/job 风暴的可观察失败半径，以及 DOM/Node/文件/网络是否可见 |
| 向量/矩阵类型 | §5.1 构造分派、§5.2 `_Epsilon`、§5.3 序列化 | `new Vec3(2)` = `(2,2,2)`；`new Vec3("1 2 3")` 往返 `toString` 一致；`equals` 在 `1e-5` 边界判不等 |
| 用户属性桥 | §4.3 三个 `_Internal` 回调、类型映射表 | `color` → `Vec3`；`usershortcut` 仅三字段；未声明 key 静默丢弃 |
| 自定义属性 UI | §6 完整 builder 协议 | 双键命名；combo 取 `options[0].value`；`order` 自增即渲染序 |
| 官方模块 | §7 三模块行为 | `mix` 不 clamp；角度制；`rgb2hsv` 三分量归一化 |
| 序列化 | §4.3 replacer + §5.3 格式 | 含向量的对象经 `stringifyConfig` 后向量为空格分隔字符串 |
| engine lifecycle | §8 版本、事件、timer、watchdog、teardown | 版本不符失败；19 slot；media/animation → audio/timer tick → live update → destroy drain；单事件隔离；实例熔断；destroy → record removal → engine release；stop 后 timer/audio/handle 为 0 |
| frame mutation commit | §9.2 仅为已撤权的项目草案，不是客户端静态观察 | event/timer/update mutation 的同帧/下一帧可见性、冲突/stale generation/callback 异常后的外部状态；具体 Swift transaction 形态不属于官方对照问题 |
| effective time / timer / audio | §8.2 单一 delta、pause/resume、timer snapshot 与 live update、稳定 arrays | frametime/runtime/timer 同 delta；完全暂停不累计，恢复不 catch-up；timer callback 新建 timer 下一轮执行；update callback 新建 owner 有界准入；16/32/64 arrays identity 不变且先于 update 刷新 |
| cursor state | §8.3 candidate、solid/visible/propagation、getter/event snapshot、hover/capture 与销毁失效 | hidden-solid 正例、后续候选不被遮断、world/screen/left-down snapshot、event object 独立、visible toggle 状态保留、destroy silent invalidation、同 identity click |
| host resources | §8.4 asset/layer/parent/model-data/storage | asset 首次 precache sticky；2048 identity cap；sort 与 script 顺序分离；destroy 后 render/update 边界；parent adjust/no-op/failure；wrapper 失效；replaceData 负门；storage 损坏恢复 |
| scene handles | §8.5 camera/material/particle/video/animation | camera typed partial update/default；ordered material execution；emit count；seek 不误报 loop end；ended callback 先于 one-shot removal；teardown 后 callback 为 0 |
| typed return/reflection | §8.6 conversion 与 metadata 通道 | scalar/Vec/bool/string/错类型/NaN/Inf；order/label/range/combo/color round-trip |

这些区分问题均可通过公开合同、项目自有 fixture 与官方黑盒结果研究，不需要复制官方源码，也不直接生成产品实现要求。

## 11. 未覆盖与后续

- `CameraTransforms` 的四成员、base defaults、authored override 与 typed partial update 已有主程序/DLL 静态互证；仍未闭合的是 VM finite/type 负向行为、2D/3D 冲突和脚本 camera 与同帧 authored/animation mutation 的优先级。
- cursor event-local/puppet 坐标、候选前后顺序、边界容差、多按钮与 parent/visibility 同帧 mutation 仍需自有 fixture；`cursorHitTest` 不属于 v2.8 公共 API。
- material descriptor 到完整 authored pass 的映射、particle GPU 同 draw 可见性、video registry pump/device-reset retained intent/provider error/多屏时钟以及 animation blend/root-motion 仍需自有 fixture、Windows trace 或视觉/声音 golden。
- prototype 导出（§4.1）与 token 机制（§4.2）的原生侧用法为本页历史等级 C 推断，只能形成后续研究问题，不能直接指导实现或写成兼容承诺。
- `ui/dist/scripts/scripts.js`（1.2 MB 编辑器逻辑）已于 2026-07-26 展开：其中**不含** Scene wire 字段的 schema 校验或默认值表（`depthtest`/`pointsize`/`maxrows` 等命中 0 次），此前「可能含属性 schema 校验与默认值」的推测不成立；其真实价值是内嵌的官方 changelog（含 10 条 V8 证据，把 §3 的 VM 选型目标从推断收窄为官方事实），见 [官方客户端 changelog 取证](client-changelog-forensics.md)。

## 12. 关联文档

- [SceneScript API 覆盖表](scenescript-api-coverage.md) —— API 表面与当前实现等级
- [资料来源与证据索引](source-index.md) —— 本文来源应登记于此
- [Windows 官方客户端取证记录](../../history/scene/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md) —— 证据等级出处
- [运行时系统语义](runtime-systems-reference.md) —— 运行系统执行顺序
- [官方客户端运行机制静态取证](client-runtime-static-forensics.md) —— Ghidra 方法、输入身份与 32/64 位结构交叉
