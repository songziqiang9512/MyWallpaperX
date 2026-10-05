<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# SDR 正常颜色恢复（2026-10-06）

> **历史证据 — 非现役入口**。当前权威：[D2输出设计](../roadmap/batch2/hdr-tonemap-edr-design.md)、[执行卡](../roadmap/batch2/reference-evidence-implementation-cards.md)。

基线 `7e73f423`，目标与取舍见 [D2 阶段 B](../roadmap/batch2/hdr-tonemap-edr-design.md)。用户报告的默认变暗存在明确终端原因：旧项目 shoulder 将普通白点 1 压为 0.75。本批保持 authored HDR 合成/Bloom 与显示 EDR 的区别；不声称官方最终曲线一致或 Display HDR 完成。

## 修改与画面收益

唯一 `SceneDisplayMappingPostProcess` 的 SDR 导出改为有限 RGB 饱和到 `[0,1]`，正常范围恒等，非有限通道归零，alpha 保留。所有使用该路径的场景都生效，无样本或资源分派；非 HDR 路线不变。删除仅测试引用的重复 CPU 曲线，实际颜色由 Metal 输出验证。raw16F、超白 Bloom、反射源、原始历史、资源生命周期及最终呈现 owner 未变。

这是明确的 SDR 取舍：普通图像亮部和白点恢复；超过显示范围的通道最终同白，但超白在裁剪前仍贡献 Bloom 光晕。未来曝光/保高光或 EDR 需显式输出合同，不恢复无条件压暗。现役 HDR Bloom 参数与 Display HDR 缺口仍待后继。

## 验证

证据根 `/private/tmp/mwx-sdr-output-20261006`，修后 App dylib SHA256 `580fcec269a67b883a14396b43ca53745d1da89cf87665a6f47048a2fa17308c`；运行与输入身份、日志和必要截图保留供独立复核。

- 修前真实 GPU 四项颜色断言失败；修前签名 App 对作者输入 `(1,0.25,0.5)` 输出 PNG `(191,64,128)`，实际白点压暗复现。
- 修后 Bloom/显示 GPU 13 项通过；真实 raw/history/reflection owner 5 项通过。验证正常灰/彩色逐位保持、有限裁剪、局部非有限处理、alpha、Bloom 后邻域增亮保留且不写回 source；多帧与半透明 raw 累积、取消/重置/旧 completion、暂停与精确大尺寸目标保护继续成立。
- 过程中修复旧 Bloom standalone fixture 缺外围 composition pin 类型导致的编译失败（该不使用的路径显式 trap），并更新两处 history 旧肩部曲线 oracle。新 halo 夹具最初在低分辨率/高强度下整幅过曝，改用低强度使可测邻域位于 SDR 范围；产品 Bloom 未调整。初次混合测试失败记录保留，最终通过分轮记录，不将旧失败日志称为全绿。
- 签名实际 App 四项通过：清底、持续累积、首次绘制后隐藏仍保留、暂停缩放且 VM 不前进；颜色恢复 `(255,64,128)`。一项“剔除 mapping 函数的派生 App”故障测试本批未跑，GPU 既有 pipeline/encoder 故障与恢复门仍通过。
- 真实 `2684431262` 原包隔离副本在修前/后各运行 10 秒，均正常启动/退出且 GPU drained、allocation failure=0。相同 PCM 夹具下青色/橙色/白色环与文字亮部恢复，光晕仍保留；动态相位不是逐像素锁定，不声明官方 parity 或性能改善。修前后均有25个material effect实际GPU完成、10个末端consumer进入合成；这不是整样本正确率。
- Debug 构建、代码健康、依赖、设计、防御、文档与目录布局门通过。结构 inventory 的 `shape-derived-analyzer-fleet` 66/65 是基线已有失败，本批未修改其 family 或放宽基线。文档路由31项中30通过，1项因四条历史README/机器索引权威不一致失败；`git show HEAD`与本批差异逐项相同，新增记录一致，未扩改旧文档职责。

## 后继

地球 `3437487219` 的 HDR slider 绑定 `general.bloomhdrstrength`，当前只消费标准 Bloom 参数；下一批先接通真实 HDR Bloom 配置与 typed 更新，验证其可见响应，再处理显示 EDR 和重型样本启动。此处为已读作者字段及当前消费者的静态缺口，不冒称运行已复现或修复。339 样本维持回归，完整兼容估计仍 70–75%（低置信），不因本批共享输出修复机械上调。
