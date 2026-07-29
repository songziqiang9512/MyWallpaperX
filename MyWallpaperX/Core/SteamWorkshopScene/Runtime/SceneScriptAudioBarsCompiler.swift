import CryptoKit
import Foundation

/// Strictly recognizes two independently verified 64-band SceneScript shapes.
///
/// Recognition combines the source fingerprint with the binding/layer contract
/// and the consumed model-to-material, material, shader, texture-path, and
/// render-state contracts. Texture pixels remain authored input; a partial
/// structural match never produces a plan.
nonisolated enum SceneScriptAudioBarsCompiler {
    typealias VerificationInput = SceneScriptAudioBarsVerificationInput
    private typealias LayerSnapshot = VerificationInput.LayerSnapshot
    private typealias AssetSnapshot = VerificationInput.AssetSnapshot
    private typealias ShaderValueSnapshot = VerificationInput.ShaderValueSnapshot

    private nonisolated enum Profile: Equatable {
        case fixedDiagonal
        case parameterizedLinear
    }

    private nonisolated struct Configuration {
        let width: Float
        let height: Float
        let depth: Float
        let xStep: Float
        let yStep: Float
        let angle: Float
        let alignment: SceneScriptAudioBarsPlan.Alignment
        let firstStep: SceneScriptAudioBarsPlan.FirstStepPolicy
    }

    private static let fixedSourceSHA256 =
        "2d874f553bef33dfd4650b1d38630148ccf52940bb6b542f46860411aa5d9379"
    private static let parameterizedSourceSHA256 =
        "e6ff1bbde3ab348731a5ba35f757f8f0fc97fd70a117dd7e74eaffe98026b149"

    nonisolated static func compile(
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneScriptAudioBarsProgram {
        var plans: [SceneScriptAudioBarsPlan] = []
        var diagnostics: [SceneScriptAudioBarsProgram.Diagnostic] = []
        for layer in descriptor.layers {
            let bindings = layer.scriptBindings ?? []
            guard !bindings.isEmpty else { continue }
            let candidates = bindings.compactMap { binding -> (SceneScriptBindingDefinition, String)? in
                let sourceSHA256 = sha256(binding.source)
                return profile(for: sourceSHA256) == nil ? nil : (binding, sourceSHA256)
            }
            guard !candidates.isEmpty else { continue }
            let layerSnapshot = LayerSnapshot(
                layer: layer,
                cameraParallaxEnabled: descriptor.camera.parallaxEnabled,
                cameraOrthoHeight: descriptor.camera.orthoHeight,
                reverseDependencyConsumerCount: descriptor.layers.filter {
                    $0.dependencyLayerIDs.contains(layer.id)
                }.count
            )
            let assetSnapshot = AssetSnapshot(
                layer: layer,
                descriptor: descriptor,
                shaderContracts: shaderContracts
            )
            for (binding, sourceSHA256) in candidates {
                let result = compileVerifiedProfile(.init(
                    layerID: layer.id,
                    bindingCount: bindings.count,
                    host: binding.host,
                    sourceSHA256: sourceSHA256,
                    properties: binding.properties,
                    authoredValue: binding.authoredValue,
                    layer: layerSnapshot,
                    assets: assetSnapshot
                ))
                plans.append(contentsOf: result.plans)
                diagnostics.append(contentsOf: result.diagnostics)
            }
        }
        return finalized(plans: plans, diagnostics: diagnostics)
    }

    /// Fixture entry point avoids copying third-party script or shader source.
    nonisolated static func compileVerifiedProfile(
        _ input: VerificationInput
    ) -> SceneScriptAudioBarsProgram {
        guard let profile = profile(for: input.sourceSHA256) else {
            return rejected(input, code: .unknownProfile, detail: "source")
        }
        guard input.bindingCount == 1,
              input.host == "visible",
              input.authoredValue == .bool(true) else {
            return rejected(input, code: .invalidBinding, detail: "shape")
        }
        guard let configuration = configuration(
            profile: profile,
            properties: input.properties
        ) else {
            return rejected(input, code: .invalidProperties, detail: "properties")
        }
        guard validLayer(input.layer, profile: profile) else {
            return rejected(input, code: .invalidLayerContract, detail: "layer")
        }
        guard validAssets(input.assets, profile: profile) else {
            return rejected(input, code: .invalidAssetContract, detail: "assets")
        }
        let paths = assetPaths(profile)
        return SceneScriptAudioBarsProgram(plans: [.init(
            layerID: input.layerID,
            sourceSHA256: input.sourceSHA256,
            host: input.host,
            modelPath: paths.model,
            materialPath: paths.material,
            texturePath: paths.texture,
            barCount: 64,
            audioResolution: 64,
            channel: .average,
            widthMultiplier: configuration.width,
            heightMultiplier: configuration.height,
            depthMultiplier: configuration.depth,
            xStep: configuration.xStep,
            yStep: configuration.yStep,
            angleDegrees: configuration.angle,
            alignment: configuration.alignment,
            firstStepPolicy: configuration.firstStep
        )], diagnostics: [])
    }

    private nonisolated static func profile(for sha256: String) -> Profile? {
        switch sha256 {
        case fixedSourceSHA256: .fixedDiagonal
        case parameterizedSourceSHA256: .parameterizedLinear
        default: nil
        }
    }

    private nonisolated static func configuration(
        profile: Profile,
        properties: [String: SceneJSONValue]
    ) -> Configuration? {
        switch profile {
        case .fixedDiagonal:
            guard properties.isEmpty else { return nil }
            return .init(
                width: 1, height: 50, depth: 1,
                xStep: 5.6, yStep: 11.3, angle: 60,
                alignment: .centre, firstStep: .advanceBeforeFirstBar
            )
        case .parameterizedLinear:
            let keys = Set([
                "anglesY", "barAlignmentdir", "barWidth",
                "originX", "originY", "scaleY",
            ])
            guard Set(properties.keys) == keys,
                  let width = number(properties["barWidth"], range: 0 ... 10),
                  let height = number(properties["scaleY"], range: 0 ... 100),
                  let xStep = number(properties["originX"], range: -60 ... 60),
                  let yStep = number(properties["originY"], range: -60 ... 60),
                  let angle = number(properties["anglesY"], range: -90 ... 90),
                  case let .string(alignmentRaw)? = properties["barAlignmentdir"],
                  let alignment = SceneScriptAudioBarsPlan.Alignment(rawValue: alignmentRaw)
            else { return nil }
            return .init(
                width: width, height: height, depth: 0,
                xStep: xStep, yStep: yStep, angle: angle,
                alignment: alignment, firstStep: .ownerAtBaseOrigin
            )
        }
    }

    private nonisolated static func validLayer(
        _ layer: LayerSnapshot,
        profile: Profile
    ) -> Bool {
        let expectedAlignment: String? = profile == .fixedDiagonal ? "center" : nil
        let exactValues: Bool
        switch profile {
        case .fixedDiagonal:
            exactValues = layer.alpha == 1
                && layer.colorRGB == [1, 1, 1]
                && layer.colorBlendMode == 0
                && layer.brightness == 1
                && layer.parallaxDepthXY == [1, 1]
        case .parameterizedLinear:
            exactValues = layer.alpha == nil
                && layer.colorRGB == nil
                && layer.colorBlendMode == nil
                && layer.brightness == nil
                && layer.parallaxDepthXY == nil
        }
        return layer.contentKind == "image"
            && layer.imagePath == assetPaths(profile).model
            && layer.imageAlignment == expectedAlignment
            && layer.visible == true
            && layer.hasInlineScript
            && layer.particlePath == nil
            && !layer.hasUtilityLayer
            && layer.dependencyCount == 0
            && layer.reverseDependencyConsumerCount == 0
            && layer.parentID == nil
            && layer.childCount == 0
            && layer.attachmentName == nil
            && !layer.hasParentAttachmentBindFrame
            && layer.puppetAnimationCount == 0
            && layer.puppetMeshPath == nil
            && layer.text == nil
            && !layer.hasTextStyle
            && !layer.hasTextScript
            && layer.effectCount == 0
            && layer.effectFileCount == 0
            && layer.texturePathCount == 0
            && layer.timelineCount == 0
            && layer.timelineDiagnosticCount == 0
            && !layer.hasModelCropOffset
            && !layer.disablesParallaxPropagation
            && !layer.cameraParallaxEnabled
            && layer.cameraOrthoHeight?.isFinite == true
            && (layer.cameraOrthoHeight ?? 0) > 0
            && layer.hasFiniteOrigin
            && layer.hasPositiveFiniteSize
            && exactValues
    }

    private nonisolated static func validAssets(
        _ assets: AssetSnapshot,
        profile: Profile
    ) -> Bool {
        let paths = assetPaths(profile)
        guard assets.missingResourceCount == 0,
              assets.modelLinkCount == 1,
              assets.linkedMaterialPath == paths.material,
              assets.materialPassCount == 1,
              assets.materialPath == paths.material,
              assets.materialPassIndex == 0,
              assets.texturePaths == [paths.texture],
              assets.textureSlots == [Optional(paths.texture)],
              assets.userTextureInputCount == 0,
              assets.userShaderValues.isEmpty,
              assets.blending == "translucent",
              assets.depthTest == "disabled",
              assets.depthWrite == "disabled",
              assets.cullMode == "nocull",
              assets.shaderContractCount == 1,
              assets.shaderDiagnosticCount == 0,
              assets.shaderCanonicalMatchesPayload,
              isSHA256(assets.shaderCanonicalSHA256) else {
            return false
        }
        switch profile {
        case .fixedDiagonal:
            return assets.materialRawSHA256
                == "65a4ac3ac6d47bc25276b8b3e5f42da54adcec69a68887ac7f0cf475e0af2b7b"
                && assets.shaderPath == "genericimage2"
                && assets.combos.isEmpty
                && assets.constants.isEmpty
                && assets.alphaWriting == nil
                && assets.shaderIdentity == "genericimage2"
                && assets.shaderSourceKind == "hostBuiltin"
                && assets.shaderStageCount == 0
                && assets.shaderDeclaredStageSHA256.isEmpty
                && assets.shaderSourceStageSHA256.isEmpty
                && assets.shaderCanonicalSHA256
                    == "d29f539dad764c98b38610897d1280d34207ecfe75a934e4f8d03bef52589fde"
        case .parameterizedLinear:
            let expectedStages = [
                "vertex:shaders/workshop/2727665642/tint.vert":
                    "0582110d1e8ccfdd0d42779860ffc2915e3eb22cc5013df173592c7dc3ae5730",
                "fragment:shaders/workshop/2727665642/tint.frag":
                    "ed1eb09fac286baf5b32b82f742330d3137983aa5694a4d183e72bd4aed68db1",
            ]
            return assets.materialRawSHA256
                == "6e9b9f68d9d08f9e3bfa400a6a0102bc144a998d952b14dc35ef7dd16085c3d5"
                && assets.shaderPath == "workshop/2727665642/tint"
                && assets.combos == ["version": 2]
                && validParameterizedConstants(assets.constants)
                && assets.alphaWriting == "default"
                && assets.shaderIdentity == "workshop/2727665642/tint"
                && assets.shaderSourceKind == "authoredSource"
                && assets.shaderStageCount == 2
                && assets.shaderDeclaredStageSHA256 == expectedStages
                && assets.shaderSourceStageSHA256 == expectedStages
        }
    }

    private nonisolated static func validParameterizedConstants(
        _ constants: [String: ShaderValueSnapshot]
    ) -> Bool {
        let invisibleKey = "\u{20}\u{200F}\u{200F}\u{200E}\u{20}"
        return Set(constants.keys) == Set([invisibleKey, "Alpha", "color"])
            && constants[invisibleKey] == scalarSnapshot(raw: "0.0", value: 0)
            && constants["Alpha"] == scalarSnapshot(raw: "1.0", value: 1)
            && constants["color"] == .init(
                rawValue: "1.00000 1.00000 1.00000",
                valueKind: "binding",
                userBinding: nil,
                components: [1, 1, 1],
                hasTimeline: false,
                timelineDiagnostics: []
            )
    }

    private nonisolated static func scalarSnapshot(
        raw: String,
        value: Double
    ) -> ShaderValueSnapshot {
        .init(
            rawValue: raw, valueKind: "number", userBinding: nil,
            components: [value], hasTimeline: false, timelineDiagnostics: []
        )
    }

    private nonisolated static func assetPaths(
        _ profile: Profile
    ) -> (model: String, material: String, texture: String) {
        switch profile {
        case .fixedDiagonal:
            (
                "models/workshop/2079954552/bar.json",
                "materials/workshop/2079954552/bar.json",
                "workshop/2079954552/bar"
            )
        case .parameterizedLinear:
            (
                "models/workshop/2727665642/bar.json",
                "materials/workshop/2727665642/bar.json",
                "workshop/2727665642/bar"
            )
        }
    }

    private nonisolated static func rejected(
        _ input: VerificationInput,
        code: SceneScriptAudioBarsProgram.Diagnostic.Code,
        detail: String
    ) -> SceneScriptAudioBarsProgram {
        .init(plans: [], diagnostics: [.init(
            layerID: input.layerID,
            code: code,
            sourceSHA256: input.sourceSHA256,
            detail: detail
        )])
    }

    private nonisolated static func finalized(
        plans: [SceneScriptAudioBarsPlan],
        diagnostics: [SceneScriptAudioBarsProgram.Diagnostic]
    ) -> SceneScriptAudioBarsProgram {
        let grouped = Dictionary(grouping: plans, by: \.layerID)
        let duplicateIDs = Set(grouped.filter { $0.value.count > 1 }.map(\.key))
        let duplicateDiagnostics = duplicateIDs.sorted().map { layerID in
            SceneScriptAudioBarsProgram.Diagnostic(
                layerID: layerID,
                code: .duplicateLayer,
                sourceSHA256: grouped[layerID]?.first?.sourceSHA256 ?? "",
                detail: "multiplePlans"
            )
        }
        return .init(
            plans: plans.filter { !duplicateIDs.contains($0.layerID) }
                .sorted { $0.layerID < $1.layerID },
            diagnostics: (diagnostics + duplicateDiagnostics).sorted {
                ($0.layerID, $0.code.rawValue, $0.sourceSHA256)
                    < ($1.layerID, $1.code.rawValue, $1.sourceSHA256)
            }
        )
    }

    private nonisolated static func number(
        _ value: SceneJSONValue?,
        range: ClosedRange<Double>
    ) -> Float? {
        guard case let .number(number)? = value,
              number.isFinite,
              range.contains(number),
              Float(number).isFinite else { return nil }
        return Float(number)
    }

    private nonisolated static func isSHA256(_ value: String?) -> Bool {
        guard let value, value.count == 64 else { return false }
        return value.utf8.allSatisfy {
            (48 ... 57).contains($0) || (97 ... 102).contains($0)
        }
    }

    private nonisolated static func sha256(_ source: String) -> String {
        sha256(Data(source.utf8))
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
