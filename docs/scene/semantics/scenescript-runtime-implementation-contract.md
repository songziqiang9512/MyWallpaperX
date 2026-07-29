# SceneScript 运行时实现层合同（2.8.42 客户端取证）

审查日期：2026-07-25；Ghidra engine 增补：2026-07-30
取证快照：Wallpaper Engine 2.8.42 随包文件
审查方式：静态检查

> 本文只覆盖在线文档未公开、但客户端取证记录到的实现层事实。`lib.sceneScript.d.ts` 的 API 表面（接口、签名、生命周期钩子）已在 [SceneScript API 覆盖表](scenescript-api-coverage.md) 建立，本文不重复。
>
> 本文回答的是 API 覆盖表回答不了的问题：**声明背后的实际数值行为、宿主与 VM 的桥接协议、以及编辑器声明的 authoring/type surface**。

## 1. 为什么需要这份文档

[资料来源与证据索引](source-index.md) 已收录在线版 `lib.sceneScript.d.ts`。但声明文件只给类型，不给行为：

- `equals()` 声明返回 `Boolean`，但**判等用什么容差**，声明里没有；
- `new Vec3(x)` 声明接受多种重载，但**标量如何广播到 y/z**，声明里没有；
- 用户属性怎么跨 native/JS 边界传递、怎么反序列化成 `Vec3`，声明里完全没有；
- SceneScript 自定义属性 UI（slider/combo/color）的构建协议，声明里**一个字都没有**。

这些都是 pixel-exact 对齐和 conformance test 必需的。客户端取证提供了它们。

## 2. 证据来源与等级

| 代号 | 文件 | 规模 | 等级 |
|---|---|---:|:---:|
| `JS` | `assets/scripts/jsclasses/baseclasses.js` | 1456 行 | A |
| `JM` | `assets/scripts/jsmodules/{wemath,wevector,wecolor}.js` | 13/15/47 行 | A |
| `DT` | `ui/dist/monaco/autocomplete/lib.sceneScript.d.ts` | 2570 行 | A |
| `LB` | `ui/dist/monaco/autocomplete/lib.es*.d.ts` 清单 | 23 个文件 | A |
| `GB` | `wallpaper64.exe` + `scenescript64.dll` 的 Ghidra 有界静态路径 | module/engine/event/timer/teardown 邻域 | B |

等级沿用 [Windows 官方客户端取证记录](../../reviews/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md)：A = 客户端快照中的结构化文件直接确认。

## 3. 编辑器 authoring/type surface（`LB`）

[SceneScript API 覆盖表](scenescript-api-coverage.md) 中「ECMAScript VM」一项为 `L0`，缺口写的是「选定 VM；严格 global allowlist」。Monaco 自动补全的 lib 清单直接给出官方自己界定的语言边界：

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

**证据边界**：Monaco type lib 不是 runtime syntax probe。它不能单独证明官方 VM 必然接受全部 ES2019 语法，也不能证明 `??`、`?.`、`BigInt`、`globalThis` 在 runtime 必然失败。对 MyWallpaperX 的作用是把 VM 选型目标收窄为“至少覆盖随包 ES2019 authoring surface，并默认不暴露 DOM/Node/WebWorker”；具体语法与 global allowlist 仍需正反运行门。JavaScriptCore 只是候选，不能因宿主可用就直接记为兼容。

## 4. 宿主 ↔ VM 桥接协议（`JS`）

`baseclasses.js` 末尾（1375-1456 行）是宿主注入层。这部分**不在 `.d.ts` 中**，是本地独有证据。

### 4.1 prototype 导出

文件在顶层 `this` 上导出 5 个 prototype 引用，键名为 `_Vec2`、`_Vec3`、`_Vec4`、`_Mat3`、`_Mat4`。

顶层 `this` 可用（而非 `undefined`），说明该随包文件在观察到的包装上下文中获得了宿主对象；是否直接脚本求值、是否另有 wrapper 以及严格模式边界仍属于 C 级解释。用户模块源码则明确使用 `'use strict'` 与 ES `export`。

推断（等级 C）：原生侧构造向量/矩阵时挂这些 prototype，避免每次跨边界重新构造 JS 对象。MyWallpaperX 若用 JavaScriptCore，对应做法是缓存 `JSObjectRef` 原型并用 `JSObjectSetPrototype`。

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

**对 MyWallpaperX 的作用**：这三条直接是 `SceneDynamicSnapshot` 与用户属性桥的实现规格。特别是 `usershortcut` 只投影三字段、未声明 key 静默丢弃这两条，属于容易漏掉又会导致行为分叉的细节。

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

`Mat4.fromEuler` 接受 Vec3 或 x/y/z；`extractEuler()` 和 `decompose().rotation` 也返回 degree。实现时不能把序列化数组当 row-major，也不能在 SceneScript bridge 内套用弧度制。

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

1. `toConfigString` 是全类通用的**未公开序列化 API**。作者代码不应依赖，但 MyWallpaperX 的桥接层必须实现它，否则 `stringifyConfig` 无法正确处理向量。
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

**对 MyWallpaperX 的作用**：这是当前随包证据中确认的 SceneScript 自定义属性声明通路。若要兼容使用该 builder 的脚本，需要支持双键命名，并保留 `_config.order`；是否还存在 native/editor 私有入口不由本文件证明。

