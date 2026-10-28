<!-- document-role: historical-evidence -->
# 并行 SceneScript 兼容切片：2026-10-28

> **历史证据 — 非现役入口**：本文集中保存本批选择、已执行验证、失败和未验边界；当前能力归[API表](../capabilities/scenescript-api-coverage.md)与[属性表](../capabilities/runtime-input-property-coverage.md)，剩余用户差异归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

基线 `327337b8c`，Root 独立树 `MWX/scene-capability-followup`。本批只采用原 Vec3 类缺失方法及现有属性编译器的输入域修复；共享 Program、typed snapshot、clock、资源与唯一 compositor 不迁移。性能候选撤回，官方音频实验未取得语义资格。

<a id="slider-bool-seed"></a>
## Slider 声明与 Bool seed 的输入域

真实 `3662790108` 的 layer1459 alpha 使用 `scriptproperties.dragopacity={user:"dragbaropcity",value:false}`；项目 `dragbaropcity` 是默认0.5、范围0…1的 Slider。原 codec 已把该 Number 按真值投影为 Bool，准备期 compiler 却只接受 Slider+Number fallback，将此键标成必须重建。

既有[嵌套输入链](runtime-evidence-index.md#e-v4-scenescript-nested-property-live)保持；修复只在原 compiler 将此输入 checkpoint 保为 scalar，seed 取合法 Slider default；原 wrapper/Bool fallback、codec 与 VM 实际值不变。不能把保留数值 checkpoint 解释为恢复任意 Slider 精度：现 VM 中0为false，0.25与0.5均为true。

修前两产品文件配新 nested 夹具取得行为红证：仅两组改名输入各自的 numeric-producer/live 四事实失败，其余79事实保持；修后 parser/LiveState、实际 QuickJS 输入域、原 user-properties 和 live-state 四模块23测试通过。真实 QuickJS 在同一 runtime 冷0.5→热0→0.25→reset0.5持续断言 Boolean `typeof` 与 `===true`，并保 scalar checkpoint、原 Bool seed、同值无revision及异常 owner 的原子拒绝。嵌套、坏/缺/重复定义、非法替换和 direct-alpha 邻例保原边界。

## Vec3 反射与作者释边
<a id="vec3-reflect"></a>

原共享 Vec3 类补充 `reflect(normal)`，独立向量代数为 `I - 2 dot(I,N) N`，法线归一化由调用方负责。[公开API](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/Vec3.html)明确返回 Vec3 和归一化前提；页面未明确对象 identity，本机实现/门证明返回新 Vec3且不改两操作数，不冒充官方对象身份实测。Vec2/Vec4覆盖未扩，产品仅增2行，无新状态或owner。

现有 C 行为门修前红、修后绿，两门通过；覆盖轴向/斜单位法线、切向/零向量、结果类型与非别名、双方不变、改名/计算属性调用及下一callback。真实 `3437487219` layer90 是 origin owner，movement="1"、timedate默认true；长按约1.24s后移动取得direction，release后仅越界才调用reflect。作者 accelerationMultiplier=0，只能验首次越界clamp及owner后继可用，不认持续弹跳。`3299228616` 相似脚本绑定visible，先在Bool `value.add`失败，不计本片受益。

## 整合验证
<a id="verification"></a>

Root 组合 Debug 构建成功，34.16s，6218构建输入无漂移，真Team签名验证通过。两组局部独立审查未发现新P1/P2；这不代实际运行或整样本裁决。

| 项目 | 截至本记录的事实 | 验收限制 / 待补 |
|---|---|---|
| 构建身份 | Debug候选App `9a1f3a82…8174`、dylib `cf22150f…341b`；基线App `bb5fa7e8…8e05`、dylib `ca58e856…9b39` | 基线产品为327原字节；候选3产品文件与冻结构建一致，Team H9QWU9XN8R；完整SHA见归档 |
| 343 inside反例 | 中性手势未触发边界反射 | 只作不应命中反例 |
| 343同手势edge A/B | held均originY≈4123/scale≈0.985；基线释手后90.origin报TypeError并disabled，停在4123；候选释手后4120/scale1，无VM failure | 两端exit0/GPU drained；只闭这次约3场景单位的释边clamp，不认连续弹跳、重复拖动或整体collision |
| 独立361 | 未参与选题的真实原包运行PASS | 仅相邻渲染/退出，不是reflect第二受益样本 |
| 366初次bounds probe | ready耗时54.1s，随后运行；1459 alpha callback完成、bounds中心约(0,-0.875305) | 请求ready后7s，但外部60.08s先终止，无正常stop/drain；属预算错误，不能写死锁或候选回归，不能写热更通过 |
| 366 direct长按/热更 A/B | 同点位、13s、静音及0.5→0→0.25→0.5；基线接纳true/false/false/true，候选全true。候选有效Metal图白bar隐藏再恢复，基线始终在；各单session、同window/surface1，exit0/GPU drained | 1459 update写shared，1351更新bar；两者无propertyInputApplied日志，不冒用其他callback。无alpha帧遥测；PNG完成时间非采样时间。只证Host热更及Boolean投影 |

两端366实际准备约53–55s，不作启动性能结论。direct runner 的 `--mwx-debug-scene-live-property-sequence-json` 调用Host；只认这一入口的接纳与实际consumer。没有面板编辑、持久化Reset或daemon IPC证据；snapshot generation属帧快照，不是ScriptProgram代次。daemon runner的stable分支跳过property probe，非stable分支随后强退或切景，发送接纳不能顶替ACK。本批未新增runner或参数。

## 未采用与研究停止
<a id="not-adopted"></a>

CPU子片候选在denseSprite约-26%，真实Trail仅约-3.1%，稀疏/空输入约+11%/+18%；收益不稳且有反例，产品候选全部撤回，不认采用或App收益。只保原门及必要实验收据，不把bench结果升格为整体性能或能耗结论。

官方 Audio 两个载体均崩溃，资格 `STOP_UNKNOWN`；无mode语义结论，未改产品，也未运行Vortex。来源材料对mode的矛盾保持未资格；实验失败不登记为引擎缺口，不猜可见算法或重跑失格载体。

## 保留与交接

必要原图、原日志、修前失败、独审、红绿及签名/输入身份归主工作区 `.artifacts/scene-evidence/runs/script-compatibility-20261028-{reflect-before,reflect-after,properties,research-stop}/`，普通14天/每包32MiB/总5GiB；retention报告明列原始SHA与省略的重复截图、HOME和可重建shader。修前App、样本副本及HOME已清理约1631MiB；候选App暂保供下一批复用，连续迭代保 `/private/tmp/mwx-scene-followup-20261028-q5apo4lx/build-cache/` 一份缓存。官方失败的两个小型guest测试目录清理被Parallels transport拒绝，未谎报删除；虚拟机保持运行。两个已完成子树的App归档接口因 pinned/workspace 保护拒绝，保留原树，不绕过保护删除。

本记录不认完整壁纸、宽collision、全部属性/原生面板Reset、普通daemon属性路径、官方同phase/parity、HDR/Release、多屏或性能收益。正式队列仅保仍未闭范围，不能以构建或少数callback自动结算。
