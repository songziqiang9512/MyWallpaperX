import Foundation

// Runs the real launch catalog, shared profile compiler and immutable Program.
// Descriptor DTOs come from the provider harness; no VM, GPU or upload is simulated.
func preparedImageMaterialChecks() -> [String: Any] {
    typealias Descriptor = SceneRenderDescriptor
    typealias Pass = Descriptor.MaterialPassDescriptor
    typealias Profile = SceneBaseMaterialLightingProfile
    let model = "models/prepared-material.json"
    let material = "materials/prepared-material.json"
    func scalar(_ value: Double, raw: String? = nil,
                keys: [String] = [], nullUser: Bool = false) -> SceneDocument.ShaderValue {
        .init(rawValue: raw ?? String(value), userBinding: nil, components: [value],
              userValueKind: nullUser ? .null : nil, bindingKeys: keys)
    }
    func pass(_ shader: String = "genericimage4", lighting: Int? = nil,
              constants: [String: SceneDocument.ShaderValue] = [:]) -> Pass {
        var value = Pass(materialPath: material, shaderPath: shader,
            combos: ["VERSION": 2], textureSlots: ["textures/prepared-albedo"],
            userTextureInputs: [nil], constantShaderValues: constants)
        if let lighting { value.combos["LIGHTING"] = lighting }
        value.texturePaths = ["textures/prepared-albedo"]
        value.blending = "translucent"
        value.depthTest = "disabled"
        value.depthWrite = "disabled"
        value.cullMode = "nocull"
        return value
    }
    func descriptor(_ passes: [Pass], modelPath: String = model,
                    materialPath: String = material,
                    layers: [Descriptor.Layer] = []) -> Descriptor {
        .init(layers: layers, modelMaterialLinks: [
            .init(modelPath: modelPath, materialPath: materialPath)
        ], materialPasses: passes, texturePropertyKeys: [])
    }
    func catalog(_ pass: Pass) -> ScenePreparedImageMaterialCatalog {
        .init(descriptor: descriptor([pass]))
    }
    func replacingInputs(_ value: Pass, slots: [String?]? = nil,
                         providers: [SceneEffectTextureInput?]? = nil,
                         materialPath: String? = nil) -> Pass {
        .init(materialPath: materialPath ?? value.materialPath, passIndex: value.passIndex,
            staticModelMaterialBindings: value.staticModelMaterialBindings,
            shaderPath: value.shaderPath, combos: value.combos,
            textureSlots: slots ?? value.textureSlots,
            userTextureInputs: providers ?? value.userTextureInputs,
            constantShaderValues: value.constantShaderValues, texturePaths: value.texturePaths,
            userShaderValues: value.userShaderValues, blending: value.blending,
            depthTest: value.depthTest, depthWrite: value.depthWrite,
            cullMode: value.cullMode, alphaWriting: value.alphaWriting)
    }
    let plain = pass()
    let lightingZero = pass(lighting: 0)
    let tierTwo = pass("genericimage2", lighting: 1)
    let tierFour = pass(lighting: 1)
    let explicit = pass(lighting: 1, constants: [
        "metallic": scalar(0.24), "roughness": scalar(0.83)
    ])
    let clamped = pass(lighting: 1, constants: [
        "metallic": scalar(Double.greatestFiniteMagnitude), "roughness": scalar(-3)
    ])
    var renamed = Pass(materialPath: "  MATERIALS\\RENAMED.JSON  ",
        shaderPath: "GeNeRiCiMaGe4", combos: ["LIGHTING": 1, "VERSION": 2],
        textureSlots: ["textures/unseen-name"], userTextureInputs: [],
        constantShaderValues: [
            "roughness": scalar(0.83, raw: " 8.3e-1 ", keys: ["value", "user"], nullUser: true),
            "metallic": scalar(0.24, raw: "  2.4e-1  ", keys: ["value"])
        ])
    renamed.texturePaths = ["textures/unseen-name"]
    renamed.blending = " TRANSLUCENT "
    renamed.depthTest = "Disabled"
    renamed.depthWrite = "disabled"
    renamed.cullMode = "NoCull"
    let renamedCatalog = ScenePreparedImageMaterialCatalog(descriptor: descriptor([renamed],
        modelPath: "  MODELS\\RENAMED.JSON  ", materialPath: "materials/renamed.json"))
    let explicitProfile = catalog(explicit).profiles[model]!
    let accepted: [String: Profile] = [
        "plain": catalog(plain).profiles[model]!,
        "lightingZero": catalog(lightingZero).profiles[model]!,
        "tierTwo": catalog(tierTwo).profiles[model]!,
        "tierFour": catalog(tierFour).profiles[model]!,
        "explicit": explicitProfile,
        "renamedWrapped": renamedCatalog.profiles["models/renamed.json"]!,
        "clampedFinite": catalog(clamped).profiles[model]!
    ]
    var checks: [String: Bool] = [
        "plainHasNoLitSurface": !accepted["plain"]!.surfaceEnabled,
        "lightingZeroHasNoLitSurface": !accepted["lightingZero"]!.surfaceEnabled,
        "lightingEnablesSharedSurface": explicitProfile.lightingEnabled && explicitProfile.surfaceEnabled,
        "noOptionalResourcesInvented": explicitProfile.normalSource == .disabled
            && explicitProfile.mapSource == .disabled && explicitProfile.reflection == nil,
        "renamedModelAndMaterialJoinCanonically": Set(renamedCatalog.profiles.keys) == ["models/renamed.json"],
        "equivalentWrapperAndRenamesKeepProfile": renamedCatalog.profiles["models/renamed.json"] == explicitProfile,
        "sourceInstanceIsNotRequired": catalog(explicit).profiles.count == 1,
        "builtinCandidateRetainsCanonicalModelIdentity": catalog(explicit).builtinModelPaths == [model]
    ]
    var noVersion = explicit
    noVersion.combos.removeValue(forKey: "VERSION")
    checks["optionalVersionDoesNotChangeLighting"] = catalog(noVersion).profiles[model] == explicitProfile
    var unsupportedBuiltin = explicit
    unsupportedBuiltin.combos["NORMALMAP"] = 0
    checks["unqualifiedBuiltinRetainsCandidateIdentity"] = catalog(unsupportedBuiltin).builtinModelPaths == [model]
        && catalog(unsupportedBuiltin).profiles.isEmpty
    var customShader = explicit
    customShader.shaderPath = "shaders/unseen.frag"
    checks["sourceShaderDoesNotBecomeBuiltinCandidate"] = catalog(customShader).builtinModelPaths.isEmpty
    var defaultTierTwo = explicit
    defaultTierTwo.shaderPath = "genericimage2"
    defaultTierTwo.alphaWriting = "default"
    checks["tierTwoLitDefaultRetainsTheSameStaticProfile"] = catalog(defaultTierTwo).profiles[model] == explicitProfile
    for (name, input) in [("plain", plain), ("lightingZero", lightingZero),
                          ("tierTwo", tierTwo), ("tierFour", tierFour),
                          ("explicit", explicit), ("clampedFinite", clamped)] {
        checks["sharedCompiler-" + name] = accepted[name] == SceneBaseMaterialLightingProfileCompiler.profile(
            layerID: 0, usesPuppet: false, materialInstance: nil, materialPasses: [input],
            materialPropertyTargets: [], builtinSurface: true)
    }
    // A lit authored instance cannot grant a plain model defaults, and a disabled
    // authored instance cannot remove the reusable model's own lit defaults.
    let sourceLayer = Descriptor.Layer(id: 700, contentKind: "image", imagePath: model, effects: [])
    let litInstance = SceneDocument.SceneLayerMaterialInstance(id: nil, textureSlots: ["instance-only"],
        userTextureInputs: [], hasUserTextureOverride: true, combos: ["LIGHTING": 1],
        unknownKeys: [], isMalformed: false, scalarShaderValues: ["metallic": scalar(0.99)])
    let sourceProgram = SceneBaseMaterialProviderBindingCompiler.compile(
        descriptor: descriptor([plain], layers: [sourceLayer]), materialInstancesByLayerID: [700: litInstance],
        scriptBindings: [], materialPropertyTargets: [])
    checks["authoredInstanceDoesNotBecomeModelDefault"] = sourceProgram.lightingProfileByLayerID[700]?.lightingEnabled == true
        && !catalog(plain).profiles[model]!.lightingEnabled
    let disabledInstance = SceneDocument.SceneLayerMaterialInstance(id: nil, textureSlots: ["instance-only"],
        userTextureInputs: [], hasUserTextureOverride: true, combos: ["LIGHTING": 0],
        unknownKeys: [], isMalformed: false, scalarShaderValues: ["metallic": scalar(0.99)])
    let disabledSourceProgram = SceneBaseMaterialProviderBindingCompiler.compile(
        descriptor: descriptor([explicit], layers: [sourceLayer]),
        materialInstancesByLayerID: [700: disabledInstance], scriptBindings: [], materialPropertyTargets: [])
        .preparingDynamicImageMaterials(catalog(explicit).profiles)
    let newClone = Descriptor.Layer(id: -700, contentKind: "image", imagePath: model, effects: [])
    checks["authoredDisabledInstanceDoesNotDisableClone"] = disabledSourceProgram.lightingProfile(for: sourceLayer)?.lightingEnabled == false
        && disabledSourceProgram.lightingProfile(for: newClone) == explicitProfile
    let withLayer = ScenePreparedImageMaterialCatalog(descriptor: descriptor([explicit], layers: [sourceLayer]))
    checks["sourceLayerPresenceDoesNotChangeModelFact"] = withLayer.profiles == catalog(explicit).profiles

    var depthPass = plain
    depthPass.depthTest = "enabled"
    depthPass.cullMode = "normal"
    let depthState = SceneMaterialRenderState.compile(blending: depthPass.blending,
        depthTest: depthPass.depthTest, depthWrite: depthPass.depthWrite,
        cullMode: depthPass.cullMode, alphaWriting: depthPass.alphaWriting)!
    var depthDescriptor = descriptor([depthPass])
    depthDescriptor.preparedImageMaterialStatesByModelPath = [model: depthState]
    let depthCatalog = ScenePreparedImageMaterialCatalog(descriptor: depthDescriptor)
    checks["preparedNativeDepthStateRetainsRecipe"] = depthCatalog.profiles[model] != nil
        && depthCatalog.renderStates[model] == depthState
    checks["rawDepthDoesNotGrantDynamicQualification"] = catalog(depthPass).profiles.isEmpty
    var unsupportedDepth = depthPass
    unsupportedDepth.combos["UNKNOWN"] = 1
    depthDescriptor = descriptor([unsupportedDepth])
    depthDescriptor.preparedImageMaterialStatesByModelPath = [model: depthState]
    checks["unsupportedRecipeCannotBorrowPreparedState"] = ScenePreparedImageMaterialCatalog(
        descriptor: depthDescriptor).profiles.isEmpty

    var rejected: [String: Bool] = [:]
    func reject(_ name: String, _ mutation: (inout Pass) -> Void) {
        var value = explicit
        mutation(&value)
        rejected[name] = catalog(value).profiles.isEmpty
    }
    reject("nonzeroPassIndex") { $0.passIndex = 1 }
    reject("customShader") { $0.shaderPath = "shaders/unseen.frag" }
    reject("implicitShader") { $0.shaderPath = nil }
    reject("unknownCombo") { $0.combos["UNSEEN"] = 0 }
    reject("unknownZeroNormalCombo") { $0.combos["NORMALMAP"] = 0 }
    reject("unknownReflectionCombo") { $0.combos["REFLECTION"] = 1 }
    reject("unknownVersion") { $0.combos["VERSION"] = 3 }
    reject("tieredLighting") { $0.combos["LIGHTING"] = 2 }
    reject("negativeLighting") { $0.combos["LIGHTING"] = -1 }
    reject("unknownConstant") { $0.constantShaderValues["unseen"] = scalar(1) }
    reject("constantsWithoutLighting") { $0.combos.removeValue(forKey: "LIGHTING") }
    reject("constantsWithLightingZero") { $0.combos["LIGHTING"] = 0 }
    reject("shaderUserValue") { $0.userShaderValues["live"] = "property" }
    reject("mismatchedTexturePath") { $0.texturePaths = ["textures/different"] }
    reject("absentTexturePath") { $0.texturePaths = [] }
    reject("twoTextureSlots") { $0 = replacingInputs($0, slots: ["textures/prepared-albedo", "b"]) }
    reject("emptyTextureSlot") { $0 = replacingInputs($0, slots: [""]) }
    reject("nilTextureSlot") { $0 = replacingInputs($0, slots: [nil]) }
    for (name, input) in [("systemProvider", current), ("propertyProvider", customCover)] {
        rejected[name] = catalog(replacingInputs(explicit, providers: [input])).profiles.isEmpty
    }
    for key in ["metallic", "roughness"] {
        for (name, components, raw) in [
            ("nonfinite", [Double.nan], "nan"), ("infinite", [Double.infinity], "inf"),
            ("extraComponent", [0.2, 0.3], "0.2 0.3"), ("filteredText", [0.2], "0.2 garbage")
        ] {
            reject(key + "-" + name) {
                $0.constantShaderValues[key] = .init(rawValue: raw, userBinding: nil, components: components)
            }
        }
        reject(key + "-userWrapper") {
            $0.constantShaderValues[key] = .init(rawValue: "0.2", userBinding: "live", components: [0.2],
                userValueKind: .string, bindingKeys: ["user", "value"])
        }
        reject(key + "-scriptWrapper") {
            $0.constantShaderValues[key] = .init(rawValue: "0.2", userBinding: nil, components: [0.2],
                scriptSource: "export function update(value) { return value; }", bindingKeys: ["script", "value"])
        }
        reject(key + "-timelineWrapper") {
            $0.constantShaderValues[key] = .init(rawValue: "0.2", userBinding: nil, components: [0.2], timeline: 1)
        }
        reject(key + "-unknownWrapper") { $0.constantShaderValues[key] = scalar(0.2, keys: ["value", "unknown"]) }
    }
    reject("normalBlend") { $0.blending = "normal" }
    reject("missingBlend") { $0.blending = nil }
    reject("enabledDepthTest") { $0.depthTest = "enabled" }
    reject("enabledDepthWrite") { $0.depthWrite = "enabled" }
    reject("normalCull") { $0.cullMode = "normal" }
    reject("tierFourAlphaDefault") { $0.alphaWriting = "default" }
    var plainDefault = pass("genericimage2")
    plainDefault.alphaWriting = "default"
    rejected["plainAlphaDefault"] = catalog(plainDefault).profiles.isEmpty
    var unlitDefault = pass("genericimage2", lighting: 0)
    unlitDefault.alphaWriting = "default"
    rejected["lightingZeroAlphaDefault"] = catalog(unlitDefault).profiles.isEmpty
    reject("alphaEnabled") { $0.alphaWriting = "enabled" }
    var enabledTierTwo = defaultTierTwo
    enabledTierTwo.alphaWriting = "enabled"
    rejected["tierTwoAlphaEnabled"] = catalog(enabledTierTwo).profiles.isEmpty
    reject("unknownAlpha") { $0.alphaWriting = "future" }
    rejected["multiplePasses"] = ScenePreparedImageMaterialCatalog(descriptor: descriptor([explicit, explicit])).profiles.isEmpty
    rejected["duplicateCanonicalModel"] = ScenePreparedImageMaterialCatalog(descriptor: .init(layers: [],
        modelMaterialLinks: [.init(modelPath: model, materialPath: material),
            .init(modelPath: " MODELS\\PREPARED-MATERIAL.JSON ", materialPath: material)],
        materialPasses: [explicit], texturePropertyKeys: [])).profiles.isEmpty
    let duplicateMaterial = replacingInputs(explicit, materialPath: " MATERIALS\\PREPARED-MATERIAL.JSON ")
    rejected["duplicateCanonicalMaterialPass"] = ScenePreparedImageMaterialCatalog(
        descriptor: descriptor([explicit, duplicateMaterial])).profiles.isEmpty
    rejected["missingMaterialPass"] = ScenePreparedImageMaterialCatalog(descriptor: descriptor([])).profiles.isEmpty

    return ["catalog": checks, "rejected": rejected,
        "scalarValues": accepted.mapValues { $0.scalarMaterial.map { [$0.x, $0.y] } ?? [] },
        "program": preparedImageMaterialProgramChecks(profiles: [model: explicitProfile], model: model)]
}

