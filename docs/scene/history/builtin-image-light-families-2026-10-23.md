# 内建图片材质灯光代际修复

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-23；合同归[D3设计](../roadmap/batch2/2d-lighting-material-design.md#builtin-image-light-families)，静态覆盖归[光照清单](../capabilities/lighting-sample-inventory.md)，未修问题归[队列](../roadmap/scene-open-breakpoint-queue.md)。本片只关闭已资格的灯光选择和直射贡献，不代表整景或完整光照一致。

<a id="builtin-image-light-families-20261023"></a>
## 通用修复与官方对照

原 builtin genericimage4 与旧图片材质共用 raw point 过滤，漏掉现代 lpoint 和 directional。现准备期保留 typed family，由同一 LightSnapshot、lit payload 和 plain/graph producer 消费；legacyImage 保旧 point，LightingV1 接 lpoint/directional。现代直射复用项目已有 AnalyticSchlick 与一次1/π归一化，点光用三维距离，方向光无距离衰减；旧 point 的平面距离及1.85增益、spot/ambient、normal/map、reflection/emission、PMA与最终输出各自保持。未扩作者 shader 准入、模型或粒子算法。

官方2.8.0.42，主程序 SHA256 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`；自有无纹理法线、MR=0/1、灰白标尺与OFF控制，先冻结ICC→sRGB、四锚点映射及测量门，不据结果拟合gain。新版材质的 raw point/OFF/反向方向光均0；正向方向光官方/候选均20，lpoint强度2均24，ready/after一致。修前现代点光和方向光为0。输入、测量代码、参数、原始图及身份均归档。

保留失败：v1 autosize使接收面缩小，未资格；v3 lpoint强度1中位12，未过事先16的正控下限；事前声明的v4仅改强度2后过门。旧 genericimage2 改名邻例对 raw point 有贡献、对lpoint为0；其官方 raw point已饱和255，原生99，**不能据此裁旧增益或声称旧数值一致**。两端均20/24仅证明这组固定法线、位置和MR下的有界响应，不外推全BRDF或所有光照样式。

## 实际画面与验证范围

候选为 `1ac578a18` 冻结源码加5个灯光文件的签名优化Debug，App SHA256 `1168542fb4c3d8b975d8c0c03a8eae41da1e3f2b1100e5e4999d3681408a49b3`、CDHash `669ee617b7536e83b9d1ac0162be8e30eea81731`；Metal library SHA256 `07a583e3c3e7996670bfd5958abb28496db45847b46004f6b6fa9086ef3a4c38`。嵌套签名及strict验证通过。后续并行提交只改UI，未覆盖这5个输入。

- `3351179520`：同原包修前/修后12秒窗口，背景及字样从暗蓝变为更明亮青蓝；人物、雨和圆环保留。目录官方截图支持受光改善方向，未锁定比例/音频/相位，不认整图数值相等或关闭文字对齐余项。
- 未参与修法的旧tier `2815826216`：同输入前后人物与主要构图保持；圆环时间/音频差异不判回归，也不称逐像素不变。
- `3437487219`：候选实际地球、云层、银河与时钟可见；Earth/Cloud属于模型，不以此次图片层通过关闭夜侧颜色或偶发闪烁。
- 单窗口335的CPU p50约6.87→6.82ms、GPU p50约65.32→65.14ms；281约2.54→2.41ms、8.73→8.69ms。未做三轮同条件性能资格，**不宣称性能或能耗收益**。

CPU验证覆盖prepared family、非builtin与LIGHTING关反例、真实preflight、现代四灯预算及payload四槽、零能量与非法方向、848字节ABI；GPU覆盖同帧混合family、方向正反、旧路径重复一致、normal旋转、PMA/HDR、31个scalar/half及独立reflection。实际App的5个方法/12场景全部通过，包括genericimage4默认/非法MR回退、新lpoint、旧point黑色反例及真实own_dim Program/effect消费。旧测试曾把genericimage4与旧point/1.85 oracle配对；修正输入和独立闭式oracle后保留原四项覆盖，没有删去失败场景。独立审查结论随正式包保存；构建、测试与运行门不升级完整D3、Release/HDR显示、多屏或长稳结论。

## 另行发现的启动失败

`3662790108` 在候选和不含灯光修改的纯 `1ac578a18` App上都缺ready，触发Host既有5秒期限；纯HEAD App SHA256 `57d5d41cef3c2e866f8297393219bc39c36b42daf16a76de79c766dd75fef9cd`。原包身份相同，不能把此项算本批灯光回归，也不能把该样本记通过。日志可见qualified/held后动态文字发布、帧驱动重启，随后GPU成功已属旧token；没有Host session-first-frame。最早可疑职责是未采用的文字provider发布被映射为surface失效；全部97次尝试未逐条归因，后继需事件反例与原包复验。此项入队，未在灯光批内修改启动代码。

## 必要证据与退出

正式包 `.artifacts/scene-evidence/runs/builtin-image-light-families-20261023/` 保存自有输入、官方原图、失败/测量、签名/测试/独审及receiver矩阵；`builtin-image-light-families-real-20261023/` 保存335/281修前修后原图与运行；`builtin-image-light-families-startup-20261023/` 保存343画面和366两版本失败，后者标未解决保护。每包不超过32MiB、总预算5GiB；普通结果14天。统计矩阵SHA256 `3b6c08e31fcadca5697c5c76719cecc346b28be7911f134c4d13bfc507ff38bc`，不复制真实PKG或媒体。

所有本轮原生运行已结束，官方自有预览已关闭，主客户端和VM保留。12个自有guest stage的哈希清理命令传输失败，删除状态未知，保留失败收据，不称已清理；不为此改系统或关闭用户VM。本机已停止使用的App、输入及重复输出在正式包校验后清理，最终产物去留随提交收据记录。
