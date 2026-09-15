# SteamService 第三方组件许可（NOTICE）

App 随包发行 osx-arm64 自包含 .NET helper，不要求用户安装 .NET。保留本文件、`licenses/` 全部许可及版权声明；依赖版本以 `packages.lock.json` 和 `SteamService.csproj` 为准。

| 组件 | 版本 / 来源 | 随包许可 |
|---|---|---|
| SteamKit2 | [3.4.0](https://github.com/SteamRE/SteamKit/tree/3.4.0) | LGPL-2.1，`SteamKit2-LGPL-2.1.txt` |
| .NET runtime | [8.0.31](https://github.com/dotnet/runtime/tree/v8.0.31) | MIT 及第三方声明，`dotnet-LICENSE.txt` / `dotnet-NOTICES.txt` |
| protobuf-net / protobuf-net.Core | [3.2.56](https://github.com/protobuf-net/protobuf-net/tree/3.2.56) | Apache-2.0，`protobuf-net-LICENSE.txt` |
| ZstdSharp.Port | [0.8.7 source](https://github.com/oleg-st/ZstdSharp/tree/0ee6121aaa173b42e68d3c6c8816a68e910e0557) | MIT，`ZstdSharp-LICENSE.txt` |
| System.IO.Hashing | [10.0.1](https://github.com/dotnet/runtime/tree/v10.0.1) | MIT 及第三方声明，`System.IO.Hashing-LICENSE.txt` / `System.IO.Hashing-NOTICES.txt` |

SteamKit2 通过未修改的 NuGet DLL 动态引用，未裁剪或合并进单文件。发行者必须保留 LGPL 权利、许可及对应源码获取方式；独立进程不免除这些义务。上述固定版本链接提供对应上游源码，正式分发时仍须按发行方式核对源码提供义务。

上述 SteamKit2 与 protobuf-net 许可文件同时保留上游版权声明和完整许可正文（分别来自 GNU LGPL 2.1 与 Apache License 2.0 官方文本）。

## 重建与替换

安装 `global.json` 指定的 SDK 8.0.401，在仓库根运行：

```bash
/bin/bash script/publish-steam-helper.sh
```

脚本 locked restore 并固定 runtime 8.0.31，生成 `SteamService/bin/publish/`。修改 SteamKit2 时，可从上表固定来源构建兼容 DLL，用其替换生成目录中的 `SteamKit2.dll`；不要求修改本项目才能使用修改版库。也可将项目引用改为该本地构建后重建 helper。替换签名 App 内的组件会影响原有签名；本地测试可将完整 helper 目录复制到 App 外，通过 `MWX_STEAM_HELPER_COMMAND` 指定其中的 `SteamService`，或重新签署本地 App。

更新依赖或 .NET runtime 时，同时更新锁文件（如适用）、本文件、许可原文并执行自包含发布与启动门。SDK 固定用于可复现构建，不代表可以停止 runtime 安全更新。
