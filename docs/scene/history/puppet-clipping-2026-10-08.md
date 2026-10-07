<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。当前规则见[Puppet 裁剪合同](../capabilities/puppet-clipping-design.md)，状态见[高级对象表](../capabilities/advanced-object-coverage.md#34-puppet-部件裁剪)，剩余任务见[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# Puppet 部件裁剪实施与有界验证（2026-10-08）

起点 `01b101ee`：真实聚光灯 `3791967416` 的固定眼部第105帧，官方闭合而 native 虹膜仍露出。作者附件与 alpha0.24 的副本均保留。仅删除两枚眼 MDL 的裁剪记录，官方复现 native 露虹膜，因果断点是未消费部件裁剪，不需要加附件、去重或引入3D depth。

## 官方公开行为与输入控制

仅消费[公开裁剪文档](https://docs.wallpaperengine.io/en/scene/puppet-warp/clippingmasks.html)、作者包和客户端黑盒，不消费私有实现。固定官方 2.8.0.42，executable SHA256 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`；窗口1512×982、位置33/78、指针789/569。每变体10 owner 在 init/tick2/tick10 确认 paused 与请求帧，body clips 固定、眼部帧为0/105；真实包只读，隔离副本逐 entry hash 保持非变更资源。

全黑 paint 隐藏虹膜，128 显示约半覆盖；移动 target ordinal 恢复原虹膜，self-only 全白仍隐藏，确认零基 part 域和排除自身。单 source 与两个 distinct、同几何/UV/骨权重 source 的0/255/128端点对照，470个信号像素的单/双系数为0.5127/0.5004，6px分块中位数0.5134/0.5186；未见0.752或1的叠加。动态效果噪声和残差保留，这支持 opaque 重叠不重复累积 paint，不区分所有内部合并算法，也未证明 fractional provider-alpha 或官方 nested parity。

公开作者数据按当前 CPU formula 离线复核：small parts0…5在6542帧0/105全为1；large5…9及body2/26/27/29的相关clips无alpha轨道，最低0.99999988只是Float归一化舍入。本样本不存在 consequential fractional source coverage；这不是所有Puppet源alpha均为1的合同。

## 实施与验证

Format 保留 draw-part/clip IR 与严格边界；Load 准备paint/关系；同pose GeometryProduct 在现有main/named encoder边界准备R8，再按原part顺序直绘。pool/预算/submission pins复用既有owner，ColorBlend与普通fragment均只衰减一次预乘RGBA。max opaque union、nested交集及cycle/局部失败见稳定合同；非一source vertexCoverage继续局部关闭。

首次18个产品文件的冻结SHA清单 `product-freeze.json` 对应以下固定样本运行；首次独立冻结审查接受该输入范围。随后发现并修复共同reader回退，后续身份分别记录，不将旧运行升级为最终代码验证。格式与既有mesh/rig/bone门55项，53通过、2个旧可选fixture跳过；辅助寿命/顶点发布17项通过；五个既有harness输入清单修复后的21项通过，日志为 `/private/tmp/mwx-puppet-inner-harness-20261008/focused-final.log`。固定运行所用Debug build与签名通过；这些不证明官方全域或性能。

受控 native `eye0/eye105` 两运行exit0、未超时、GPU failed0；目视核对0保留、105闭合后不露虹膜。受控App SHA256 `7783b19272bbb938d843aa90b10eec51c700cf7f879ccc0a6e45868a027e415f`、CDHash `52934d2330cdd2f9eaad7de14ef3a475f6cac75a`，team `H9QWU9XN8R`。通用benchmark整体FAIL仅为固定指针的hover输出不足，不改写为PASS。

原包回归App SHA256 `154319c54c4b25186ec372ea76f5abda6aa484d4ac341a1869ae33f856892bf3`、CDHash `678dd4effcc41d4ba92ab5533dfb2f748800aad2`，签名在运行前后均验证。原包32秒direct Host回归exit0、未超时；loaded textures48/48、6个动画layer/10clips（两body layered），completed/presented200、GPU failed0。series0004主画面已目视核对，无残留intro；动态时刻与官方不同，局部图案变形仍须固定姿态核验。整体FAIL仍仅hover；重DEBUG telemetry completedFPS7.480不作为性能采样或性能通过。

## 跨样本复审与CPU修正

广义资源扫描255个MDL，其中113个MDLV0023被候选新增strict suffix拒绝；按实际image→model→Puppet引用及HEAD A/B复核，29条新增退化涉及19样本：28个合法零长度part和1个既存stride48精确七零后缀。其余84非Puppet拒绝不计产品回退。空part需保ordinal并保持连续全覆盖，精确空后缀只按确切字节形状兼容，不能放宽畸形记录。

修正后161个真实Puppet可达资源/51样本完成生产reader CPU回归：29条恢复，旧130条position/UV Float bits与indices SHA、draw-part/clip IR完全相同，2条旧MDLV0013仍拒绝，process unknown0。报告 `/private/tmp/mwx-clipping-corpus-20261008/reachable-puppet-after-fix.json`，产品冻结清单 `product-corpus-freeze.json`；46项focused为45通过、1个旧fixture跳过（`corpus-fix-focused.log`）。这些验证不运行App/GPU/VM/动画，不扩为视觉或格式全域接受。

当前语料只有1样本、3资源、4条clipping规则；其他可达样本只取得reader非回退证据，不能称51样本获得裁剪改善。

## 跨样本App与最终冻结

reader修正后的签名App SHA256 `dd825fed6edd5b4223396cab290d70b38fdbb47fe7ddc1f60e1fd4bc99125465`、CDHash `371fa0105050f66d137af7f5a50929af044c9d8f`，运行前后签名均验证。`native-regression/report.json` 的三个14秒direct Host代表运行中，`3396722575`和`3767232084`严格benchmark PASS、exit0、未超时，completed分别63/525、GPU failed0；前者4个Puppet clip加载，后者保留既存静态mesh，不据此称有动画或新增裁剪受益。

`3233141951`在startup ready70.445545秒并取得首张非黑snapshot后，超过duration+60秒预算，被终止为exit−15。报告保留timeout、缺终态性能/退出和后继输出等失败，三输入报告为2/3 PASS。该输入只证明纹理24/24及5个Puppet layer/6clip加载、首图存在；慢启动因果未定，不能称PASS，也没有证据将其归为本批Puppet回退。重DEBUG观察的两成功运行均不具备steady-state性能资格。

最终复审补齐空clipped source不阻断健康union，并在load时去重、排self/empty执行source列表，原DTO保持不变；10项GPU门通过（`clipping-gpu-last.log`）。最终18文件冻结为 `product-final-freeze.json`，`build-corpus-final2` Debug构建与 `sign-last` 签名成功。最终App SHA256 `40281522de090c633987e67c0a8cec3cbbe5ddf1c3100baebc4531cf9b740dbc`、CDHash `7b05d735af121cb378eb843ac4f89659561fbef2`；`native-last/report.json` 的固定eye105复验exit0、未超时、纹理48/48、10clip、completed104、GPU failed0，运行前后签名验证，主线程目视series0000闭眼无虹膜。整体benchmark FAIL只含固定指针hover不足，未改写为PASS；新身份只做该定帧复验，不能代替前述旧身份原包32秒或跨样本运行。

## 产物与声明边界

核心证据压缩保留在 `/private/tmp/mwx-eye-controlled-20261007/retained-evidence.tar.gz`（约31.68MiB），含原路径manifest/hash、最少代表图、运行报告、日志与脚本；跨样本PNG另留单包小于32MiB。主线程清理App、样本副本、旧截图及重试输出；自有VM目录与Mac共享副本已删除，VM已恢复suspended。新语料/census `/private/tmp/mwx-clipping-corpus-20261008` 留供下批，连续构建只保留既有 `/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d`。promote因现有总缓存超额拒绝，prune-expired无可清登记包，未知归属未动；证据暂留上述有界/tmp包，不另建保留体系。

本批完成有界裁剪及reader非回退验证；最终冻结身份已重验固定105闭眼，跨样本App仍保留两成功代表与一独立慢启动失败。nested仅本地GPU成立，source alpha非一、未知格式、软边和更广官方pixel parity、原样本局部图案/完整视觉及性能仍未验收。后继转当前全样本的共同能力缺口；没有整样本兼容率、普通产品入口全流程或Release结论。
