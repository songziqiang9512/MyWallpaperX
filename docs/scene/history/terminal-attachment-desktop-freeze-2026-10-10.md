> **历史证据 — 非现役入口**。当前任务从[断点队列](../roadmap/scene-open-breakpoint-queue.md)继续。

# 正常桌面终端目标权限与歌曲触发停帧（2026-10-10）

现役状态归[U16/U24断点队列](../roadmap/scene-open-breakpoint-queue.md)，本页只记录本批完成范围。

## 首断点与修复

基线 `7b4b896a`。用户报告 `3122339805`、`3420215721` 从Xcode Cmd+R构建后设为桌面，歌曲信息出现时整个场景停止。原测试使用截图证据窗口，不能覆盖普通桌面：`SceneDebugFrameCapture.configure` 为readback将CAMetalLayer设为非framebuffer-only；调试入口还可能默认关闭系统媒体。

在隔离HOME/样本副本中以相同协议启动普通 `--mwx-scene-daemon`，不带debug root/evidence参数，读取真实系统媒体。312用用户Xcode二进制及候选都复现：77帧之后rendered/drawCalls固定，dropped持续增加，busy为0，时钟截图停止。临时中性诊断确定首拒绝为 `graph-preflight-stage-0-node-0-material-0-…-pass-target-rejected`，不是主线程死锁或自动暂停。

`SceneResolvedMaterialAttachmentStorage.target` 把离屏输出的 `.shaderRead` 要求错误套到最终绘制目标。媒体使相关材质图层出现后，terminal replay在准备阶段拒绝普通SDR drawable；调试截图目标已有读取权限，掩盖了该错误。

只将已有 `PassRole` 显式传入同一target检查，准备与编码再验证一致：离屏要求renderTarget+shaderRead，terminal要求renderTarget。输入纹理可采样、输入/目标不得别名、格式/设备/尺寸/mip/sample、Program/reset身份和one-shot回执全部保留。没有修改CAMetalLayer策略、媒体Store、Program profile、资源owner或合成算法。所有临时日志均已撤回。

## 验证及边界

- 旧产品上，既有pass GPU门仅新增的PMA/straight renderTarget-only两像素断言失败，其他135项含原readable像素控制、offscreen拒绝及shaderRead-only终端拒绝通过。既有graph端到端门改成只可绘制目标后，同样报targetRejected。
- 修复后两GPU门通过，覆盖实际prepare→MainPass→GPU完成及像素；one-shot terminal receipt门首次因旧mock缺已提交的sharedModelPath而编译失败，补齐不可构造stub的trap-only成员后5项通过。最终pass门重跑通过，未在mock中实现新产品逻辑。
- Debug构建、签名及761个Scene源身份核对通过。最终dylib SHA `9320635c5fdb800456d46d7d1fd2b7bf992137992fcea7827f739b4b5c7392dd`。构建复用隔离checkout（Web基线较旧），不是全HEAD发布验证。
- 正常桌面312第一轮修复后940帧/0drop，真实metadata/cover进入，30秒后的时钟和数字窗口继续更新；最终移除临时日志后的构建再跑988帧/0drop/busy0，exit0，launch.json事前绑定普通daemon参数及最终产品身份。直接daemon覆盖真实桌面surface和system media，不等于App音频采集、全设置或全部交互验收。
- 342以用户Xcode二进制、修复前、修复后默认配置均持续出帧（分别498、489、487提交）；30fps请求下约半数尝试因in-flight未提交，且未接App音频采集，不能宣称用户的停帧报告已解决。其封面491准备拒绝和频谱/亮度余项仍开放。
- Scene依赖、defense、设计门通过。全仓code-health仍被未改Web文件1008行阻挡；residue检查发现未知归属的Scene/.mimosa（218字节），按规则保留。本批没有调整基线或清理他人文件。

## 产物与后继

本机根 `.artifacts/tmp/media-freeze-20261010` 保留有界运行、构建身份与红绿证据，pass红收据另见 `.artifacts/tmp/terminal-replay-target-20261010/audit`。正式证据库已达1GiB预算，本批不扩预算、不删除他人包。仅连续复用 `.build-cache/solid-source-domains-recovery-20261009` 一份构建缓存。

独立审查覆盖原公共权限合同、同一检查的两调用方、反例及真实桌面证据。下一项继续U24真实App音频/可见冻结条件及in-flight丢帧；不把U16因果闭环写成两样本全修。正常桌面与证据窗口的验证差异已写回开发工作流。
