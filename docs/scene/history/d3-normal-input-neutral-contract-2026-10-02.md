<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

> **历史证据 — 非现役入口**。当前权威：[D3设计](../roadmap/batch2/2d-lighting-material-design.md)、[实施路线](../roadmap/scene-compatibility-roadmap.md)、[来源分类](../development/source-index.md)。
>
> 中性内容由独立上下文审查通过；原交接正文SHA `432d1dbe2c2bcfe8580aa6005886aa90ffbb1c8769e17b159b72e352f7283310`，纠正并批准的研究卡SHA `f2d1092f778dd025723b5bd56741161bb050eab6c664b68c3487932496ff3f44`。审查仅批准交接，实施准入由现役设计拥有；本归档新增角色与导航，不引入原始研究表达。

# D3 normal 输入中性交接（已审查）

日期 2026-10-02；研究 context `/root/d1_order_blackbox`；product_write_authority=false。只写本临时研究目录。未运行 VM/GPU、未构建、未改仓库、未提交。研究者不得实施本 D3；实施必须使用 fresh context，且只接收本中性文档和研究卡，不继承研究对话。

## 决策结论

可以继续独立实现“明确 normal 语义的作者 binding → data-purpose 资源 demand → 同一 registry/publication → 现役 lit producer”的通用职责，不需要等待官方光照数学 golden。补证已确定：**此固定 2.8.42 stock 声明中，genericimage2 与 genericimage4 的 normal 均为零基 slot 1；slot 2 是 PBR masks，不能当法线。** slot 1 的作者可见标签经英文 locale 映射为 Normal map，mode明确为normal；presence combo为NORMALMAP，无default，作者声明的格式是rg88且formatcombo=true。这不是从变量名或纹理路径猜用途。

binding、presence、feature enable、resource availability、purpose 和 sampling frame 是不同事实。remaining unknown已收窄为formatcombo运行时取值/normal通道解码与空间方向、reset以及atlas consumer；不得用这些精确分支阻挡普通明确RGB normal的项目独立策略，也不能把策略冒称官方全格式兼容。

## official-public-contract

