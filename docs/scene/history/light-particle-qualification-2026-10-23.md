# 粒子式光线的归因与尺寸资格

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-23；统计归[光照清单](../capabilities/lighting-sample-inventory.md)，开放问题及后继顺序归[队列](../roadmap/scene-open-breakpoint-queue.md)。本批未改产品，没有样本视觉修复或性能收益结论。

<a id="light-particle-qualification-20261023"></a>
## 376：保持原倍率的主/子粒子归因停止

3769761761的429没有顶层alpha；`.01`来自instanceoverride.alpha，不能重开已闭顶层alpha问题。原SpriteTrail与static Sprite child只把ColorRandom分别固定R/G，保持相机、祖先、几何与全部instanceoverride；B仅互换颜色。自有控制板带IMAGE、OFF与同child halo材料、particle alpha=.2×原instance alpha=.01的低透明度Sprite正控，事前要求OFF各通道≤1，正控主通道≥4且高于其余≥3并有16个连通像素，禁止调亮救门。

唯一原生A的两张settled图在ready后约2.074/2.615s，sRGB标记明确。3024×1964 cover裁掉右侧两锚点与OFF3，四锚点资格失败；诊断映射的LOW区域全黑也不能冒充资格坐标或证明child未执行。结论STOP_UNKNOWN，B和官方均未运行；未改输入位置、阈值或gain重试。原缺斜带继续开放，后继先提供可辨、完整注册的主/子贡献，不重复默认晚窗或以GPU总数猜因。

## 131：非方尺寸观察保持，严格门未获资格

1315486372顶部52是普通纹理Sprite光卡，不是Light Shafts effect。既有官方方形size80→40×40资格不重做；新自有128×512全opaque纹理含白边及不对称RGB内标，同板IMAGE40×160与固定size80的单Sprite，无速度/旋转/fade/atlas/parent。两个端分别用同板IMAGE作标尺，事前区分宽度主轴比值1与高度主轴.25，不扫轴或倍率、不缩放截图硬比。

签名优化Debug `c10d061b…d1a13`一次6s/after3/series1s，两个settled原图IMAGE/Sprite均219×872；初始及committed只有粒子20，采样GPU成功、最终drain。官方2.8.0.42/SHA256 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`，Session1/main8640；两文件逐字节资格后只dispatch一次，CUA两张原始JPEG的独立黑client均[93,214,1293,993]、1200×779，IMAGE/Sprite均87×347，内标方向相同。每端比值均(1,1)，既定两mask支持边一致，几何观察不支持按基本尺寸主轴改产品；不外推原光卡宽软、alpha、旋转、父变换或HDR。

严格同式锚点门仍NOT_QUALIFIED：native测量的exact-RGB单组件实现，在原编码JPEG三个锚点均零命中；独审按ICC→sRGB得到碎组件且边缩3–4px，仍失败。研究卡未明确冻结该exact-byte分割算法，后续宽support/dominance只能保留几何观察，不能充作全卡PASS。官方4076B Display ICC与原生sRGB不同，不认绝对颜色或完整parity；未改阈值、重跑官方或以观察关闭131原差异。早期dominance-only GO保留为SUPERSEDED，最终comparison与独审均保停止边界。

## 身份、产物与退出

两次原生App均为相同冻结c10d字节，运行门/退出/drain正常，不把矩阵PASS代替上述正控。独立审查亲看原图并CPU复算，通过本批不改算法、不关闭原缺陷的判断。376输入A/B及131板、失败/观察、原图、manifest、VM命令与清理收据归正式包`.artifacts/scene-evidence/runs/light-particle-qualification-20261023/`（ZIP 2,007,871B，SHA256 `d3d58fdd083b123f082cfb9d0f0ef35c63ee45e4309c09c389003e9a7306eda5`）。普通14天、单包32MiB、总5GiB；真实样本只读。

首次cmd复制与长清理命令遇Parallels传输Invalid argument，先verify-existing再决定下一步，未不明重拷或重启。短PowerShell复制校验成功；公开closeWallpaper按唯一location关闭预览，CUA确认消失；末哈希一致后清掉本批guest stage，主客户端8640及VM保留。原生运行副本已由benchmark清理，归档后删除停用本机实验输入/重复输出；连续迭代仅留既有单份构建缓存及冻结源码，并行UI改动/App不动。
