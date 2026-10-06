# App 内容与体积

正式 App 保留运行代码、依赖、许可证及运行资源；开发现场和编辑器展示素材不进入 App。
源仓库中的 Scene 公共资产仍完整保留，不能根据当前样本覆盖率删除可能被作者路径引用的资源。

本批本机 arm64 Release 实测（逻辑文件大小，不重复计符号链接）：

| 内容 | 修改前 | 修改后 |
| --- | ---: | ---: |
| 整个 App | 235.69 MiB | 187.98 MiB |
| SceneStockAssets.bundle | 76.50 MiB | 53.33 MiB |
| Videos.zip | 30.23 MiB | 6.60 MiB |
| SteamService | 83.62 MiB | 83.53 MiB |

资源部分减少 50,019,473 bytes（47.70 MiB）；并行源码开发可能改变主程序大小，后续发布应重新测量。

## SceneStockAssets

`script/copy-scene-stock-assets.sh` 是 App 内该 bundle 的唯一复制入口；Xcode 自动资源复制排除原目录。
复制保留原始路径和运行文件字节，仅过滤：

- `.mimosa`、`.DS_Store`：本地工具或系统元数据。
- `assets/effects/*/preview/`、`assets/presets/*/preview/`：编辑器预览工程，797 个文件、约 21.97 MiB。
- `assets/materials/particle/**/*_preview.gif`：52 个粒子编辑器预览图，约 1.20 MiB。

效果 JSON 中的 `preview` 字段仍原样保留。资源加载器加载 passes、dependencies 等运行引用，
没有加载这些预览工程；现有保留 JSON 中也没有运行字段依赖上述预览文件。
`test_stock_asset_packaging` 检查这一依赖边界，并实际运行复制脚本，逐文件核对保留内容的哈希、
许可证和旧输出清理。若以后增加这类运行引用，应调整打包合同，而不是忽略测试失败。

以下继续保留：材质/纹理（含原始图片及 `.tex-json`）、模型、字体、着色器、脚本、粒子定义、
预设运行内容、兼容资源和全部许可证。部分 `.tex-json` 已出现在效果 dependencies 中；
`.dxs` 虽未完成 Metal 支持，也不能因此认定未来无用。Scene 允许作者动态引用公共路径，
因此本次结论是“排除编辑器展示内容”，不是对未来所有壁纸行为的无条件保证。

## 自带视频

`Videos.zip` 只保留 `Video2.mp4`（皮卡丘，3840×2160/25 fps/11.28 s）和
`Video3.mp4`（霓虹城市，1920×1080/30 fps/18.67 s）。两者采用 HEVC `hvc1`、yuv420p、
faststart，保持原分辨率、帧率、帧数和时长；这是有损重新编码。对应编码参数为
libx265 medium、CRF 24 / 28。需要复做时可从资源变更前的 Git 版本提取原 ZIP，按相同文件名编码。

ZIP 从 31,697,465 bytes 减为 6,918,174 bytes。本机检查了完整视频的 FFmpeg 解码及 SSIM，
并使用 AVFoundation 验证首、中、尾帧解码；这不代替最低系统版本上的完整播放验收。
缓存更新沿用 `BundledVideoLibrary` 的 archive hash 与原子目录替换，测试覆盖旧五视频缓存切换到新两视频缓存。
不触碰用户导入的壁纸目录。

## 其他内容

- Help 只随 `MyWallpaperXHelp` bundle 复制一次，避免同步目录再复制一份根目录资源。
- QuickJS 的开发 README、`.mimosa` 会话和 `.source` 快照不作为资源复制；许可证保留。
- SteamService 不复制 PDB；自包含 .NET、SteamKit、动态加载依赖及许可证保留。
  不启用未经验证的 trimming/AOT，也不按当前调用统计删除 DLL。
- App/dSYM 分开发布，dSYM 是 Release 附件，不塞进 App；Release 本就没有 Debug 注入 dylib。
- `Resources/SceneMediaObserver/SceneMediaObserver.dylib` 随 Developer ID Release 分发
  （2026-10-07 发布负责人决定，见 [D6 渠道修订](../web/mediaremote-nowplaying-design.md)）；
  由 `script/build-scene-media-observer.sh` 构建并随包签名，供壁纸歌曲信息的系统正在播放
  来源在独立 Perl 宿主装载。Mac App Store 构建不得包含该私有 backend。

`validate_apple_silicon_release.py` 在实际 bundle 上拒绝开发残留、PDB 和重复根资源。
本机无签名 Release 体积是逻辑文件大小，不能直接当作最终公证 DMG 的下载体积。
