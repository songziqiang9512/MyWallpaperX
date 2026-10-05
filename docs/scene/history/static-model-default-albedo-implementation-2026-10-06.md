<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。现役职责见[运行架构](../architecture/runtime-architecture.md)，后继顺序见[暂停交接](../roadmap/scene-maintainer-handoff-2026-10-06.md)。

# Static model 默认 albedo 与太阳系交互收尾

起点 `fa02f6bf3c21c7454aa7134dadcf4e5157e25cc4`。用户要求本批提交后暂停Goal；后继执行说明见[暂停交接](../roadmap/scene-maintainer-handoff-2026-10-06.md)。稳定输入优先级由[Sampler合同](../capabilities/sampler-alias-precedence.md)拥有。

## 实际修复

资源准备原先因slot0为nil跳过模型部件。现在独立证明无条件、普通颜色sampler的default asset，由descriptor传给既有VFS/texture loader，再走原模型draw/depth/shadow/compositor。显式坏路径不fallback，uniform unavailable与默认输入解耦，rejected仍拒绝；没有新renderer或逐帧解析/分配。

源graph identity、potential条件声明、宏改写/别名/生成声明、combo名称、数组与用途反例都受控。第一实现误将default依赖整shader prepare：作者两槽readiness导致`texture-readiness-unavailable`，补完整八槽仍因不相关格式输入报`texture-format-unavailable`。两个App尝试与baseline像素相同，明确不计成功。最终按固定模型不执行custom shader的职责移除这个依赖，保留独立元数据证明。

## 真实可见结果与边界

JUNO隔离fixture含原MDL、7材料、7TEX原字节和自有固定场景/相机/灯光；9个geometry segments，目标foil_silver为3418 vertices/3087 triangles。包SHA `bca7e0c27da595134f519d7d0925b4709f09bdd11398ea734999f95cbc470844`。基线缺银色机身及天线盘，最终恢复大块主体、盘和支撑连接，左右太阳能板等原材质保留。原完整太阳系内JUNO导航和材质normal/PBR/官方外观仍待验。

基线dylib `af9e4da0679d218671d6bece89a7a5f7be5ae4a7f2e962be7f6fae238fdb23b4`；最终 `80dd07c572a527d14a10ca5c178d5610bb4913941b124fb2cfbe96dd75ebf37f`。两次同包运行exit0、surfaces1→0、gpuDrained=true。根Agent实际看原PNG；差分bbox `(745,607,2098,1344)` 只描述此3024×1964视角，不是几何准确率或性能结论。

本轮原太阳系、前批App身份另验证：媒体size1→1.5与resize0.75→1成功、同surface/window保持；中文水星标签受控双击进入近景；原生右/左箭头进入水星并返回总览。先前点击英文层640不切换不能作为输入bug。默认size1.5面板重叠尚无官方对照；水星近景大片发白为下一已见问题，不关闭整景。当前专项粗略估计约65%，不是完整正确率。

## 验证与独立审查

- 最终CPU材料绑定/property **10/10**，含默认白/彩色、null/省略、explicit/user守恒、宏/条件/graph identity拒绝及无关variant失败正例，源码无漂移。末轮审查新增EMPTY宏前缀隐藏条件声明及normal/noise/graph alias/registry数据用途反例，两个定向门 **2/2**，62.053秒、无漂移。
- 实际reader→resource→frame→Metal **5/5**；旧HEAD resource反例只画explicit part，最终默认白/彩色与材质色均落像素，坏输入局部拒绝，两帧一致、预算回收。旧宏rename/array错误的独立红例保留。
- 既有sampler default门 **5/5**，最终Debug build成功。结构13门中2项仍是既有analyzer66/65失败；其余职责/依赖/防御/文档门见本轮日志，未抬基线绕过。
- 独立只读终审接受，绑定 `product-freeze.json`（SHA `bc960ac1848f7bb0d2a2b65e0f3d0b39585ebaedef071219017e8d517adbe7bf`）的10个产品/测试路径并实际看前后原图；末轮两个P2已关闭。官方中性合同另经独立批准：自有generic4 plane的null/省略与显式white图相同，missing不同；不证明内部机制、MDL/normal/reflection或官方PBR parity。

## 保留与清理

最终证据按四个独立运行范围保存在 `/private/tmp/mwx-solar-layout-20261006`；每包低于32 MiB，原PNG未转换，包内manifest逐文件核SHA。保留至2026-10-20。必要画面限6张，其余重复截图不保留。默认纹理包含JUNO原输入pkg、前后App身份/PNG、关键CPU/Metal红绿、10项冻结源码和官方自有探针包；其他包分别保留属性/resize、原生返回及中文双击证据。

| 文件 | bytes | SHA256 |
|---|---:|---|
| `default-albedo-evidence.zip` | 6766515 | `b31b4ff4986abc083d8b2e7c66e30262f9898ad8770b20644aaa14e04b947e11` |
| `size-resize-evidence.zip` | 27787471 | `9cc8f0934bfd1bdd1d64f43f6b285f341f0d8d3c233ed4a399ff50b97e1ef055` |
| `native-return-evidence.zip` | 21440065 | `5378ea7bedebcb006c836ede47dc74278d9fcba9df84b3ca25f99cfe8da246a2` |
| `chinese-doubleclick-corrected-evidence.zip` | 16658893 | `ede4b91eb5847afae4b66dea88f641fb7a49e4545edeb0cc46cc9416b1f106f8` |

已执行既有prune-expired（无到期可删）；默认纹理包promotion仍因总cache预算不足被拒，保留原位，不扩预算或删除未知证据。原104.9MB聚合包由上述范围包替代。

已用完的本轮App、HOME、样本副本、重试编译目录清理，最终包与小型身份/交接记录保留。一份build cache和shader cache供后继恢复，路径见交接；它们不是证据。Windows VM已挂起，测试App已退出；普通用户App不处理。真实用户媒体及原Workshop未修改，未推送。
