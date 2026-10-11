<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。职责归[运行合同](../architecture/runtime-architecture.md)，未完成项归[断点队列 N06](../roadmap/scene-open-breakpoint-queue.md)。

# 初始图层配置与普通图片资源复用（2026-10-12）

## 本片结果

基线 `c7761b7f` 的 2887542690 有 34 个 origin owner 因 `getInitialLayerConfig` 缺失发生 TypeError。沿原 authoredValue → descriptor → QuickJS catalog 补初始配置副本，沿现 base-image owner 将已上传成功的普通图片资源引用接入原 dynamicImageResources，不新增加载器、provider、AST 扫描或 compositor。

真实 App 后验中 34 个方法缺失错误消失；25 个普通 image 目标通过既有创建/事务资源准入，5 个 Puppet（285/227/183/191/370）及 composition286 仍局部拒绝未准备资源。另 3 个 text owner（887/318/640）可以继续执行，但隐藏 clone 的 text wrapper 尚未正确消费，不能计完整克隆正确。因此本专项按受阻目标计已接通 25/34，约 74%；不是整样本画面正确率。全部目标的 shadow 属性实际为 Off，本片可见收益是原层脚本恢复及鼠标响应，不是新增投影阴影。

## 合同与边界

- 官方 2.8.0.42 自有输入证实 name/index/ILayer 查询返回初始作者对象的独立深副本，只删除顶层 id；保留 script/value wrapper、image/size 字符串、未知字段及 nested id。实时字段和返回值修改均不污染初始值；缺名称或越界序号返回 null。
- 配置在 catalog 准备时编码一次，getter 使用 VM 原生数据复制，不在普通帧解析作者 JSON。编码失败不产生有效 catalog token；快照由原 domain 释放。
- 资源投影要求普通成功 Entry 与模型默认 SourceKey 一致，且唯一 builtin 普通图片 pass、单 slot0、无常量/用户输入、默认 render state、无未知 combo；保原 candidate/texture 引用。层级 override、自定义/multipass 材质、上传失败、延迟资源、动画及 Puppet 不借此开放。显式动态资源准备保持原优先级；没有重复解码或上传。
- 动态层初始配置 getter 明确 unavailable。官方已经证明创建时深副本，但实现仍开放：直接序列化任意动态参数会触发数组 indexed/inherited getter。独立审查发现这一副作用后撤销本片动态捕获，旧 create/rollback 路径保持原行为，没有另造递归图准入。
- `perspective` typed setter、create 的 `size`、text wrapper、Puppet/composition clone 均未完成。下一片优先接已有投影/尺寸字段，再处理文本包装，不按本样本增算法。

## 验证与证据身份

保留根：`.artifacts/tmp/initial-layer-config-20261012`，所有媒体运行使用隔离副本及 HOME，真实媒体只读。

- 最终 Debug build 成功。App executable SHA256 `3c29cde3342cf211749de8b570728fbf2dfd76a2e56e2dbf6a64bb7d7540beb0`；debug dylib `9a9db83c10efef8e7b6688dc9adbf8664e049f7a8dda37a8f29ad07f4409efdf`。
- `after-final`：同原始 scene.pkg `9f305bc9970f1fb50867d114ce967fec3c9d1aa6dbc69031ffd16fba55ab4d70`，三点往返鼠标输入均有截图，零 TypeError；拒绝仍仅上述 6 个特殊资源 owner，最终 surfaces 1→0、gpuDrained=true。截图可见前景/背景随输入变化；未证明精确官方轨迹或 perspective 一致。
- `regression-final`：3761619125 仍有 115 个唯一首帧 effect 阶段，其中 78 个实际 material 阶段、37 个作者关闭透传，全部 succeeded；GPU 正常排空。保留前批 deformer 链，没有将 claimed/encoded 的局部计数误作总阶段数。
- 初始配置真实 C/Swift 门 2 方法通过，C 48 项事实零失败；含副本隔离、实时快照变化、配置 identity、编码错误和动态 unavailable/原事务兼容。原 QuickJS 主门通过。资源门 6 方法、29 组输入通过，真实 MTLTexture 引用相同，decoder/upload 为受控边界；不能单独证明 GPU 绘制。
- 现 initialization transaction、dynamic layer runtime、dependency visibility owner、snapshot atomicity 门均通过。首轮 atomicity 因配置 setter 放入 frame snapshot 文件引入 VM 链接依赖失败；将 setter 原字节放回 catalog 所在 LayerHost 后原测试直接通过，未新增伪 VM 桩。首轮 Swift 夹具误把 journal commit 当成当前帧发布，修正为原 SnapshotResolver/publish 路径后通过；红绿收据均保留。
- 官方中性收据 `official/neutral-contract.json` SHA256 `199978e148a002b2ef62cabd6ded867e2818010e67c2c831572d6734eae1d200`。两个自有 guest 输入及窗口已精确清理，receiver8528/session/version不变。

验收上限为隔离 direct Host 的 VM/资源/GPU/屏幕呈现；没有覆盖普通桌面 dispatch、所有属性、真实音频输入、完整官方视觉或全样本兼容率。静音夹具下频谱为空，不能据此判频谱缺陷。独立审查已接受产品职责和反例；最终冻结身份/治理门/清理结果保留于同根收据。

产物收尾：隔离样本副本、HOME、早期App输出及重复截图已清理，保留约30 MiB最终/基线证据及一份 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData` 增量缓存。标准证据晋升工具因现有总缓存预算拒绝新增，受控 prune 无可清条目；保留本根的有界唯一证据，不提高预算或删除未知旧材料。既有218字节 `.mimosa` 残留仍按原处置保留，未归入本批清理。
