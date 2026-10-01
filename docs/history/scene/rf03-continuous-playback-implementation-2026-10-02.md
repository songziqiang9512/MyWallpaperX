<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF03 连续排放四方法后继（2026-10-02）

> **历史证据 — 非现役入口**。当前入口：[兼容路线](../../scene/scene-compatibility-roadmap.md)、[能力台账](../../scene/semantics/coverage-ledger.md)、[运行证据](../../scene/semantics/runtime-evidence-current.md)。未改受保护三份总表。

## 实际结果与责任

默认连续排放的已准备单 root 粒子系统现在可用 play/pause/stop/isPlaying。原先模拟器已能持续发射，但 preparedPlaybackWork 要求非零 rate 必须有正 duration，导致作者 init.stop 抛 TypeError、红色粒子继续出现。依据[官方 emitter Duration](https://docs.wallpaperengine.io/en/scene/particles/component/emitter.html#duration) 的默认0无限行为，移除这个不必要的有限时长限制；仍用既有 C journal、Swift typed意图、per-surface simulator与唯一compositor。

独立终审又发现 parser 将显式非法 duration 折为 nil，修复为在 SceneParticleEmitter 保留 hasMalformedDuration 并在同一 prepared admission拒绝。producer 是 SceneParticleDefinitionParser.parseEmitter，覆盖bool、不可解析字符串、数组与无value字典；缺省/null与数值0分开验证。没有新增模拟owner或时钟。设计见[D11](../../scene/design/particle-playback-state-design.md)/[D4](../../scene/design/script-component-api-design.md)。

## 冻结与反例

工作目录为主分支 codex/engine-refactor-program，批次起点 HEAD 85415320 加已验收五批未提交文件；只对新增3产品、2测试及明确文档差异负责。隔离证据根 `/private/tmp/mwx-rf03-continuous/`：baseline保存本批前字节；review-v3/manifest.json与owned.diff保存受审代码/测试；最终文档措辞把App缺省duration与Swift的0/null分开。20项实际App载荷见payload-v3.json；frozen-v3.app严格deep验签，Team H9QWU9XN8R，CDHash `a790e6ab53c1e82725ebe0c2479e8d006f50504e`。

- simulator-red.log：真实 Swift parser/simulator 六反例失败；simulator-green.log初修通过。
- app-red.log及app-before：旧冻结RF07 App的真实 init.stop TypeError，GPU仍完成、红色粒子未被停止（ready/after两图均55696红像素，绿色peer10471像素）。未以非黑或route代替命令成功。
- malformed-red.log：终审四个非法作者值反例先失败；simulator-parser-v3.log最终7测试通过（12.440s），另含delay/remainder暂停、重复play不重启、stop后重启delay及ID连续、零容量/null。
- focused.log：author、transaction、runtime三模块全通过；runtime53测试含10个既有skip，不能记成全部执行。此邻接门先于新增malformed字段，最终parser/simulator和App按v3执行。
- build-v3.log：最终完整Debug构建成功。中间build-v2因局部编辑误及child初始化产生编译错误，已修，日志保留，不作成功证据。
- app-v3.log：最终三个独立App场景通过，73.656s；六PNG，最终stop两图红像素均0，其余两场景红像素55696，所有图绿色peer10471像素（pixel-oracles.json）。缺省duration init.stop首/后图红色消失且绿色peer保留；pause保留warm-up存量继续模拟；stop→play重新出生。实际frame0命令revision一次消费、frame0/1/2 GPU completion、后续terminal截图和gpuDrained停止链闭合。
- code-health-v3、defense-v3、design-gate-v3通过；doc-gates.log当时25文档测试通过。独立astra high复核接受v3，无剩余阻断finding。

## 未验证边界与下一批

duration=0/null由真实Swift门覆盖，App为缺省duration。未新增显式emit、多emitter、children、随机周期、reset、模拟迁移或官方像素parity；未做性能收益声明。实际硬件GPU故障和物理多屏不在本小批。

按用户要求本批随3产品/2测试和设计增量按职责提交；提交号由Git记录，不在正文制造自引用。下一批是RF05初始属性隐藏但被普通image consumer采样的provider：先三对照复现deferred资源缺边，再修既有selector；之后推进D1现有isolated scope的真实组源与图片父子树闭合。
