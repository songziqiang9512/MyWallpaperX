<!-- document-role: historical-evidence -->

# 粒子初始化位置与事件继承资格（2026-10-23）

> **历史证据 — 非现役入口**。截止2026-10-23；两轮均停止选公式，产品未改。本页不授权重复旧实验。

本文保存两次有界研究及停止原因，不决定执行顺序。历史命令只用于复现；当前实现与下一门分别由[粒子能力表](../capabilities/particle-component-coverage.md)和[断点队列](../roadmap/scene-open-breakpoint-queue.md)维护。两轮均未修改产品，不能作为样本修复或性能收益。

固定官方客户端为 2.8.0.42，EXE SHA `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`。本机正式包保存冻结自有源码、PKG、协议、原图、采集时间、测量脚本、全部候选误差和独立审查；原始数据与结论分开，不复制官方算法。

## 位置映射：六候选全拒

<a id="position-mapping"></a>

产品基线 `809219140`。自有 `80025025` PKG SHA `5b0419262629bb94e0a30f348d9d2b7a541966dc73d783a7c29c8a049c500f1b`，640×360 正交、Count5、bounds .05… .85、半径50、零初速、寿命900s。五板分别使用 +Z、两个带符号单位斜轴、仅改发射径向的 +Z 反例及单可见出生；没有 pointer、音频或后续力场。

- 两次原始采集在派发后31.57…34.60s，非重叠间隔2.503s。
- 49条固定控制记录（44个独立中心，尺与中tick重合）残差≤0.767px；A-D各5点、E1点。两图点集配对差0px，仅描述捕获结果。
- 默认Z的A/D同点集；有效 `(+X sinθ,+Y cosθ)` 列表误差≤0.636px，首可见点对应冻结phase .05/k0。现有 `(+X cosθ,+Y sinθ)` 不能复现该固定点集；不因此识别官方内部basis、角度符号或隐藏粒子id0。
- 六个冻结通用候选没有一个同时匹配ABCD。B有一点还超出全部候选共同假设的投影圆范围，调平面内角度不能解释；发射源、轴/半径/轴向空间与投影尚未分离，不能唯一归因circleBasis。

结果为 `STOP_UNKNOWN_NO_FROZEN_CANDIDATE`。未选最近误差公式、拟合或重跑原矩阵；原位置、初速 Rodrigues 旋转、三轴共享RNG及空间资格保持。零初速板不证明速度方向；311小提琴和379漩涡的实际方向/密度没有关闭。

必要证据：`.artifacts/scene-evidence/runs/particle-position-mapping-20261023/`，其中ZIP 1,951,488B，SHA `ab91428fad3dd44b2c9eefe7d9f52f9f10255636df7aca988f8f4e6ed58fd24b`。官方预览按精确title关闭、校验后移除自有guest stage；VM/主界面保留。文档最近门首次有一项正文预算/导航收据失败，修正后仅该失败测试补过；其他四模块通过，未声称全套重跑。

## 死亡事件继承：输出组合未知

<a id="event-inheritance"></a>

重新核准真实 `3742497499` 后，174是默认隐藏的standalone副本，不应把其无event context的拒绝当成颜色漏接。活跃135的死亡子系统在 `multiplysize`、`setopacity` 两个未支持mode处被模板门拒绝，已有setcolor snapshot链未断。父死亡事件已携带完整size/alpha，现context仅提取color；若后继有资格，应扩同一typed snapshot/initializer owner，不另建事件或渲染链。

当前 `b982beef…e5fa` 优化Debug原包20s静音基线实际呈现人物、水面、文字和气泡，正常停止；同输入project/pkg无改动。135有GPU输出而child仍被拒，不能用root计数证明水花。父life1…4、size20…222，child每死亡事件burst1、life .2… .30000001、最多7并发系统，且沿原instance rate推进；作者顺序为size4→setcolor→multiplysize→setopacity→alpharandom。单帧官方图和本轮混合画面都不能可靠圈出短促splash，实际可见收益仍未资格。距离算子的旧UNKNOWN独立保留。

自有 `80025026` PKG SHA `45ec5a210a08740a7d34a431c1999e97c98cbd3d7a0737c731f6c93c0a75ab9c`：900×600，六板全为自然eventdeath；父life1s、固定size2/3与alpha .25/.75、无fade/size/alpha算子；child life900s、零运动、青色加法Sprite。独立root同材质参照预先固定尺寸2/3/4/8/12与alpha .125/.25/.375/.5/.75；E另在继承后放第二个Alpha初始化器。

- 两次采集在派发后37.95…40.982s，间隔2.502s，固定exe/session/title与输入哈希检查成立。
- 61条固定控制记录（55个坐标中心）最大残差0.569px；A不继承的death载体正控成立，无检测到的红色父残留。两原JPEG字节相同，测量patch差0，只记捕获结果，不强化为独立渲染帧或长期稳定。
- 所有固定匹配完整保留：尺寸A/B均匹配 `[3,4]`，C无匹配；alpha D/E/F分别唯一匹配 `.25/.125/.75`。尺寸和alpha两组都没有命中任何冻结joint pattern。

结果为 `STOP_UNKNOWN`。不补候选、挑最近、调整容差，也不从参照匹配推断父death终值、set/multiply内部操作或作者顺序。当前mode仍拒绝；后继须先区分Alpha初始化本身的组合语义、事件输入与尺寸消费，再资格真实水花，不能跳未知mode来放开模板。现373索引中未找到非374的新mode消费者；独立旧setcolor门只能证明不回归，不能冒充新mode受益。

必要证据：`.artifacts/scene-evidence/runs/particle-event-inheritance-20261023/`，普通14天。两轮独审接受严格UNKNOWN；未构建修后App、未做候选性能对照。只关闭自有预览并清理自有stage，VM/官方主界面继续运行。
