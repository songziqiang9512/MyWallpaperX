# Wallpaper Engine stock 播放资产包

> 事实快照：Wallpaper Engine `2.8.42` / Steam build `23967692`
>
> 路径清单来源：Wallpaper Engine `2.8.42` 固定客户端快照的静态取证
>
> 项目目录：[SceneStockAssets.bundle](../../../MyWallpaperX/Resources/SceneStockAssets.bundle)

## 1. 目的与边界

`SceneStockAssets.bundle` 按官方 `assets/**` 的原相对路径、文件名和扩展名保存 Scene 所需的项目自有资源。素材原位落地，不新增平行命名、目录或 runtime 别名；包可以同时包含播放、编辑器、preview、example、thumbnail 和 source-only 资源。

bundle 不设目录级的文件清单、文件数量或 preview 排除门禁。逐资产的官方 codec/尺寸/通道/mip/atlas/像素 parity 未证明，也不表示所有 consumer 已实现。

本包不含bundle内部作者manifest或目录级静态catalog。运行时共享`SceneMaterialAssetCatalog`仍可按作者exact路径建立typed demand，并依次查询package/loose与`SceneStockAssets.bundle/assets/...`；这不是第二套资源registry或别名表。各consumer的定向功能测试负责验证其实际使用的资源。

## 2. 运行与替换合同

当前真实consumer包括三组播放consumer和一组有界资源consumer：Particle material slot 0会在样本本地资源缺失后直接读取`assets/materials/particle/**/*.tex`；文字解析会在壁纸包内字体缺失后直接读取`assets/fonts/<作者文件名>`；Water Flow普通MaterialProgram的phase slot可由共享material asset catalog在作者package/loose exact候选缺席时解析`assets/materials/particle/normal_ring_smooth.tex`，并沿同一typed purpose/file-generation/publication合同消费；`.lookupTable` TEX loader可直接解析并上传`assets/materials/lut/*.tex`的严格3D volume profile。上述路径都不使用替代文件名映射；LUT路径目前只到Metal `type3D` resource，不包含Effect/material consumer。

共享publication门已证明Water Flow exact `.phase` purpose会读取上述stock TEX及sidecar/format identity；作者loose exact候选仍按正常优先级覆盖stock，stock缺失、purpose错配和路径逃逸都失败关闭。其余Effect、material、shader、sidecar、normal、多纹理、SceneScript和zcompat文件，以及LUT的effect/material binding，虽然具备固定物理身份，consumer仍按各专项能力表推进。后续实现必须直接复用本包现有路径，并以“包内现有文件被对应consumer实际读取”为资源链验收条件；不得再创建另一个stock资产包、另一套命名或第二resource registry。

占位生成器 `script/generate_scene_stock_asset_bundle.py` 与历史集合门 `script/tests/test_scene_stock_asset_bundle.py` 已随真实素材落地退役（`47e2fa8`）。bundle 内容不再有目录级门禁，由各 consumer 门验证运行时实际读取的资源。

## 3. 证据等级

- A 级：2.8.42 固定客户端快照静态取证记录了 3,113 个相对路径、扩展名及目录归属。
- 项目事实：Particle slot 0 可直接解码并上传包内 `particle/debris/debris1` 的 1024x128 R8 spritesheet；字体 consumer 可由 CoreText 打开官方命名字体；Water Flow ordinary Program的stock phase publication测试锁定`particle/normal_ring_smooth.tex` SHA-256 `a867c40ea0f69b45b1b10dd48eff700f322569cb51f770d28a46ab5e3fa5173d`、`.phase` purpose、file identity/sidecar/format、作者loose覆盖、missing与traversal拒绝；当前 28 个 `materials/lut` TEX 均经同一 strict profile 上传为 32×32×32 Metal 3D texture。Particle slot 0、字体与Water Flow consumer已进入播放runtime；LUT仅完成资源ingest/upload。
- 未证明：未接入文件的官方加载时机、JSON/shader/sidecar语义、其余TEX codec/尺寸/通道/mip/atlas/颜色空间和像素等价；Water Flow stock publication门也不证明独立效果ROI或官方视觉parity，这些仍需自有fixture与Windows golden。
