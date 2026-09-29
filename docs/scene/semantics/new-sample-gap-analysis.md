# 新样本缺口分析（2026-09-30）

> 基于 census 重扫（208 样本 / 2973 family / 81709 occurrence）+ 12 个问题样本的隔离
> benchmark 实测 + pkg 解包逐层核查。所有症状已映射到引擎日志与作者定义结构。

## 增量总览

208 样本（+36 新）、2973 family（+366）、81709 occurrence（+12947）。Family 增量：
layer +233、particle +49、dynamic-input +45、shader +25、material +3、audio +4、其余 +7。

## 缺口清单（按实测根因）

### 已修复

**缺口 2（自引用依赖黑屏）→ `60154574`**：1926190458 层 13 声明 `dependencies: [13]`，
`DependencyOwnershipCompiler.compile()` 的自引用路径因 `!effectiveReferences.isEmpty` guard
在 shadow 证明成功时返回 nil → 整层被 `execution-route-dependency-owner` 拒绝。修复为允许
空 effectiveReferences（shadow 证明成功正是 graph-internal 的意图）。修复后 169,753 unique
pixels、claimed=1/encoded=1。

### 待修复（按优先级）

**缺口 3（音频条 composition 层 textureBindingInvalid）→ `3d94a3f4` + `9b4086ff` 已修复安全回退**：
影响 3807151772/3806337293/3805547608/3807668787 等。层 399（composition + audio bars）被
`material-variant-envelope-texture-binding / textureBindingInvalid slot=0` 拒绝。根因：
音频条 shader 声明 `g_Texture0` 的 materialKey 是 `"上一个"`（中文编辑器写出的 previous
本地化键，字节级确认）。`3d94a3f4` 把该 rejection code 加入 passthrough allowlist（层不再
被整层丢弃）；`9b4086ff` 泛化 StraightBlendOutputAnalyzer 的 color 定义 gate 接受声明-赋值
分裂形态（colorTransfer 泛化）。

**当前状态（3807151772 benchmark PASS 40.6fps）**：层 399 的 shader 仍无法编译
（textureBindingInvalid 仍在，因为 materialKey 确实不是已知别名），但层降级为
previous-current 安全回退——场景背景继续渲染，音频条效果本身不绘制。Benchmark PASS。

**后续（缺口 3-c，dormant 合同完整启用）**：要让音频条 shader 实际渲染出条形图，需要让
dormant 门对 `"上一个"` 触发。当前 dormant 门在 `graphInputColorCarrierSlot` 处要求
color transfer analyzer 先证明 carrier slot（`straightAlphaPreserving` 等），而音频条
shader 的混合形态（`ApplyBlending(BLENDMODE, mix(finalColor.rgb, scene.rgb, scene.a),
finalColor.rgb, bar*opacity)` → `gl_FragColor = vec4(finalColor, alpha)`）不匹配任何
现有分析器模式。`9b4086ff` 已让声明-赋值分裂形态通过 `uniqueDefinition` gate，但后续的
`ApplyBlending` / `mix` / `exactUses` 检查链还需确认是否匹配音频条 shader 的完整形态。
这是下一修复批的入口。

**缺口 1（image→model→material 链黑屏）**：833227004 渲染纯灰（178,178,178 = 清屏色），
材质管线 planned=0。层 `image: models/background.json` → material `flowimage`。准入的
候选选择不含"无场景效果但模型引用自定义 material"的层。初版候选扩展编译过但被
`raw-graph-count` 拒绝——需要为这类层合成单 pass graph 或放宽该 guard，属独立设计批次。

**缺口 4（effect 执行失败→passthrough 泄漏）**：3809618616（全屏红纯色）、3806337293、
3796588443。根因是 workshop 效果 `video.frag` 第 77 行
`g_AudioSpectrum64Left[barID / 4][barID % 4]`——对一维数组用二维下标，glslang 编译失败。
**这是作者 shader bug**，官方客户端同样编译失败。引擎按合同 fail-soft（previous-current），
但 benchmark 的 passthrough 计数器把这种 previous-current 报为 unexpected（矩阵未预登记）。
无需修产品代码——需要在分析文档记录该形态。

**缺口 5（性能/卡死）**：3589454154（130 层、3.8fps 近冻结）、3232289987（60 层 9 粒子 +
跨 workshop 引用，进程超时）。需 CPU profile。

**缺口 6（跨 workshop 粒子引用）**：`particles/workshop/<other-id>/...` 不在本地 pkg，
systemParticles=0。需 graceful degradation 或预下载。

## 第二轮 benchmark（8 个代表性新样本，2026-09-30）

| 样本 | 结果 | fps | 观测 |
|---|---|---|---|
| 2163522240 | PASS | 54.4 | composition(2)+self-ref；自引用修复覆盖 |
| 2304304373 | PASS | 50.8 | composition(3)+model-material 链 |
| 2684431262 | **FAIL** | 5.7 | **黑屏**（69k unique 中 4.79M/6.2M 为纯黑 (0,0,0)）|
| 2794098047 | PASS | 56.6 | audio-bars+composition(4) |
| 3078285611 | PASS | 7.9 | **纯粉色**（583k/620k 为 (250,142,200)）——渲染单一覆盖色 |
| 3233141951 | **FAIL** | — | **进程超时**（12 秒窗口被 SIGTERM） |
| 3448845950 | PASS | 18.5 | 深色场景（51 万像素 (0,14,26)——暗色主题正常） |
| 3226487183 | **FAIL** | 17.9 | effect CPU invocation 失败 + passthrough（纹理错位） |

**65 个新增样本匹配已知缺口模式**（音频条/composition/self-ref/model-material 链）。
缺口 3 的修复（`3d94a3f4` passthrough allowlist + `9b4086ff` colorTransfer 泛化）已覆盖
其中音频条+composition 层的 textureBindingInvalid 拒绝。

## 新发现

- **2684431262**：纯黑+5.7fps——需排查模型→纹理加载（与 833227004 同类 model-material 链缺口）。
- **3078285611**：渲染为单一纯粉色——效果链可能产生单一覆盖色而非逐层合成。
- **3233141951**：进程 12 秒内被 SIGTERM——资源加载超时或 GPU 卡死。

### 非缺口（观察与实测不一致）

- **3805547608**：benchmark PASS，52fps。"图层源切换"是 UI 交互路径，静态测试不覆盖。
- **2983846453**：属性面板缺自定义图像导入是 UI 功能缺失，非 Scene 渲染缺口。

## 文档更新

`docs/scene/semantics/scene-corpus-capability-inventory.md` 已由 census 重写（172→208）。
快照 `script/scene_capability_census_snapshot.json` 同步更新。
