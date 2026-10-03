<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# D1 普通 composition 背景与作者顺序

> **历史证据 — 非现役入口**。当前权威：[D1设计](../roadmap/batch2/composition-render-target-design.md)、[兼容路线](../roadmap/scene-compatibility-roadmap.md)、[运行证据](../capabilities/runtime-evidence-current.md)。

2026-10-04；基线 `820581e7c23055100a7609c695e0d8b984b59034`。设计见 [D1](../roadmap/batch2/composition-render-target-design.md)，稳定职责见[架构§3.3](../architecture/runtime-architecture.md#33-保留事务安全不扩大视觉失败半径)。本记录只接管这次有界实施与验证，不定义完整 Scene 兼容率。

## 问题与实际画面

自有场景固定蓝背景、黄 child、红非 child，根使用自写 RGB 反色且保留 alpha。旧 App 的无效果正控制正确；省略 copybackground 时只把 child 变蓝，漏掉背景及根前非 child；显式 true 则在 `utility-composition-subtree-shape` 拒绝整组效果。旧 App 三案为一项正控制通过、两项方法失败（五处子断言），均有实际 GPU completion 和 Metal readback。

修后十项独立 App 案例全部通过：省略/true 输出黄背景、蓝 child、青根前非 child；false 保留蓝背景与红非 child；非 child 移到根后保持红。child 位于根前、无效果组、空组 false/true，以及脚本隐藏 child 后新背景覆盖旧像素均通过。每案 ready/after 两次 Metal readback，固定 ROI 面积至少 99% 在通道误差 4 内，中心像素同门；不是相邻 GPU 帧或整景官方 pixel parity。

## 实现

现役 RuntimePlanner 在初始化或 topology revision 形成一份 Execution，准备、容量预检、实际 encode 共用根位置和成员顺序。删除无依据 prefix、parent-before-child 与末后代触发路线。缺省 copybackground 为 true，保留字段存在性；首次实际使用才从 enclosing pass 复制背景，false 透明初始化，预留不采像素。无效果组只重排、不增加 target；动态删除 child 更新现有投影和同帧计划。pool、pin、generation、取消/completion 与唯一 compositor 保持原 owner，旧 coverage 和零调用诊断退役。

## 冻结与验证

- 22 个产品路径（含两项删除）的 canonical SHA 清单：`75e0ee4caace42e2e68775e7510fc42c903f40ec1178f97edd0c91efe5b7b1be`。Debug build 通过，构建前后产品与并行项目文件哈希未变；运行 Xcode 后出现的 `project.pbxproj` 自动整理差分排除本次提交。
- 修后 App executable SHA256 `4eceed7901cf20186a2ad822cda506362614a6721aca84665e01221ec743aa11`；debug dylib `4d1f704c5eb096b4a659e88ab8c3ad3948510d9c0298dbd30060d98981a7482d`。
- `test_scene_composition_authored_order_integration`：10/10 PASS，151.030 秒。无 stock 实现读入，所有效果和底图输入由测试自己生成，期望事前固定。
- utility 13、topology/realtime 19、runtime bridge 14、submission 3、dependency 28 项通过。旧 fixture 缺字段/签名已最小同步；submission 上一基线的 opaque 类型遗漏一并修复，失败 trap、真实 owner 与 mutation 断言保留。
- 原有 source suite 的 13 项 App 回归通过（嵌套、子层 effect、空后帧、resize、取消恢复）；该次 native setUp 的旧 fixture 缺字段修复后，独立重跑原生门 28 项：27 PASS、1 skip（额外 named-model App 类未设置专用入口，不计入运行）。合计 23 项实际 App、104 项定向回归通过。
- 独立只读审查接受 v2 产品与新十案；复算 before 六张、after 二十张 PNG，60 个 ROI 每项 79524/79524 像素精确命中，最大误差 0；对应三案输入与 preregistration 一致，91 个自有包成员哈希一致。同一审查者再复算原有 13 案的 28 张 PNG，并核对实际 GPU clear/pin/completion 五项全真，最终产品与运行有界 ACCEPT，无新增 P1/P2。

## 仓库门与已知基线失败

代码行数、依赖、防御、设计、文档职责/链接/健康、断言与产物门通过。语义/验证登记 116 项首跑有四项失败：本批删除文件的历史链接及 RF04 两个资源文件漏登记已经修正，目录/链接两项重跑通过；其余 authority/completion 两项是同一既有 inventory 问题。独立 lexical 核对 HEAD 与当前均为 66 个声明、51 个文件，登记为 65，完整文件计数相等；唯一漏项为 `SceneGraphPreparationAdmission`（820581e7 引入且本批未改）。它有实际资源状态，不能伪分类 passive，也不为过门提高阈值。后继应审查该资源 token 的计数归属；本批不声称全仓门全绿。

## 官方证据上限

固定 Wallpaper Engine 2.8.42，wallpaper32 SHA256 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`。合法官方客户端通过公开 CLI 加载自有 256² 输入，512² 客户区；RGB 反色片段独立编写。全屏 effect off/on、parent 根前后位置与三色几何正控制后，直接区分单 child、非 child 的根前后位置、copybackground 省略/false/true 和空组。独立审查重算 22 张呈现 PNG 的固定 ROI 与 7×7 邻域，一致。

两个截图间隔约 0.2 秒，不是编号连续 GPU 帧。Scene/fragment/窗口身份随捕获登记；完整 used-input 收据为运行后采集，不能回写成事前全输入冻结。多 sibling、嵌套与生命周期属于项目一致性推广及回归；官方与项目底图使用不同格式，不声称同包逐像素 parity。passthrough、特殊 transform/clip、任意组 alpha、device loss 和多屏未由本批证明。错误 shader 构造、错误 intrinsic 尺寸和无效序列化的先导尝试排除。

最终日志、我方截图、输入身份和官方数值收据保留于本机 `.artifacts/scene-evidence/runs/d1-composition-order-20261004`，14 天限期；原始官方 PNG 仍在仓库外 `/private/tmp/mwx-d1-composition-20261004`，不复制不透明官方资源。两份临时 App 在提取后清理，HOME/缓存随隔离测试释放；保留 `/private/tmp/mwx-scene-next-build/cache` 一份构建缓存供连续迭代。
