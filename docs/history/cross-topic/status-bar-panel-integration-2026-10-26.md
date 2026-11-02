# 状态栏控制面板整合与限定验证记录 · 2026-10-26

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-26；原产品提交`43280edd2`，归档来源为`f07322860b7c073a78c068a5df01519f7aec221e`的设计页。本记录不代表本次运行或新的安装授权。

当前0.88布局、恢复、失败、关闭及验收边界仍见[现役设计](../../development/status-bar-panel-redesign.md)。以下原连续9行、1680字节逐字保留，载荷SHA256：`0f26212552d320397f7fdd2e10a01f1056f4fff5331c07902a8b415c0d96d104`；它不是整档哈希。旧包、命令、安装和清理安排只属于当时环境。

<!-- preserved-body:start -->
### 执行记录

- 原生面板及用户确认的外观调整已完成；保留原采样策略，无二级菜单或额外常驻任务。
- UI专项放行`de3ef098e`后整合：删除本专项原独立LastPlaybackSelection/SQLite恢复实现与额外暂停通知；保留最新Library Sequence、typed pending、Restoration与pauseSnapshots唯一链。源导航、手动恢复、静态轮换和属性入口均调用现owner。
- 独立审查修正迁移记忆/暂停意图、部分来源加载、全catalog重复解析、小高度按钮重叠及同步/异步失败反馈；原owner回归覆盖Stop/重启、来源/查询保留和迟到/过期反例。
- 最终原生面板/Restoration、Library Sequence/产品事务、pause/icon门及Debug/Release构建通过；独立复核无新增可修问题。Release通过25个Mach-O的arm64闭包、同Team签名/必要权限/版本核验，已替换并启动`/Applications/MyWallpaperX.app`（2.11.0/283）。仅确认新版主窗口启动，状态栏实景与操作交用户测试；harness不代表实景、延迟或全样本验收。保留基线Scene隔离和旧控件警告，未混改。
- 临时HOME不隔离CFPreferences域；预览阶段已改用独立签名bundle标识与偏好域，正式安装仍保持产品身份。该测试处理不修改产品运行配置。

产品提交`43280edd2`以UI放行提交`de3ef098e`为父，快进整合到`codex/engine-refactor-program`；未触碰main、不推送。最终证据保留在忽略目录`.artifacts/status-bar-integration-20261026/`，旧预览、安装回退副本、临时样本及本轮DerivedData于安装启动验证后清理；正式安装App继续保留供用户测试。
<!-- preserved-body:end -->
