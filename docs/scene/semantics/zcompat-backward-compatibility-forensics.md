# zcompat 官方向后兼容机制取证

审查日期：2026-07-25
取证快照：Wallpaper Engine 2.8.42 `assets/zcompat`
审查方式：只读静态检查，全目录 11 个文件 / 52 KB

> `assets/zcompat` 随包分发了按数字 ID 组织的 shader 替代候选与 Web 字符串补丁记录。静态文件能确认补丁数据形态，但不能单独确认官方 loader 的匹配顺序、应用时机或失败策略。
>
> 它直接回答一个 MyWallpaperX 必须面对的问题：**当我的实现与某个作品的隐含假设冲突时，官方是怎么处理的。**

## 1. 结论先行

1. `assets/zcompat` 是安装包中唯一以兼容命名的顶层目录，含 scene shader 候选与 Web patch record 两类数据；这不排除引擎代码内还有其他兼容逻辑。
2. 两类数据的路径都使用数字 ID，但 scene 目录名究竟是作品 ID、共享资产 ID 或其他 Steam identity 仍是 C 级解释。
3. scene 配置的 `maximumprojectid` 是**字符串**且取值可达 `INT64_MAX`，超出 IEEE 754 安全整数范围；字段如何参与匹配尚未确认。
4. web record 具有 `file` / `replace` / `insert` 字段，一个 record 可列出多个候选路径；“字面替换、逐项尝试”是需要运行门确认的高可信解释。
5. 5 个 web 补丁中**有 4 个逐字节相同**——同一个修复被登记到 4 个不同作品 ID 下，机制本身不做去重。
6. 附带产物：两个候选 shader 中出现的 `g_AudioSpectrum*` 系列 uniform，在 `assets/shaders` 全部 108 个顶层 stock shader 中出现 0 次。这确认了随包作者 shader 的音频接口形态，但不证明引擎实际填充策略。

## 2. 目录全貌

```
assets/zcompat/
├── scene/shaders/
│   ├── 2078835426/  config.json  pixelate.frag  pixelate.vert
│   └── 2084198056/  config.json  Simple_Audio_Bars.frag  Simple_Audio_Bars.vert
└── web/
    ├── 780658164.json  780662613.json  780675904.json
    ├── 784979889.json  854685299.json
```

11 个文件，52 KB。目录名 `zcompat` 的 `z` 前缀使其在 `assets/` 下**排序最后**（`effects` … `shaders` 之后），推断是为了保证覆盖层在基础资产之后加载。等级 C。

`assets/` 顶层无其他兼容命名目录。在本轮允许的 official asset 范围内，`maximumprojectid` 只出现在这两个局部 `config.json` 中；`wallpaper64.exe` 的只读字符串表（ASCII/UTF-16 双编码）未命中该键，因此本文的行为语义只能到推断级。未读取安装根用户配置或个人项目数据。

## 3. Scene shader 覆盖

### 3.1 `config.json` 结构

两份配置的完整内容：

| 目录 | `maximumprojectid` | `frag` | `vert` |
|---|---|---|---|
| `2078835426` | `"9223372036854775807"` | `pixelate.frag` | `pixelate.vert` |
| `2084198056` | `"2638335396"` | `Simple_Audio_Bars.frag` | `Simple_Audio_Bars.vert` |

三个字段，无其他键。

**`maximumprojectid` 是字符串，不是数字。** `9223372036854775807` = `INT64_MAX`（`2^63 - 1`），远超 IEEE 754 双精度安全整数上界 `2^53 - 1 = 9007199254740991`。用 `Double`/`NSNumber` 解析会静默丢精度得到 `9223372036854775808`。Swift 侧必须按 `String` 读入后转 `Int64`/`UInt64`，或直接做字符串比较。

`2638335396` 虽然本身在安全范围内，也同样带引号——**字段类型是稳定的字符串**，不是「大数才加引号」。

### 3.2 目录名与生效条件

目录名 `2078835426` / `2084198056` 具有 Steam Workshop ID 的数字形态。两个 shader 都带 `[COMBO]` 与 uniform 标注（见 §3.3），且不在 stock `assets/effects` 中；它们来自作者侧资产的解释可信，但具体 Steam identity 需要与 Workshop metadata 交叉验证。

`maximumprojectid` 的语义推断（等级 C）：目录 ID 标识被覆盖的**共享 shader 资产**，`maximumprojectid` 则限定**引用它的壁纸作品**的 ID 上界——ID 小于等于该值的作品套用覆盖版，之后发布的作品不套用。

支持这一读法的两点：`INT64_MAX` 是「无上界，永远套用」的自然写法；而 `2638335396` 是一个具体截止点，符合「某次修复后新作品无需再打补丁」的模式。

**该语义无法从本地文件或二进制证实，实现时必须先建最小 fixture 验证，不能直接写成兼容承诺。**

### 3.3 覆盖 shader 的结构事实

两份 shader 的结构信息：

