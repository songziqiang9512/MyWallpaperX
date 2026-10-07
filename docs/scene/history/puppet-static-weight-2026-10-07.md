<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。当前合同见[高级对象](../capabilities/advanced-object-coverage.md#32-puppet-静态权重与几何失败边界)，剩余任务见[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# Puppet 静态权重与失败发布修复（2026-10-07）

起点 `64f4a380`：3791967416 的身体网格已经恢复，但 animation layers 964/968 的 blend=1.3 使整个动画选择失败并退回 bind pose。现有额外轨道还截断到 1、减去 frame0，首 additive 和单 opaque 都忽略权重。先在高级对象第3.2节写入设计并登记，再沿 selector/evaluator/playback 三个原 owner 修正；设计快照保留在本批证据包。完成后窄设计登记退役，实施合同由上述能力页持有。

## 官方行为与独立实现

只使用公开作者 API 和隔离作者素材；没有消费客户端或参考项目私有实现。公开 [IAnimationLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IAnimationLayer.html) 给出 blend/paused frame API，但没有规定权重范围和数值公式。按[官方 CLI](https://help.wallpaperengine.io/en/functionality/cli.html)创建单独命名窗口，未替换用户桌面；Windows 11 VM 从 suspended 恢复，实验后恢复 suspended。

官方 wallpaper32 2.8.0.42，SHA256 `DAAC1EA7C991207FDB6098616757E3DAE393850F6862845DB55D04921B6BDA07`。静态 JSON 权重0/.5/1/1.3/2，脚本仅 pause/setFrame，在第20次update记录局部骨骼。控制轨道 bone11：frame0 T20/Rz10°/Sx1，后续固定 T30/Rz30°/Sx1.2，bind T≈59.3713/Rz0/Sx1；base、第二条 additive 与单 opaque 分开运行。控制模型只改本地副本的作者MDLA记录，原样本与用户官方截图只读。

控制结果排除 clamp、忽略 base 权重以及 frame0 reference。旋转2倍结果约1.01360rad，排除球面外推的1.04720rad；独立实现采用 bind-relative T/S 差和局部 quaternion delta、最短半球 nlerp。10组实际产品 reader/evaluator 对照的最大平移误差0、旋转0.00067049rad、scale比值误差小于5e-8，符合产品比较前预设的0.001/0.002rad/0.002容差。该观察不恢复官方内部公式，不证明非共轴多轨或任意权重的完整官方 parity。

## 修复与验证

- selector 接受有限 Float 可表示的非负静态权重；移除 first additive 特例与 reference pose 缓存。单 opaque、base/extra additive 共用同一加权求值；unit weight 非对易 bind/sample 自有反例保证旋转乘法侧正确。
- 外推产生非法 pose 或最终顶点时抛出失败。独立审查找到首帧无有效顶点仍 ready/draw 的旧漏洞：PlaybackState 现要求完整 prepared signature/revision 和实际上传过的 buffer；后续失败复用上一完整顶点/attachment，DEBUG 只读成功顶点。
- 真实 Metal 门又复现了 ObjectIdentifier 地址复用：已释放旧 command buffer 的地址被新对象复用，旧标记误判 ready。改为弱引用对象身份，不延长旧 command buffer 生命周期。
- 新数值门5项通过，原播放11项及骨骼查询、VM姿态发布、平移物理门通过。真实 PlaybackState/GeometryProduct/FIFO/image pipeline/Metal shader 的4项门通过：首帧失败不写buffer不绘制；第二顶点溢出前确有部分scratch写入，但旧GPU buffer、像素、挂点和evidence全部保留；恢复后全部更新；异对象和旧对象释放后均不继承ready。旧PlaybackState反证有4个失败断言。外围stub仅供空snapshot、allocator和evidence观察。
- 最终 Debug build成功；独立只读审查接受产品、两份新测试和门映射。源码身份固定在 `source-identity.json`，门禁和提交后验证分别保留，不把审查者读日志说成独立复跑。

## 真实画面与未完成项

最终签名 Debug App CDHash `6bae34e34c4b4f3d5d3f0c3513bbee9284986637`，team `H9QWU9XN8R`。30秒隔离 direct Host 回放退出0、无超时，身体608/962均由bind回退转为 `mode=layered ids=750,1052,846 clips=3`，8771顶点/15817三角进入真实网格绘制；两条静态1.3轨道不再被拒。series-0001 稳定截图已核对，身体与服饰保留，姿态有动画驱动。

整体验收仍FAIL：效果CPU失败、barcode局部passthrough、hover阈值未达。眼睛993的auxiliary track6542仍拒，眼/眉组装重叠、脚本动画handle/seek、偏暗及最终合成未收口。3条clip加载不证明脚本控制轨道的所有API有效，loaded=1也不计完整样本正确率。下一批先处理眼部auxiliary/挂点与seek，随后控制viewport/光标/时刻核对颜色，不能据本次画面强行全局提亮。

失败保证限于GPU几何发布。VM getter只检查完整有限骨骼矩阵；最终顶点溢出的帧可能让脚本观察新骨骼矩阵而几何保持旧帧，未宣称全链原子一致。并发transaction取消、GPU故障、完整named-provider组合和普通产品入口不在本批验收范围。

证据根 `/private/tmp/mwx-puppet-weight-20261007` 保留固定身份、输入配置/控制模型、官方数值、产品数值对照、测试/构建/运行日志、代表图及保留清单。staged App、输入副本与冗余中间产物清理；继续共用一份 `/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d` checkpoint缓存。