1. [Lighting & Reflections](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html)（2026-10-02 在线读取，Generating a Normal Map / Lighting）：image material 需启用 Lighting 或 Reflection；normal map 为平面层提供深度方向信息，开关决定是否接受灯光。该页没有序列化 slot、NORMALMAP 键、缺图规则或解码数学。
2. [Shader Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html)（Texture / Define New Texture / Optional Visible Texture）：sampler 0–7 各有自身 resolution、sprite rotation/translation；material metadata key 用于识别与覆盖；default 是未指定时的默认资源，optional combo 表示作者定义/选择纹理，不能从 default 倒造 presence。文档不公开 genericimage2/4 的 normal 槽映射，也不定义动态 normal 的生命周期。
3. [Advanced Lighting](https://docs.wallpaperengine.io/en/scene/lighting/lights.html)（Light Movement）：灯的真实 Z 高度影响 normal map。这个事实支持世界空间位置职责，不能推出 normal 的具体 Y 通道约定或切线算法。

## authored-corpus-observation

只用现役 `script/scene_capability_census_io.py` 的只读 package index / JSON entry 读取；未提取或读取任何 stock shader、纹理或其他资产 payload 正文。材料筛选只覆盖下列三个合法 scene.pkg 的 materials/*.json；另读 scene.json 中有关对象的 image/instance 字段。下表 hash 是精确 JSON entry 字节 SHA-256，不冒称整个包 hash。源 root 为 `~/Movies/MyWallpaperX/创意工坊/Scene/`。

| 包 / JSON entry | 关键作者字段及行号 | SHA-256 |
|---|---|---|
| 2815826216 / materials/98367037_p5.json | :8 LIGHTING=1；:9 REFLECTION=0；:20 genericimage2；:21 仅 slot0 | ef751ab8149ba52307134f579b71a951b1d929057a2f8f52b5493b4b2234f8bf |
| 3662790108 / materials/sun-4.json | :9 LIGHTING=1；:19 genericimage4；:20 slot0、null slot1、非空 slot2 | 5d0d88f8980a46779960b22003095ddf46662ece56e0a9b139b7d1fcc9bf307c |
| 3662790108 / materials/sun-1.json | :9 LIGHTING=1；:20 genericimage4；:21 slot0、null slot1、非空 slot2 | 85557e23bd3daa0ab30d1db829540c771a8b14d1f5fd4419bd6339ed9997747d |
| 3437487219 / materials/Universe.json | :9 LIGHTING=1；:24 genericimage4；:25 slot0、null slot1、非空 slot2 | 4fc65fa8a29edccefbe94fb0fed2ea0fc45c87e2607d5b91e2fbb34d804d2cd3 |

这些材料未显式写 NORMALMAP。结合下节固定声明，可确认它们**没有slot1 normal作者绑定，slot2属于PBR mask用途**，不能拿来验普通normal正例。scene对应对象未写instance：2815826216 id20；3662790108 id1121/1336；3437487219 id146/135/143。scene.json hash依次为 d34def3460001a2938803e8522fface217bb3cbb654672762a218bd223cf8c06、faea17adcce6b09b40c1a722c08b53bc4f3588c3189873986c754517a9500cc5、845a96e6ee0adc935aa2dd368a5be140a164221b21a1424179296ab85f2b52b5。

## official-client-static-observation：仅结构化作者声明元数据

Root另行授权后，按workflow第3节的合法stock结构层和第7节上下文隔离执行精确过滤。仅返回sampler slot及JSON作者metadata；未输出或阅读函数正文，不保存原始声明、shader/payload或算法表达。本节是归一化事实，非shader转录。

身份：`Reference Project/wallpaper_engine/version.json`当前声明2.8.42；同根wallpaper32.exe SHA-256 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`。build23967692只由来源索引历史登记，本轮未独立再证build号；精确内容绑定下列文件hash，不将EXE版本当作所有stock永未变更证明。

| 精确相对路径（上述客户端root下） | SHA-256 | 归一化声明事实 |
|---|---|---|
| assets/shaders/genericimage2.frag:21 | 1e252e2271cae57fcfdecf3bd79d1685bb726e1e8afe09ba863dca2e1b12d68e | slot1；Normal map作者标签；mode normal；presence combo NORMALMAP；无default；format rg88；formatcombo true |
| assets/shaders/genericimage4.frag:38 | 6b5344953054ae853ff8a7942f716dd9eb67f61cc1526bd8b6bc67df92c76e1f | 同上 |
| 上述genericimage2.frag:22 / genericimage4.frag:39 | 同各自文件hash | slot2是PBRMASKS；作者组件语义为metallic、roughness、reflection、emissive；非normal |
| locale/ui_en-us.json:2815 | 3a58e712363f8f20bf7c371746462ecaf36919be949dcc968a3785d07f251ea0 | 对应作者标签确认为Normal map；非依据名字猜测用途 |

normal声明同时携带LIGHTING=1、REFLECTION=1的require关系。这里只记录为作者UI关联，**不能据此推成播放器要求两开关同时为1的AND门**；公开文档明确可单独开启Lighting或Reflection。NORMALMAP是纹理presence而非lighting总开关；不要求材质JSON重复显式写NORMALMAP=1才承认非空slot1。格式声明rg88/formatcombo提示存在格式分支，但不证明实际资源必为RG8，也不公开Z重建/符号/强度算法。此研究没有进入该算法。

## 有界真实正样本核验

在上述三包内逐项只读materials/*.json，并仅检查genericimage2/4的indexed textures与scene objects[].instance.textures：分别发现4、198、4个相关material pass；**均未发现非空slot1，instance也均未发现非空slot1 override**。本轮没有真实normal正样本，不宣称任何现有场景已经受益。三包保留为“Lighting可达，但normal缺省/slot2 PBR不应误归normal”的反例；自写普通/中性/倾斜normal仍可建立新能力门。不读取纹理payload去猜用途。

## third-party-reference-pattern（不等于官方真值）

固定 revision **da4fa7b3ee33e9e94c59307f47098aa521f21aa6**，仓库 laobamac/MirageWallpaper。下列路径统一前缀 `SceneRenderer/Sources/SceneRenderer/`。通过 git show 固定对象核查；本地工作树 HEAD 已为 77e4886e，不能混用。历史专题基线 8893b25b 本轮没有复证，不继承其行号。

| 高层职责观察 | 固定路径:行号 |
|---|---|
| image instance 可携带 indexed textures、usertextures、combos，应用到 material 后才进入后续准备；非空 instance texture 覆盖同槽，null/空项保留 inherited slot；同键 combo 覆盖 | Wallpaper/Schema/ImageLayerSpec.cpp:57–90、381–384；Wallpaper/Schema/MaterialSpec.cpp:129–138 |
| material textures 的序号在准备中保持；作者 binding/header 状态参与 presence，sampler annotation 分开记录 default 与 presence combo，material 明确 combo 又覆盖准备值 | Wallpaper/Compiler/SceneCompiler.cpp:1870–1894、1905–1934；Wallpaper/Compiler/ShaderAnnotations.cpp:148–188 |
| 实際 slot 与 g_TextureN 对应；普通资源和 graph target 分支保留 slot。每槽 resolution 从其自己的 texture header/target 而来，不从 albedo 槽借用 | Wallpaper/Compiler/SceneCompiler.cpp:1937–2005 |
| sprite state 按 sampler 序号发布当前 rotation/translation；同一节点的脚本帧控制作用于该节点已登记 sprites，具体每纹理帧表仍独立 | AppRuntime/Controller/SceneUniformBinder.cpp:444–464 |
| 通用 Vulkan loader 对已列出的普通压缩/非压缩纹理格式选 UNORM；没有在这个边界把 normal 单独登记为用途。该第三方实现不能证明我方可省略 purpose，也不能证明官方 sRGB 策略 | Gpu/Vulkan/TextureCache.cpp:32–42 |
| NORMALMAP 名字有语义常量，但读到的 material/SceneCompiler 职责不按 genericimage2/4 硬编码 normal 槽；实际 sampler 语义依赖 shader metadata；具体stock元数据由上一节独立固定，不从Mirage硬编码推导 | Domain/Semantics/SemanticTextures.cppm:83；以上准备范围 |

限制：Mirage 的空项继承和 combo 优先级仅是第三方策略证据；官方默认/显式0/空字符串/reset差异尚需自写作者数据对照。其 loader 没有提供可移植的 normal-purpose 合同。它对 header/缺资源处理的细节不得用来覆盖我方现有 typed availability 与生命周期。没有复制第三方表达、结构或算法到本交接。

## 输入 → 准备状态 → 输出职责（MyWallpaperX-strategy）

| 输入 | 唯一准备状态与职责 | 帧/输出职责与边界 |
|---|---|---|
| builtin genericimage2/4、material pass Lighting、instance 同键显式覆盖 | 现有 material feature owner 先决定 bounded lit profile；保持明示0与缺省区别 | plain receiver 不因有 normal 或灯而受光；自定义 shader 不叠加第二套内建受光 |
| 上述固定内建profile的slot1 normal + indexed asset binding，或其它已证实normal语义的sampler | material prepare 产生 slot/path/provenance/purpose=.normal；同一 path 可有不同 purpose identity；不依路径拼写分类 | 现 texture demand/load/registry 真正供给 data texture；consumer 不在帧内重解析 |
| slot absent、default、明确 author candidate、可用/缺失资源 | presence 只来自实际作者绑定；default 与 availability 分开，不把 missing author candidate伪装成没启用 | normal 是可选分量；保留明确 flat fallback 和诊断，不偷偷换另一个 map；stale或非法range仍硬拒绝unsafe unit |
| dynamic binding/provider | 现 graph/resource publication 所有权；normal purpose 随binding传播，generation/epoch/slot固定 | 只消费当前合法publication；换图和下一帧更新必须经同一registry；不能把color provider未经data约定直接当normal |
| 普通 normal texture + sampler参数 | 该槽独立frame/physical/mapped/sampler描述；plain full texture 可先开放 | albedo与normal在同一几何局部UV上定位，但每槽各自完成texture frame映射；不把albedo padding/frame直接套给normal |
| atlas/sprite normal，或与albedo不同帧表 | 保留各槽frame来源；未知组合可局部normal fallback并报告，不能冒称支持 | 同一帧geometry basis与normal方向相配；只验证plain不能外推atlas、sprite、翻转、puppet |

实现者应独立检查我方现有.normal/BC5/RG上传是否已经重建或规范化normal Z，以及lit consumer对RGB的输入假设；同一分量不能在loader与shader重复处理。不能从本声明推导该实现选择，必须沿现资源owner核对并以自有中性/倾斜normal门验证。

Data-purpose 非sRGB是本项目显式数据合同；当前公开资料和第三方只支持职责方向，未证明官方内部颜色解码。坐标Y符号、normal packing、强度、UV随parallax/animation的特殊分支仍unknown，不要求先恢复官方光照公式。

## 自有正反门（预声明，未运行）

统一 256×256 不透明灰 albedo、200×100 quad、黑 ambient、单个已支持point/spot和固定Z；记录精确fixture/hash/App/GPU completion/publication/terminal compositor/next-frame。每变体只改一项。

1. plain：lighting=0，有/无normal应相同；lighting=1，missing与自写中性normal RGB(128,128,255)进行差分。量化误差须由fixture承认；宜另用可准确编码的float中性输入作为exact方向oracle，不能在失败后放宽。
2. normal方向：自写左右相反法线半区，用相反X灯位观察亮暗交换；旋转quad90°和非均匀scale分别验证同帧basis。不复用被测shader作为oracle。刻意错误sRGB-normal变体必须被ROI分辨。
3. override：material槽A、instance槽B、instance null、明确combo0/1分别验证prepare得到的binding/presence/feature；未证官方reset分支保unknown，测试只断言已批准项目策略。
4. dynamic：同一normal binding在相邻帧发布相反方向图，验证publication identity、下一帧ROI变化与旧generation拒绝；provider unavailable局部flat策略必须可观测且不污染albedo。
5. atlas：albedo有效区域故意放左上，normal有效区域放右下，外围填明显错误方向；另测normal plain/albedo atlas与反向组合。只有按各槽frame取样才能通过。sprite两帧方向相反，含不同打包旋转；无normal atlas准入时应明确fallback而不是悄然错误采样。
6. effects/no-effects：同一receiver两路线均经已有lit base producer，identity effect前后结果一致，唯一最终compositor消费可追踪。

离散binding/slot/purpose/generation要求exact；中性/缺图门暂定每通道≤1/255但需上述编码前提；有意相反normal的选定20×20 interior ROI差异>20/255以证明敏感性。官方golden未运行，不将这些自有门称parity。

## 唯一必要补证与可执行后继

**U1 slot已补证，format分支未定**：固定声明足以将genericimage2/4的slot1分类为normal-purpose。官方GUI自写normal导入前后作者JSON差分可作后续动态交叉核对，已不再是普通typed slot1实现的前置。仍须精确处理资源实际格式：优先自写明确RGB normal普通纹理建立项目策略；RG8作者资源的法线Z/方向解释不能由formatcombo=true推导，需要预声明中性/±X/±Y输入的官方黑盒或公开明确格式合同。若当前profile仅接受已定义编码，应对其它格式局部flat并诊断，不把所有normal拒绝。

**U2 presence/reset**：同工程清除normal控件保存S3，与S0对比；toggle Lighting保持normal绑定保存S4。定出null、删除字段、明确0的差别。当前material corpus没有提供这个往返证据。

**U3 space/atlas**：先只开放自写plain full texture项目策略；若要宣传官方atlas/sprite支持，再用独立打包normal/albedo与上下相反法线做官方单变量ROI。图像元数据只能固定frame归属，不能从公共变量存在推定stock consumer已使用它。

本研究到此停止扩大。最小设计裁决可批准固定builtin profile的slot1 normal输入、data资源链和独立RGB-normal有界行为；slot2不得注册normal。RG8 packing、reset、atlas/动态官方一致性仍分别保留unknown，不把这些后继问题升级为整个normal能力的无限研究前置。