| 项 | `pixelate` | `Simple_Audio_Bars` |
|---|---|---|
| `.frag` 规模 | 1.9 KB | 12 KB / 303 行 |
| `.vert` 规模 | 1.1 KB | 251 B |
| `[COMBO]` 数 | 2 | 8 |
| 自定义 `u_` uniform | 2 | 7 |
| 顶点变换 | 使用 `mul` 与 model-view-projection uniform | 同左 |

两份都使用与 stock shader 相同的 `mul` 等候选 frontend token。可确认 token surface 有交集；确切矩阵约定与 frontend 展开仍按 [Shader source 前置合同审查](shader-prelude-and-backend-abstraction.md) 的 C 级边界处理。

zcompat shader 中出现的 prelude 符号：`texSample2D` ×6、`frac` ×7、`saturate` ×3、`mul` ×2、`CAST3` ×1、`HLSL`/`GLSL` 各 ×1。全部落在 25 个已确认符号内，没有引入新符号。

uniform 标注的两种 `material` 语义值：`"framebuffer"`（pixelate 的 `g_Texture0`）与 `"previous"`（Simple_Audio_Bars 的 `g_Texture0`，label `"Prev"`），两者都带 `"hidden":true`。这是纹理槽绑定别名的实物样本。

两份 shader 的 10 个 `[COMBO]` 的 `type` 是 `options` ×9 与 `imageblending` ×1，全部落在 stock shader 已有的取值域内，**没有引入新控件类型**；也没有使用 `[OFF_COMBO]` 等变体拼写。

`assets/` 全域的注解标记普查、`[COMBO]` 载荷键必填性、`require` 依赖条件，以及 combo 注解与 uniform 标注的 `type` 值域划分，见 [Shader source 前置合同审查](shader-prelude-and-backend-abstraction.md) §8。本文初版曾把两类注解的 `type` 合并成一张表，是错的：`color` 在 `[COMBO]` 行上出现 0 次。

### 3.4 音频频谱 uniform（附带发现）

`Simple_Audio_Bars.frag` 声明了 6 个音频 uniform：

```
g_AudioSpectrum16Left[16]   g_AudioSpectrum16Right[16]
g_AudioSpectrum32Left[32]   g_AudioSpectrum32Right[32]
g_AudioSpectrum64Left[64]   g_AudioSpectrum64Right[64]
```

**这 6 个名字在 `assets/shaders` 的 108 个 stock shader 中出现 0 次**，因此不在 [Shader Prelude 文档](shader-prelude-and-backend-abstraction.md) §7 的 141 个 `g_` uniform 清单内。这份 zcompat shader 是本机唯一的实物证据。

两条可确认的声明合同：

1. **三档分辨率 16 / 32 / 64**，与 `lib.sceneScript.d.ts` 的 `AUDIO_RESOLUTION_16/32/64` 常量一一对应。JS 侧与 shader 侧用同一组档位。
2. shader 声明了左右声道两个独立数组，因此 MyWallpaperX 的 binder/IR 不能把两个 uniform identity 合并。静态声明不能证明 Windows renderer 给两者填入不同数据；真正的 stereo provider 行为仍需左右声道非对称输入实验。

该 shader 的 `RESOLUTION` combo 默认值为 `32`，选项恰为 `{16, 32, 64}`。源码按 combo 分支选择数组；编译时还是运行时 variant 的最终切换时机需结合 frontend/cache 运行门确认。

## 4. Web 代码注入

### 4.1 结构

`zcompat/web/<workshopID>.json`，统一结构：

```
{ "actions": [ { "file": <相对路径>, "replace": <字面子串>, "insert": <替换文本> } ] }
```

三个字段，无 `regex`、无 `count`、无条件字段。字段形态支持**字面子串替换**解释，但没有运行证据确认多匹配、零匹配与编码策略。

### 4.2 5 个补丁的实际内容

| 文件 | 大小 | actions 数 | 内容 |
|---|---:|---:|---|
| `780658164.json` | 533 B | 4 | `texImage2D` 空值守卫 |
| `780662613.json` | 533 B | 4 | **与上者逐字节相同** |
| `780675904.json` | 533 B | 4 | **与上者逐字节相同** |
| `854685299.json` | 533 B | 4 | **与上者逐字节相同** |
| `784979889.json` | 264 B | 1 | THREE.js renderer alpha + clearColor |

`cmp` 确认前 4 个完全一致。**同一个修复被复制成 4 份、按作品 ID 分别登记**，机制不做共享或去重——补丁与作品是一对一映射。

### 4.3 `texImage2D` 补丁（4 份）

4 个 action 覆盖 4 条候选路径：

| `file` | 记录的补丁意图 |
|---|---|
| `index_files/index.min.js.Download` | 给纹理上传调用增加 null guard |
| `js/index.min.js` | 同类 null guard |
| `js/index2.min.js` | 适配另一组压缩形参名的 null guard |
| `js/index3.min.js` | 同类 null guard |

三条可确认的机制事实：