private func preparedImageMaterialProgramChecks(
    profiles: [String: SceneBaseMaterialLightingProfile], model: String
) -> [String: Bool] {
    typealias Program = SceneBaseMaterialProviderBindingProgram
    let colorTarget = SceneDynamicTarget.materialConstant(layerID: 12, passIndex: 0,
        name: "color", materialPath: "materials/retained.json")
    let alphaTarget = SceneDynamicTarget.materialConstant(layerID: 12, passIndex: 0,
        name: "alpha", materialPath: "materials/retained.json")
    let original = Program(baseMaterialBindings: [12: .init(layerID: 12, source: .materialPass,
        slotIndex: 0, provider: .current,
        fallbackAsset: .init(virtualPath: "textures/retained", purpose: .premultipliedColor)!),
        13: .init(layerID: 13, source: .layerInstance, slotIndex: 0, provider: .previous),
        14: .init(layerID: 14, source: .materialPass, slotIndex: 0,
            provider: .userProperty(.init(propertyKey: "retained-cover", purpose: .premultipliedColor)!))],
        rejectedBaseMaterialReasons: [15: "retained-rejection"],
        lightingProfileByLayerID: [12: .disabled, -2: .disabled],
        sourceMaterialAlphaByLayerID: [12: .constant(0.6)], authoredMaterialColors: [model: SIMD3(0.2, 0.4, 0.6)],
        materialColorTargets: [model: colorTarget], sourceMaterialAlphaByModel: [model: .property(target: alphaTarget, fallback: 0.7)])
    let prepared = original.preparingDynamicImageMaterials(profiles)
    func layer(_ id: Int, _ kind: String = "image", _ path: String? = nil) -> SceneRenderDescriptor.Layer {
        .init(id: id, contentKind: kind, imagePath: path ?? model, effects: [])
    }
    let snapshot = SceneDynamicSnapshot.empty(frameIndex: 0)
    let clone = layer(-1)
    return [
        "providerBindingsRetained": prepared.baseMaterialBindings == original.baseMaterialBindings,
        "providerDemandsRetained": prepared.orderedSystemProviderDemands == original.orderedSystemProviderDemands
            && prepared.userPropertyDemands == original.userPropertyDemands && prepared.assetDemands == original.assetDemands,
        "rejectionsAndReportRetained": prepared.rejectedBaseMaterialReasons == original.rejectedBaseMaterialReasons
            && prepared.reportLines() == original.reportLines(),
        "authoredProfilesRetained": prepared.lightingProfileByLayerID == original.lightingProfileByLayerID,
        "sourceAlphaTablesRetained": prepared.sourceMaterialAlphaByLayerID == original.sourceMaterialAlphaByLayerID
            && prepared.sourceMaterialAlphaByModel == original.sourceMaterialAlphaByModel
            && prepared.sourceMaterialAlphaPropertyTargets == [alphaTarget],
        "sourceColorTablesRetained": prepared.authoredMaterialColors == original.authoredMaterialColors
            && prepared.materialColorTargets == original.materialColorTargets,
        "sourceColorAndAlphaConsumersRetained": prepared.sourceMaterialColor(layer: clone, snapshot: snapshot) == SIMD3(0.2, 0.4, 0.6)
            && prepared.sourceMaterialAlpha(layer: clone, snapshot: snapshot) == 0.7
            && prepared.sourceMaterialAlpha(layer: layer(12), snapshot: snapshot) == 0.6,
        "dynamicProfilesPublished": prepared.dynamicLightingProfilesByModelPath == profiles,
        "authoredPositiveIDWins": prepared.lightingProfile(for: layer(12)) == .disabled,
        "authoredNegativeIDWins": prepared.lightingProfile(for: layer(-2)) == .disabled,
        "authoredIDWinsBeforeContentKind": prepared.lightingProfile(for: layer(12, "text")) == .disabled,
        "negativeImageUsesCanonicalModel": prepared.lightingProfile(for: clone) == profiles[model],
        "positiveIDCannotBorrowModel": prepared.lightingProfile(for: layer(999)) == nil,
        "zeroIDCannotBorrowModel": prepared.lightingProfile(for: layer(0)) == nil,
        "negativeTextCannotBorrowModel": prepared.lightingProfile(for: layer(-3, "text")) == nil,
        "negativeSolidCannotBorrowModel": prepared.lightingProfile(for: layer(-3, "solid")) == nil,
        "differentModelCannotBorrowProfile": prepared.lightingProfile(for: layer(-3, "image", "models/unknown.json")) == nil,
        "missingModelCannotBorrowProfile": prepared.lightingProfile(for: .init(
            id: -3, contentKind: "image", imagePath: nil, effects: [])) == nil,
        "queryDoesNotNormalizePerFrame": prepared.lightingProfile(for: layer(-3, "image", " MODELS\\PREPARED-MATERIAL.JSON ")) == nil,
        "emptyHasNoLitWarmup": !Program.empty.hasLitImageConsumers,
        "disabledAuthoredHasNoLitWarmup": !original.hasLitImageConsumers,
        "dynamicPlainHasNoLitWarmup": !Program.empty.preparingDynamicImageMaterials([model: .disabled]).hasLitImageConsumers,
        "dynamicLitRequestsWarmup": prepared.hasLitImageConsumers,
        "authoredLitRequestsWarmup": Program(baseMaterialBindings: [:], lightingProfileByLayerID: [1: profiles[model]!]).hasLitImageConsumers,
        "preparingAgainReplacesDynamicTable": prepared.preparingDynamicImageMaterials([:]).dynamicLightingProfilesByModelPath.isEmpty
            && !prepared.preparingDynamicImageMaterials([:]).hasLitImageConsumers,
        "preparingDoesNotMutateOriginal": original.dynamicLightingProfilesByModelPath.isEmpty
    ]
}
