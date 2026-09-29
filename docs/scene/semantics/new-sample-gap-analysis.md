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

**缺口 3（音频条 composition 层 textureBindingInvalid）**：影响 3807151772/3806337293/
3805547608/3807668787 等。层 399（composition + audio bars）被
`material-variant-envelope-texture-binding / textureBindingInvalid slot=0` 拒绝。根因：
音频条 shader 声明 `g_Texture0` 的 materialKey 是 `"上一个"`（中文本地化的 previous 别名，
字节级确认 E4B88A E4B880 E4B8AA）。引擎的 `usesGraphInputMaterialAlias` 只认
`framebuffer`/`previous`/`ui_editor_properties_framebuffer`，不认识中文本地化键 → slot 0
无法解析 → textureBindingInvalid。
**处理方式（按用户指示不硬编码本地化别名）**：走既有
`dormantUnresolvedMaterialGraphInput` 合同（E-V1-DORMANT，真实样本 3749463715:536 已验证
同型修复）。该合同专为"authored 非空 key 但不是已知别名"设计，只要求 shader 唯一
sampler、hidden、无显式绑定/默认值/readiness fallback。音频条 shader 满足全部条件
（唯一 sampler g_Texture0、hidden、material 无 textures 数组）。但 dormant 门的
`graphInputColorCarrierSlot` 要求 color transfer 已证明（音频条 shader 是
straight-alpha-preserving 形态：`gl_FragColor = vec4(finalColor, alpha)` +
`mix(finalColor.rgb, scene.rgb, scene.a)` 混合上屏，color transfer analyzer 应能证明），
需验证 analyzer 对该形态的覆盖。这是下一修复批的入口。

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

### 非缺口（观察与实测不一致）

- **3805547608**：benchmark PASS，52fps。"图层源切换"是 UI 交互路径，静态测试不覆盖。
- **2983846453**：属性面板缺自定义图像导入是 UI 功能缺失，非 Scene 渲染缺口。

## 文档更新

`docs/scene/semantics/scene-corpus-capability-inventory.md` 已由 census 重写（172→208）。
快照 `script/scene_capability_census_snapshot.json` 同步更新。
