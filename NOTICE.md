# MyWallpaperX 项目与第三方声明

## 项目许可

MyWallpaperX 项目自有代码（另有许可声明者除外）按 **GNU General Public License v3.0 only**（SPDX：`GPL-3.0-only`）提供。完整许可正文见仓库根目录的 [LICENSE](LICENSE)。项目由各贡献者保留相应版权。

本软件可以在 GPL 3.0 规定的条件下修改和再分发，不附带任何担保，包括适销性或特定用途适用性担保。分发者须遵守完整许可证，包括适用的对应源码提供及声明保留要求。

项目源码与正式版本：[songziqiang9512/MyWallpaperX](https://github.com/songziqiang9512/MyWallpaperX)。每个正式 Release 的源码由其 `build-<version>` 标签固定；重建入口见 [README](README.md#开发与贡献)。

## 第三方代码、组件与资源

下表用于定位许可材料，不替代各组件的完整许可证，也不将第三方内容重新许可为 GPL。

| 组件或资源 | 声明位置 |
| --- | --- |
| SteamKit2、.NET runtime、protobuf-net、ZstdSharp、System.IO.Hashing | [SteamService/NOTICE.md](SteamService/NOTICE.md) 与 [licenses](SteamService/licenses/)；随自包含 helper 一起分发 |
| QuickJS-NG | [MIT 许可与原作者版权声明](MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/QuickJSNG/LICENSE)，随 App 保留在 `Contents/Resources/QuickJSNG/LICENSE` |
| glslang | [编译工具随包许可](MyWallpaperX/Resources/SceneShaderCompilerLicenses.bundle/Contents/Resources/glslang/LICENSE.txt) |
| SPIRV-Cross | [编译工具随包许可](MyWallpaperX/Resources/SceneShaderCompilerLicenses.bundle/Contents/Resources/spirv-cross/LICENSE) |
| Sparkle | [上游许可](https://github.com/sparkle-project/Sparkle/blob/2.9.2/LICENSE)；版本由 Xcode 的 `Package.resolved` 锁定，随 framework 保留原声明 |
| Scene 公共字体、图像及其他素材 | `MyWallpaperX/Resources/SceneStockAssets.bundle/Licenses/` 及资源附带声明；打包规则见 [App 内容与体积](docs/release/bundle-content.md) |
| 演示视频、项目图标与截图 | 不因项目代码采用 GPL 而改变原有权利归属；分发前应确认对应授权 |

App 中保留 `Contents/Resources/LICENSE` 和 `Contents/Resources/NOTICE.md`；helper、编译工具与资源 bundle 内的第三方许可也须保留。再分发时应同时提供与所分发版本相对应的完整源码和必要构建材料，并满足各第三方许可的独立要求。

## 独立项目与内容权利

MyWallpaperX 与 Valve、Steam、Wallpaper Engine、Pixabay 无隶属或官方合作关系。相关名称及商标归各自权利人所有。

用户导入、下载或播放的第三方作品，其版权及使用权限由原作者和相应平台决定。应用功能与项目开源许可均不授予额外的作品访问、复制或分发权利。