1. **多路径 record**。同一个补丁列出 4 条不同路径，说明 schema 允许一次记录覆盖多个文件候选；缺失文件是跳过、警告还是整组失败尚无运行证据。
2. **压缩变量名敏感**。其中一条 action 适配不同的压缩形参名，说明 record 保存精确 source fragment，不是抽象 AST pattern。
3. **补丁内容是空值守卫**。它针对纹理参数为 null 的路径；导致该状态的具体官方版本、加载时序与原始故障没有本地证据。

`index_files/index.min.js.Download` 是非常规但真实存在的相对路径。其来源是否为浏览器“另存为”属于无证据猜测，不进入兼容合同；路径解析只需保持精确、相对且防止越界。

### 4.4 THREE.js 补丁（1 份）

`784979889.json` 的单个 action 作用于 `js/index.js`（**非压缩**源码）：

`replace`：构造 `THREE.WebGLRenderer` 时 `alpha: true`
`insert`：改为 `alpha: false`，并追加一行 `renderer.setClearColor(0xe0dacd, 1)`

即把透明背景改成不透明，并补一个具体的背景色常量。这说明**注入不限于等长替换，可以插入新语句**。

## 5. 机制特征归纳

| 维度 | scene shader 覆盖 | web 代码注入 |
|---|---|---|
| 键控方式 | 目录名 = 共享资产 Workshop ID | 文件名 = 作品 Workshop ID |
| 生效条件 | `maximumprojectid` 上界 | 无条件（文件存在即尝试） |
| 粒度 | 整份 shader 替换 | 字面子串替换 |
| 失配行为 | 未知（无本地证据） | 未知（需运行门） |
| 一对多 | 一份覆盖服务所有引用者 | 一作品一文件，重复内容不共享 |

共同点是随包数据驱动、路径以数字 ID 分组。二进制 strings 未命中不能证明引擎代码没有其他作品特判。对 MyWallpaperX 的可取设计是独立、可审计、版本化的兼容 manifest，但 schema 与补丁内容必须自有，不能复制官方/Workshop payload。

## 6. 对 MyWallpaperX 的候选实验与验收门

| 项 | 规格 | 验收门 |
|---|---|---|
| `maximumprojectid` 解析 | 原样保留 `String`；若实验确认数值语义，再做 checked `Int64` 转换，禁止走 `Double` | raw string 往返不变；checked parse 等于 `Int64.max`，不是 `...808` |
| 覆盖查找 | 用自有 fixture 分别测试目录 ID、壁纸 ID 与 cutoff 方向 | Windows 输出只允许一个假设通过后再固化 |
| web patch 多路径 | 分别测试缺文件、零匹配、单匹配与多匹配 | 记录 Windows 的跳过/警告/失败策略，不预设静默 |
| web patch 匹配 | 比较字面、正则、首次/全量替换候选 | 非 ASCII 与换行差异也进入负向门 |
| 音频频谱 | IR 保留 L/R 独立 identity 与 16/32/64 三档 | 非对称立体声输入下记录 Windows 两组数组和可见输出 |
| fixture 路径 | 官方 `zcompat` 的结构用于对照；仓库 fixture 自行编写 | — |

需要注意的取舍：MyWallpaperX 是独立实现，官方的兼容补丁是针对**官方引擎某次行为变更**写的。直接套用官方补丁**未必正确**——如果 MyWallpaperX 的纹理就绪时序本来就是安全的，`texImage2D` 空值守卫是无害冗余；但 THREE.js 那份改的是**可见外观**（背景从透明变成 `0xe0dacd`），套用与否会直接改变画面。

在上述 matcher/runtime 语义确认前，不应把官方 `zcompat` 直接接入产品。若未来需要兼容层，应使用自有 manifest、明确 provenance 与逐条回归门，并保持默认路径不修改 Workshop 文件。

## 7. 未覆盖与边界

- `maximumprojectid` 的比较对象与方向无本地证据，等级 C。二进制字符串表未命中（ASCII 与 UTF-16 双编码均已尝试），无法进一步确认。
- 覆盖 shader 在 `maximumprojectid` 判定失败时是回退到作者原版还是拒载，无证据。
- web 补丁的应用时机（解包时改写磁盘 / 加载时内存改写）无证据。MyWallpaperX 无论采用何种自有兼容层，都不得修改真实 Workshop 来源；必须在隔离副本或内存表示上执行。
- 只有 2 个 scene 覆盖和 5 个 web 补丁，样本量不足以推断字段的完整取值域（例如 `config.json` 是否支持 material 或 texture 覆盖）。

## 8. 关联文档

- [Shader source 前置合同与跨后端假设审查](shader-prelude-and-backend-abstraction.md) —— frontend token 与 `g_` uniform 清单（不含音频系列）
- [SceneScript 运行时实现层合同](scenescript-runtime-implementation-contract.md) —— `AUDIO_RESOLUTION_*` 常量与 `registerAudioBuffers`
- [官方 19 工程 fixture 清单](official-default-projects-fixture-inventory.md) —— `supportsaudioprocessing` 开关的官方样本
- [资料来源与证据索引](source-index.md) —— 第三方播放器的 mono spectrum 偏差记录；本文来源应登记于此
