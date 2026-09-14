# SteamService 第三方组件许可（NOTICE）

本目录发行物包含以下第三方组件；发布前必须随包分发本文件与对应许可文本，并保持依赖版本锁定（`packages.lock.json`，LockModeFilePathAndContent）。

## SteamKit2 3.4.0

- 来源：https://github.com/SteamRE/SteamKit（tag `3.4.0`）
- 许可：LGPL-2.1-only（https://github.com/SteamRE/SteamKit/blob/3.4.0/SteamKit2/SteamKit2/license.txt）
- 使用方式：通过 NuGet 以未修改二进制形式引用（`SteamKit2 3.4.0`，见 `SteamService.csproj` 与 `packages.lock.json`）；本项目未修改 SteamKit2 源码。
- LGPL 义务：独立进程不自动免除义务。若替换/重链接修改版 SteamKit2，必须提供其源码或等价重链接说明；随发行物分发许可证文本；保持本 NOTICE 与版本锁定一致。
- 传递依赖以 `packages.lock.json` 内容为准（含 protobuf-net 等），发行前逐项核对许可与分发义务。

## 重建说明

```bash
cd SteamService
dotnet restore --locked-mode
dotnet publish -c Release -r osx-arm64
```

依赖版本变更（含 SteamKit2 升级）必须：更新 `SteamService.csproj` → 重新生成 `packages.lock.json` → 核对新版本许可 → 更新本文件。
