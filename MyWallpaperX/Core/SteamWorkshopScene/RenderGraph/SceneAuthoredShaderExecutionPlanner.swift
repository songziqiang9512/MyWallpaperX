import CoreGraphics
import Foundation

nonisolated enum SceneAuthoredShaderExecutionPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Plan = SceneAuthoredShaderExecutionPlan

    static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole
    ) -> Plan? {
        let materialNodes = graph.nodes.filter { $0.kind == .material }
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 1,
              materialNodes.count == 1,
              graph.renderTargets.isEmpty,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              ["image", "solid", "text"].contains(layer.contentKind),
              let mappedSize = mappedSize(layer),
              validTopology(
                  graph: graph,
                  node: materialNodes[0],
                  layer: layer,
                  inputRole: inputRole
              ) else {
            return nil
        }
        let node = materialNodes[0]
        let resolution = SceneAuthoredMaterialResolver.resolve(
            node: node,
            graph: graph,
            descriptor: descriptor
        )
        guard resolution.isResolved,
              let material = resolution.node,
              validMaterial(material),
              let materialDescriptor = descriptor.materialPasses.first(where: {
                  $0.id == node.materialPassID
              }),
              materialDescriptor.userShaderValues.isEmpty,
              materialDescriptor.alphaWriting == nil,
              let contract = matchingContract(
                  material.shaderPath,
                  shaderContracts: shaderContracts
              ),
              let vertex = contract.stages.first(where: { $0.kind == .vertex }),
              let fragment = contract.stages.first(where: { $0.kind == .fragment }) else {
            return nil
        }
        let frontend = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex.source,
            fragmentSource: fragment.source
        )
        guard let program = frontend.program,
              frontend.diagnostics.isEmpty,
              let framebufferSlots = framebufferSlots(
                  program: program,
                  contract: contract
              ),
              let uniformBindings = uniformBindings(
                  program: program,
                  constants: material.constants,
                  framebufferSlots: Set(framebufferSlots)
              ) else {
            return nil
        }
        return Plan(
            cacheKey: contract.canonicalSHA256,
            program: program,
            mappedSize: mappedSize,
            framebufferTextureSlots: framebufferSlots,
            uniformBindings: uniformBindings
        )
    }

    private static func validTopology(
        graph: Graph,
        node: Graph.Node,
        layer: SceneRenderDescriptor.Layer,
        inputRole: SceneAuthoredEffectInputRole
    ) -> Bool {
        let effect = graph.effects[0]
        guard layer.effects.indices.contains(effect.key.effectIndex) else { return false }
        let descriptor = layer.effects[effect.key.effectIndex]
        return descriptor.id == effect.key.descriptorID
            && descriptor.visible != false
            && effect.nodeIndices == [node.nodeIndex]
            && SceneAuthoredEffectInputValidator.accepts(
                effect.input,
                layerID: graph.layerID,
                role: inputRole
            )
            && effect.output == graph.finalOutput
            && node.effect == effect.key
            && node.target == effect.output
            && node.bindings.isEmpty
    }

    private static func validMaterial(_ material: SceneResolvedMaterialNode) -> Bool {
        material.textureSlots.allSatisfy { $0 == nil }
            && material.combos.isEmpty
            && normalized(material.renderState.blending) == "normal"
            && normalized(material.renderState.depthTest) == "disabled"
            && normalized(material.renderState.depthWrite) == "disabled"
            && normalized(material.renderState.cullMode) == "nocull"
    }

    private static func matchingContract(
        _ shaderPath: String,
        shaderContracts: [SceneShaderContract]
    ) -> SceneShaderContract? {
        let matches = shaderContracts.filter {
            normalized($0.identity) == normalized(shaderPath)
        }
        guard matches.count == 1,
              let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.stages.count == 2,
              Set(contract.stages.map(\.kind)) == Set([.vertex, .fragment]),
              contract.stages.allSatisfy({ $0.includes.isEmpty }) else {
            return nil
        }
        return contract
    }

    private static func framebufferSlots(
        program: SceneAuthoredShaderProgram,
        contract: SceneShaderContract
    ) -> [Int]? {
        var slots: [Int] = []
        for texture in program.textureBindings {
            let annotated = contract.stages.contains { stage in
                stage.declarations.contains { declaration in
                    declaration.kind == .uniform
                        && declaration.type == "sampler2D"
                        && declaration.name == texture.name
                        && stage.annotations.contains {
                            $0.line == declaration.line && isFramebuffer($0.value)
                        }
                }
            }
            guard annotated else { return nil }
            slots.append(texture.slot)
        }
        return slots.sorted()
    }

    private static func isFramebuffer(_ value: SceneJSONValue) -> Bool {
        guard case .object(let object) = value,
              object["material"]?.stringValue?.localizedLowercase == "framebuffer" else {
            return false
        }
        return true
    }

    private static func uniformBindings(
        program: SceneAuthoredShaderProgram,
        constants: [String: SceneDocument.ShaderValue],
        framebufferSlots: Set<Int>
    ) -> [Plan.UniformBinding]? {
        var bindings: [Plan.UniformBinding] = []
        for field in program.uniformLayout.fields {
            let source: Plan.UniformBinding.Source?
            switch (field.name, field.type) {
            case ("mwxRenderSize", .float2):
                source = .renderSize
            case ("g_ModelViewProjectionMatrix", .float4x4):
                source = .modelViewProjection
            case ("g_Time", .float):
                source = .time
            case ("g_PointerPosition", .float2):
                source = .pointerPosition
            case ("g_TexelSize", .float2):
                source = .texelSize(scale: 1)
            case ("g_TexelSizeHalf", .float2):
                source = .texelSize(scale: 0.5)
            default:
                source = textureBuiltin(field, framebufferSlots: framebufferSlots)
                    ?? constant(field, authored: constants)
            }
            guard let source else { return nil }
            bindings.append(.init(field: field, source: source))
        }
        return bindings
    }

    private static func textureBuiltin(
        _ field: SceneAuthoredShaderUniformLayout.Field,
        framebufferSlots: Set<Int>
    ) -> Plan.UniformBinding.Source? {
        for slot in framebufferSlots {
            if field.name == "g_Texture\(slot)Resolution", field.type == .float4 {
                return .textureResolution(slot: slot)
            }
            if field.name == "g_Texture\(slot)Texel", field.type == .float2 {
                return .textureTexel(slot: slot)
            }
        }
        return nil
    }

    private static func constant(
        _ field: SceneAuthoredShaderUniformLayout.Field,
        authored: [String: SceneDocument.ShaderValue]
    ) -> Plan.UniformBinding.Source? {
        guard let value = authored[field.name],
              value.userBinding == nil,
              value.timeline == nil,
              value.timelineDiagnostics.isEmpty,
              let components = value.components,
              components.count == componentCount(field.type),
              components.allSatisfy(\.isFinite) else {
            return nil
        }
        return .constant(components)
    }

    private static func componentCount(_ type: SceneAuthoredShaderValueType) -> Int {
        switch type {
        case .bool, .int, .uint, .float: 1
        case .int2, .uint2, .float2: 2
        case .int3, .uint3, .float3: 3
        case .int4, .uint4, .float4, .float2x2: 4
        case .float3x3: 9
        case .float4x4: 16
        }
    }

    private static func mappedSize(_ layer: SceneRenderDescriptor.Layer) -> CGSize? {
        guard let sizeWH = layer.sizeWH, sizeWH.count >= 2 else { return nil }
        let width = CGFloat(sizeWH[0])
        let height = CGFloat(sizeWH[1])
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func normalized(_ value: String?) -> String {
        value?.replacingOccurrences(of: "\\", with: "/").localizedLowercase ?? ""
    }
}
