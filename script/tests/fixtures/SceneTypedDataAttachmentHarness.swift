import Foundation
struct Graph {
    struct TextureIdentity: Hashable {
        enum Kind { case effectOutput, framebuffer, layerSource, unresolved }
        let kind: Kind
    }
    struct Binding { let texture: TextureIdentity; var conditions: Int? = nil }
    struct Node { var target: TextureIdentity?; var bindings: [Binding] }
    struct Target { let texture: TextureIdentity; let format: SceneGraphRenderTargetPlan.TextureFormat }
    var renderTargets: [Target] = []
}
enum SceneTextureContent { case data, color }
enum SceneResolvedMaterialAttachmentKind {
    case preservedRGBAUnorm, color, scalarRedUnorm, redGreenUnorm, scalarRedFloat16, redGreenFloat16
}
enum SceneGraphRenderTargetPlan {
    enum TextureFormat { case r8, rg88, r16f, rg1616f, rgbaBackbuffer, rgba8888, rgba16f }
    static func targetDescriptor(_ target: Graph.Target, inputWidth: Int, inputHeight: Int,
        backbufferFormat: TextureFormat) -> Graph.Target? { target }
}
func attachment(for node: Graph.Node, in graph: Graph,
    preservedRGBADataTargets: Set<Graph.TextureIdentity>,
    graphTextureContentFacts: [Graph.TextureIdentity: SceneTextureContent],
    backbufferFormat: SceneGraphRenderTargetPlan.TextureFormat
) -> (storage: SceneResolvedMaterialAttachmentKind, format: SceneGraphRenderTargetPlan.TextureFormat)?
__BODY__
let source = Graph.TextureIdentity(kind: .framebuffer)
var node = Graph.Node(target: .init(kind: .effectOutput), bindings: [.init(texture: source)])
for format: SceneGraphRenderTargetPlan.TextureFormat in [.rgbaBackbuffer, .rgba16f] {
    func resolve(_ facts: [Graph.TextureIdentity: SceneTextureContent]) -> (storage: SceneResolvedMaterialAttachmentKind, format: SceneGraphRenderTargetPlan.TextureFormat)? {
        attachment(for: node, in: Graph(), preservedRGBADataTargets: [],
                   graphTextureContentFacts: facts, backbufferFormat: format)
    }
    let data = resolve([source: .data])!
    precondition(data.storage == .preservedRGBAUnorm && data.format == format)
    let unproven = resolve([:])!
    precondition(unproven.storage == .color && unproven.format == format)
    node.bindings[0].conditions = 1
    precondition(resolve([source: .data])!.storage == .color)
    node.bindings[0].conditions = nil
    node.bindings.append(.init(texture: source))
    precondition(resolve([source: .data])!.storage == .color)
    node.bindings.removeLast()
}
node.target = nil
precondition(attachment(for: node, in: Graph(), preservedRGBADataTargets: [],
    graphTextureContentFacts: [source: .data], backbufferFormat: .rgba16f) == nil)
