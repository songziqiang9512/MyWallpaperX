<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# D3 F5：默认环境反射的实际消费（2026-10-02）

> **历史证据 — 非现役入口**。目标与独立数值策略见[D3 F5](../roadmap/batch2/2d-lighting-material-design.md#f5-reflection-environment)，后继由[RF10卡](../roadmap/batch2/reference-evidence-implementation-cards.md#rf10-pbr-direct)拥有。本片产品已获独立终审ACCEPT，稳定职责移交原架构owner；本记录保留冻结范围与未验证上限。

## 范围与依据

产品基线`6a95278f`，设计前置提交`4f198574`。本片接通普通单pass builtin genericimage2/4 的默认2D环境反射，LIGHTING与REFLECTION独立。材质profile→原资源准备→同帧源捕获→共享lit shader→原compositor，未建立第二registry、clock、history或输出owner。Puppet、3D、planar、显式slot3/provider、动态reflection属性不在此窄片。

root、产品、测试与独审均未接收私有原始静态表达。采用[经独审的中性输入及顺序合同](d3-reflection-environment-neutral-contract-2026-10-02.md)：固定官方声明证明隐藏2D环境输入；固定第三方结构证明首次实际消费者前的本帧主场景前缀共享与每帧重建。没有从声明presence推导官方运行数值。视向、法线、world单位有限距离投影、真实mip与Fresnel权重由本项目独立选择；并不声称官方公式、深度求交SSR或像素parity。

## 旧反例与实施纠偏

全部可复查本机材料在`/private/tmp/mwx-reflection-environment/`。原四case用相同原材料/三份TEX资产，只改变LIGHTING0下REFLECTION0/1及reflectivity0/4。实际builder缺反射profile，旧App的八张首帧/后续PNG完全相同；红证manifest SHA`67663f3e4d179deef6e1aae3238c34aafd79bda953529c65b3caf9fb9dd0a430`，独审SHA`6427b39c713e0a1d5852717b7a3b5171fef0d3a299fcbd1d23d38847a1bab9f5`。这证明缺消费，不证明官方环境算法。

实现后真实App又抓到初始化漏接：v4原四case仍无差分，日志为`lit-pipeline-unavailable`。原加载期只按lightingEnabled准备PSO；扩为surfaceEnabled后仍在原加载owner准备，不在普通帧编译。该路径作为第31个设计候选经独审、登记后修改。旧v4 App、八图和失败结论完整保留。

跨帧检查同时发现普通scratch的保护缺口：reflection A预留后，非reflection B可替换目标却不持pin，随后C可能复用B在飞目标。现在每次实际compositionTarget消费交付同CB pin，root mainPass持有，group经原parentPass归同提交；SceneColor接用返回pin。普通帧不因此全工作集预分配。真实GPU事件挡住B，验证C不能提前复用、完成后旧generation回收。

独审还发现显式slot3输入被忽略。真实parser→profile先证明八个显式asset/provider/canonical名字仍错误准入，再仅关闭这些输入的reflection；保direct/normal/F4，null无显式来源时仍支持默认环境。未把名字猜成已支持别名。

## 资源与数值合同

首次实际plain/graph source叶端才获取默认环境；准备阶段不发布未写纹理。关闭活动group及主pass，主前缀copy、生成完整mip、receiver采样按同CB顺序编码，同帧后续receiver复用一次结果，下一帧重新生产。资源经typed atom直接进入consumer，不提交persistent registry/history。GPU completion与ready编码状态分别处理。

可选环境不得挤占必需源/terminal scratch：原池先stage实际全部MTLTexture，预算与revision/identity一起复核后原子commit；第N次分配失败不留下前缀eviction。完整奇数非方形mip按逐级尺寸计费，旧在飞allocation含retired部分持续计费；取消释放未提交pin，提交后以真实completion释放。

自有double oracle在GPU前独审冻结；common/graph输出等价，零B/零strength/disabled/unavailable保原像素，alpha不变，HDR不提前夹到1。最初用RGBA16F梯度输出反推理想UV的2e-6门失败；独立只执行texture.sample的Metal control证明硬件过滤量化。保留旧失败，改用冻结UV经同设备独立采样得到期望像素，2e-6限制采样值等价，不声称直接测得内部UV。使用冻结double Fresnel归一化的最大对照差为1.1660e-7，辐射值域差4.9053e-9。数学oracle未根据产品结果调整。一个极端有限底色向量在旧/新shader均得40，只计回归，不虚称复现了overflow。

## 冻结身份与验证

最终产品v6清单SHA`0becbc5e87d12eae6e4171684a85e34a5f4733774b134b8c865ea6637c3c000d`，26个实际产品文件。`build-v5`完整Debug成功，1070源/project身份前后不变。隔离`source-v6.app`的主程序SHA`ff60aad8940cbbb4879bcfc85cfb84fbc0f2d095045d2a586218cf26ff96477a`，dylib SHA`544b7794f170d75bfa338c614e1db4c27bcfcff5a87c58ff15c979894c94de41`，metallib SHA`adaaff60ad4c8fdeb0bb247f3ed8e807403c62315660f5dd7e1c92c53eb1763e`。本地ad-hoc签名并strict/deep核验；不是发布签名或性能构建。

- actual builder含30组反射输入/默认/instance/provenance/显式slot3向量通过。最终补跑整个authored map模块，3个实际方法通过（56.750秒）；App integration类跳过，10个方法未执行，不以定义数冒充通过数。
- GPU/池/registry 42个方法通过：24数值向量走真实common与graph两路；12空间投影采样对照、9LOD、已有normal/alpha门；实际Nth分配失败、NPOT成本、跨CB pin、reset/cancel/completion等。
- 邻接normal、live property、PBR scalar、F4亮度、graph publication、material finalizer和resident budget通过。终端HDR/raw/history四项通过；测试shell仅补无关类型依赖，未模拟被断言的行为。
- runtime bridge的旧Renderer源码字符串查找在HEAD已失败；保留该旧门并单列，不改产品迎合它。新增API影响的harness按真实接口同步。旧shape检查不构成行为证明。
- code-health、scene-defense、design-gate在最终v6全部通过；未提高结构/防御预算，外来layout排序未纳入本批。

v5原材料四case重放全部通过：关闭/零strength与旧App逐像素相同，开启后预声明receiver ROI有417390个像素变化、最大RGB差225，ready/after各自完全相同；所有运行单session、frame1完成、drain、三工件不变。root核对了原package/project和runner身份并目检启用图。结果SHA`a65d46d9bc28ea37422d501a8fff8a9fd0ac675548c65790b62097ec0d7ea759`。

空间初轮六项通过，另四项未形成有效覆盖：visible.user被既有规则列为重建；group root首位进入legacy前缀而被拒；visible effectful前向primary不会提前执行。v2改用真实visible脚本、在group前添加合法主层、hidden effectful provider，重新冻结输入和oracle，四项通过。动态输出为ready双红43→同截图双绿43→after双红43；group pending双黑、已composite组双红22；hidden前向graph使B黑，并有provider先encoded-output、named publication/binding成功、consumer GPU完成及terminal消费事件。v1失败保留，不能当产品反例或已覆盖路径。动态门验证脚本更新，不是live属性或相邻帧证明。

真实ReflectionFrame producer使用自有4×2 HDR区块，copy后生成三个mip，末级为[1,2,0,.5]；主目标改蓝不改变同帧快照，下一帧同storage重新得到[0,0,3,1]。在飞reset仍计152字节、完成归零，cancel幂等，实际blit失败当帧不重试，16项行为均成立。manifest SHA`3962dc88409039784630cf7f779ee26d624f80c3bbeb94cf0dc39a437fad5373`。v6仅收敛private pool参数，让helper自身只构造可达key，删除无真实产生者的默认失败分支；独审增量SHA`599ca5916b5e69e38fa963eed2f12d291bed61f02d6f289604f7230260eea7cf`。

最终v6以相同输入/oracle另根重放原四case及空间十case，14/14通过。原四case结果SHA与v5一致，三工件及复制输入事后身份全部匹配；空间结果manifest SHA`15a31a49769ac7e575016cf07edf65b29f5f4adc0727680bfabda5122d7bc182`，group/forward/script五专题实际路由事件另有`route-audit.json`。真实producer在v6再次通过，source-manifest SHA`9759c78034be188c14924fe4f50dd0e72da37aa865b38a5aa2eb6a632d845d41`，result SHA`98020375b0143a04e840b81ca08a8acac1eb8dabbcf499799d94cf6ffcb01d65`。GPU/池/registry在v6重跑42项通过，测试清单SHA`484d2dde6bf9939aa6555d0eae0dec363e4cacb14245c298e58b3f29e31c330f`与producer所属测试SHA`d3c8f49af259867420356517973d7d03b41ae0b38f0b29a96fdd637db2281dbd`分别冻结；不将重复运行叠加为唯一测试数。文档角色13项通过。独立产品终审`product-final-v6-review.md` SHA`e3a50b02a3c837c535a8232a4a596d07066259536156ec2261c90e53163b09e5`明确ACCEPT；关键证据identity SHA`bc0ef7d4ac4c58b0d6cebab49427bd8e0f67722afce6355f8f375e82053f45b6`。审查者独立核对26产品、9测试/fixture、3 App工件、105项空间证据hash、50个ROI及四原材料对照，逐条复核真实route/发布/完成事件，无未解决P1/P2。未运行官方golden/parity、完整原场景全时序、优化构建性能、多显示器压力或真实全局GPU配额耗尽；实际分配失败门使用池内factory注入，不把它冒称整机OOM；这些上限不由Debug构建或局部像素通过推升。

## 后继

本片稳定职责已移交[架构](../architecture/runtime-architecture.md)，窄gate `scene-2d-reflection-environment`同批退役；下一主能力仍是有合法caster/depth输入的2D阴影。先从既有中性参考、公开作者合同和合法输入确认caster/receiver与层深度职责，再设计、独立实现和实际输出验收；缺官方算法不是跳过理由。显式环境输入和其它receiver作为独立扩展，不通过默认环境替代作者请求。