同一注入段还把全局 `shared` 初始化为空对象。它确认初始 identity，但不确认多脚本、跨 layer、跨 surface 或壁纸切换时的共享/销毁范围；这些生命周期仍需运行门。

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
- event 与 timer callback 会累计真实执行耗时，宿主可读取并清零。项目可据此设计分级预算，但不能把观察到的客户端 watchdog 阈值直接复制为 MyWallpaperX policy。

### 8.2 Event、timer 与 audio tick

- 每个 script record 固定保存 19 个 event slot：init/update/resize/destroy、用户属性、通用设置、animation、六个 cursor 与五个 media。
- 每个 slot 有独立存在/禁用位；单一 handler 被禁用不等于停掉整份脚本。
- init、update 与 animationEvent 的返回值进入绑定 property writeback；其他 event 只产生副作用。
- frame tick 先刷新 16/32/64 的 left/right/average 稳定数组，再处理 timer。
- timer 由 frame delta 驱动；interval 到期每帧至多执行一次，执行后从完整周期重新计时，不追补长帧漏掉的周期。
- `registerAudioBuffers` / `registerAsset` 与 timer/storage 等操作存在不同求值阶段约束；公开取消合同仍以注册函数返回的 cancel function 为准。

### 8.3 Property return 与反射

property return 通过集中式 typed conversion 写回 number、bool、string 和 vector；标量可广播到向量，错类型、不完整向量或非法数值不得覆盖旧值。原生 property reflection 还保留 name、label、顺序、类型、数值范围、bool、归一化颜色、文本和 combo option。带单位字段的精确转换与全部异常边界仍需项目自有 fixture。

### 8.4 Destroy 与 teardown

- engine teardown 会先停止/唤醒 watchdog 并等待监督线程退出，再释放 script record、timer、音频注册、host wrapper 与 isolate。
- DLL 的 record removal / engine 析构不会替宿主调用用户 `destroy`。
- 主程序两条独立 lifecycle path 都会主动派发 destroy，因此 owner removal 前 exactly-once destroy 是 host 职责。
- adapter/多接口间接层使 `destroy -> record removal -> engine teardown` 的完整相对顺序仍无法由静态路径无歧义确认，应保留 fake-VM fixture 或 Windows dynamic trace 门。

## 9. 对 MyWallpaperX 的验收门

按 [SceneScript API 覆盖表](scenescript-api-coverage.md) 的分级口径，本文可支撑以下项从「无依据」升级为「有 A 级规格、待实现」：

| 能力 | 本文提供的规格 | 建议验收门 |
|---|---|---|
| VM 选型 | §3 随包 authoring surface 到 ES2019、无 DOM/Node/WebWorker 类型 | 正向：官方默认项目用到的语法与 ES2019 authoring subset；负向 global allowlist 由独立运行门确认 |
| 向量/矩阵类型 | §5.1 构造分派、§5.2 `_Epsilon`、§5.3 序列化 | `new Vec3(2)` = `(2,2,2)`；`new Vec3("1 2 3")` 往返 `toString` 一致；`equals` 在 `1e-5` 边界判不等 |
| 用户属性桥 | §4.3 三个 `_Internal` 回调、类型映射表 | `color` → `Vec3`；`usershortcut` 仅三字段；未声明 key 静默丢弃 |
| 自定义属性 UI | §6 完整 builder 协议 | 双键命名；combo 取 `options[0].value`；`order` 自增即渲染序 |
| 官方模块 | §7 三模块行为 | `mix` 不 clamp；角度制；`rgb2hsv` 三分量归一化 |
| 序列化 | §4.3 replacer + §5.3 格式 | 含向量的对象经 `stringifyConfig` 后向量为空格分隔字符串 |
| engine lifecycle | §8 版本、事件、timer、watchdog、teardown | 版本不符失败；19 slot；单事件隔离；实例熔断；destroy exactly-once；stop 后 timer/audio/handle 为 0 |
| typed return/reflection | §8.3 conversion 与 metadata 通道 | scalar/Vec/bool/string/错类型/NaN/Inf；order/label/range/combo/color round-trip |

均**不需要**复制官方源码即可实现与验证。

## 10. 未覆盖与后续

- `CameraTransforms` 是唯一确认由引擎原生提供的类，其 4 个成员的实际行为**无本地证据**，仍需运行时观测。
- prototype 导出（§4.1）与 token 机制（§4.2）的原生侧用法为等级 C 推断，只能指导实现，不能写成兼容承诺。
- `ui/dist/scripts/scripts.js`（1.2 MB 编辑器逻辑）已于 2026-07-26 展开：其中**不含** Scene wire 字段的 schema 校验或默认值表（`depthtest`/`pointsize`/`maxrows` 等命中 0 次），此前「可能含属性 schema 校验与默认值」的推测不成立；其真实价值是内嵌的官方 changelog（含 10 条 V8 证据，把 §3 的 VM 选型目标从推断收窄为官方事实），见 [官方客户端 changelog 取证](client-changelog-forensics.md)。

## 11. 关联文档

- [SceneScript API 覆盖表](scenescript-api-coverage.md) —— API 表面与当前实现等级
- [资料来源与证据索引](source-index.md) —— 本文来源应登记于此
- [Windows 官方客户端取证记录](../../reviews/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md) —— 证据等级出处
- [运行时系统语义](runtime-systems-reference.md) —— 运行系统执行顺序
