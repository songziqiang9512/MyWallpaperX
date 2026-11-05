extension Harness {
    static func imageBlendResults() -> [String: Any] {
        let imageBlend = imageBlendBinding()
        let puppetImageBlend = imageBlendBinding(
            providerPuppetMeshPath: "models/character.mdl"
        )
        let forwardImageBlend = imageBlendBinding(providerFirst: false)
        let forwardEffectfulImageBlend = imageBlendBinding(
            providerEffectful: true,
            providerFirst: false
        )
        let transformedImageBlend = imageBlendBinding(
            extraCombos: ["TRANSFORMUV": 1, "TRANSFORMREPEAT": 0],
            extraConstantShaderValues: [
                "blendangle": .init(components: [0]),
                "blendoffset": .init(components: [1164, 0]),
                "blendscale": .init(components: [1]),
            ]
        )
        let imageBlendWithGraphInternalPrevious = imageBlendBinding(
            sameLayerPreviousReference: true
        )
        let nonNormalTransformedImageBlend = imageBlendBinding(
            extraCombos: ["BLENDMODE": 6, "TRANSFORMUV": 1],
            extraConstantShaderValues: [
                "blendangle": .init(components: [0]),
                "blendoffset": .init(components: [100, 200]),
                "blendscale": .init(components: [1.5]),
            ],
            multiply: 1.5
        )
        let nestedImageBlend = nestedImageBlendPlan()
        let nestedProgramReference = nestedProgramReferencePlan()
        let unexplainedProgramDependency = nestedProgramReferencePlan(
            includeInactiveAlternative: false
        )
        let forwardNestedImageBlend = nestedImageBlendPlan(
            forwardToConsumer: true
        )
        let forwardNestedSchedule = forwardNestedImageBlend.sourcePreparationPlan(
            authoredLayerIDs: [399, 402, 400, 401],
            availableExecutionLayerIDs: forwardNestedImageBlend.requiredGraphOutputProviderLayerIDs.union([402]),
            visibleRootLayerIDs: [402], activeStaticModelConsumerLayerIDs: [],
            sourceAfterLayerIDByLayerID: [:])?.preparationSchedule()
        let brokenNestedImageBlend = nestedImageBlendPlan(
            middleDependencyMismatch: true,
            forwardToConsumer: true
        )
        let forwardPreparation = forwardPreparationPlan()
        let forwardSchedule = forwardPreparation.plan.sourcePreparationPlan(
            authoredLayerIDs: forwardPreparation.authoredLayerIDs,
            availableExecutionLayerIDs: forwardPreparation.plan.requiredGraphOutputProviderLayerIDs.union([301]),
            visibleRootLayerIDs: [800, 301, 850, 900], activeStaticModelConsumerLayerIDs: [],
            sourceAfterLayerIDByLayerID: [:])?.preparationSchedule()
        let forwardStaticPreparation = forwardPreparationPlan(
            providerEffectful: false
        )
        let forwardStaticSchedule = forwardStaticPreparation.plan.sourcePreparationPlan(
            authoredLayerIDs: forwardStaticPreparation.authoredLayerIDs,
            availableExecutionLayerIDs: [301], visibleRootLayerIDs: [800, 301, 850, 900],
            activeStaticModelConsumerLayerIDs: [], sourceAfterLayerIDByLayerID: [:])?.preparationSchedule()
        let modelProvider = SceneRenderDescriptor.Layer(
            id: 611,
            contentKind: "solid",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: []
        )
        let modelConsumer = SceneRenderDescriptor.Layer(
            id: 610,
            staticModelPath: "models/unseen/shared.mdl",
            contentKind: "model",
            utilityLayer: nil,
            dependencyLayerIDs: [611],
            childLayerIDs: [],
            visible: false,
            effects: []
        )
        let modelMaterialPath = "materials/unseen/shared.json"
        let modelNamedPath = "_rt_imageLayerComposite_611_a"
        let modelDependencyPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: [modelConsumer, modelProvider],
                renderOrderLayerIDs: [610, 611],
                modelMaterialLinks: [.init(
                    modelPath: "models/unseen/shared.mdl",
                    materialPath: modelMaterialPath
                )],
                materialPasses: [.init(
                    materialPath: modelMaterialPath,
                    passIndex: 0,
                    texturePaths: [modelNamedPath],
                    textureSlots: [modelNamedPath],
                    userTextureInputs: []
                )]
            ),
            visibleLayerIDs: []
        )
        let activeModelForwardProviders = modelDependencyPlan.sourcePreparationPlan(
            authoredLayerIDs: [610, 611], availableExecutionLayerIDs: [],
            visibleRootLayerIDs: [610], activeStaticModelConsumerLayerIDs: [610],
            sourceAfterLayerIDByLayerID: [:])?.preparationSchedule().prepassProviderLayerIDs
        let inactiveModelForwardProviders = modelDependencyPlan.sourcePreparationPlan(
            authoredLayerIDs: [610, 611], availableExecutionLayerIDs: [],
            visibleRootLayerIDs: [610], activeStaticModelConsumerLayerIDs: [],
            sourceAfterLayerIDByLayerID: [:])?.preparationSchedule().prepassProviderLayerIDs
        let modelEffectConsumer = consumer(612, provider: 611)
        let mixedModelProvider = SceneRenderDescriptor.Layer(
            id: 611,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: []
        )
        let mixedModelDescriptor = SceneRenderDescriptor(
            layers: [modelConsumer, modelEffectConsumer, mixedModelProvider],
            renderOrderLayerIDs: [610, 612, 611],
            modelMaterialLinks: [.init(
                modelPath: "models/unseen/shared.mdl",
                materialPath: modelMaterialPath
            )],
            materialPasses: [.init(
                materialPath: modelMaterialPath,
                passIndex: 0,
                texturePaths: [modelNamedPath],
                textureSlots: [modelNamedPath],
                userTextureInputs: []
            )]
        )
        let mixedModelDependencyPlan = SceneDependencyRenderPlan(
            descriptor: mixedModelDescriptor,
            visibleLayerIDs: [612],
            admittedResolvedMaterialReferences: Set(
                SceneDependencyGraphAnalysis.references(
                    in: mixedModelDescriptor.layers
                )
            )
        )
        return [
            "staticModelNamedProvider": [
                "binding": modelDependencyPlan
                    .staticModelBindingsByConsumerLayerID[610] != nil,
                "provider": modelDependencyPlan
                    .staticModelBindingsByConsumerLayerID[610]?
                    .providerLayerID ?? -1,
                "pass": modelDependencyPlan
                    .staticModelBindingsByConsumerLayerID[610]?
                    .passIndex ?? -1,
                "slot": modelDependencyPlan
                    .staticModelBindingsByConsumerLayerID[610]?
                    .slotIndex ?? -1,
                "forward": modelDependencyPlan
                    .staticModelBindingsByConsumerLayerID[610]?
                    .requiresForwardCapture ?? false,
                "required": modelDependencyPlan.requiredProviderLayerIDs
                    .contains(611),
                "activeOrder": activeModelForwardProviders ?? [-1],
                "inactiveOrder": inactiveModelForwardProviders ?? [-1],
            ],
            "mixedModelNamedProvider": [
                "modelBinding": mixedModelDependencyPlan
                    .staticModelBindingsByConsumerLayerID[610] != nil,
                "effectBinding": mixedModelDependencyPlan
                    .bindingsByConsumerLayerID[612] != nil,
                "required": mixedModelDependencyPlan.requiredProviderLayerIDs
                    .contains(611),
            ],
            "imageBlendBinding": [
                "consumer": imageBlend?.consumerLayerID ?? -1,
                "provider": imageBlend?.providerLayerID ?? -1,
                "effect": imageBlend?.slot.effectID ?? "",
                "pass": imageBlend?.slot.passIndex ?? -1,
                "slot": imageBlend?.slot.slotIndex ?? -1,
                "blend": imageBlend?.blendMode ?? -1,
                "imageBlend": imageBlend?.kind == .imageLayerBlend,
                "forwardCapture": imageBlend?.requiresForwardCapture ?? false,
            ],
            "puppetImageBlendRejected": puppetImageBlend == nil,
            "forwardImageBlendBinding": [
                "consumer": forwardImageBlend?.consumerLayerID ?? -1,
                "provider": forwardImageBlend?.providerLayerID ?? -1,
                "imageBlend": forwardImageBlend?.kind == .imageLayerBlend,
                "forwardCapture": forwardImageBlend?.requiresForwardCapture ?? false,
            ],
            "forwardEffectfulImageBlendBinding": [
                "consumer": forwardEffectfulImageBlend?.consumerLayerID ?? -1,
                "provider": forwardEffectfulImageBlend?.providerLayerID ?? -1,
                "imageBlend": forwardEffectfulImageBlend?.kind == .imageLayerBlend,
                "forwardCapture": forwardEffectfulImageBlend?
                    .requiresForwardCapture ?? false,
            ],
            "retiredForwardProviders": [
                "direct": forwardPreparation.plan.sourcePreparationPlan(
                    authoredLayerIDs: [800, 301, 850, 900],
                    availableExecutionLayerIDs: [301], visibleRootLayerIDs: [800, 301, 850, 900],
                    activeStaticModelConsumerLayerIDs: [], sourceAfterLayerIDByLayerID: [:])?.preparationSchedule()
                    .prepassProviderLayerIDs ?? [-1],
                "upstream": forwardNestedImageBlend.sourcePreparationPlan(
                    authoredLayerIDs: [399, 402, 401],
                    availableExecutionLayerIDs: [401, 402], visibleRootLayerIDs: [399, 402],
                    activeStaticModelConsumerLayerIDs: [], sourceAfterLayerIDByLayerID: [:])?.preparationSchedule()
                    .prepassProviderLayerIDs ?? [-1],
                "middle": forwardNestedImageBlend.sourcePreparationPlan(
                    authoredLayerIDs: [399, 402, 400],
                    availableExecutionLayerIDs: [400, 402], visibleRootLayerIDs: [399, 402],
                    activeStaticModelConsumerLayerIDs: [], sourceAfterLayerIDByLayerID: [:])?.preparationSchedule()
                    .prepassProviderLayerIDs ?? [-1],
                "model": modelDependencyPlan.sourcePreparationPlan(
                    authoredLayerIDs: [610], availableExecutionLayerIDs: [], visibleRootLayerIDs: [610],
                    activeStaticModelConsumerLayerIDs: [610], sourceAfterLayerIDByLayerID: [:])?.preparationSchedule()
                    .prepassProviderLayerIDs ?? [-1],
                "duplicateRejected": forwardPreparation.plan.sourcePreparationPlan(
                    authoredLayerIDs: [800, 301, 301],
                    availableExecutionLayerIDs: [301], visibleRootLayerIDs: [800, 301],
                    activeStaticModelConsumerLayerIDs: [], sourceAfterLayerIDByLayerID: [:]) == nil,
            ],
            "forwardEffectfulPreparationOrder": [
                "authored": forwardPreparation.authoredLayerIDs,
                "prepared": forwardSchedule?.preparationLayerIDs ?? [-1],
                "duplicateRejected": forwardPreparation.plan
                    .sourcePreparationPlan(authoredLayerIDs: forwardPreparation.authoredLayerIDs + [900],
                        availableExecutionLayerIDs: [300, 301], visibleRootLayerIDs: [301],
                        activeStaticModelConsumerLayerIDs: [], sourceAfterLayerIDByLayerID: [:]) == nil,
            ],
            "forwardStaticPreparationOrder": [
                "authored": forwardStaticPreparation.authoredLayerIDs,
                "prepared": forwardStaticSchedule?.preparationLayerIDs ?? [-1],
            ],
            "transformedImageBlendBinding": [
                "provider": transformedImageBlend?.providerLayerID ?? -1,
                "imageBlend": transformedImageBlend?.kind == .imageLayerBlend,
                "requiresProgram": transformedImageBlend?
                    .requiresResolvedMaterialProgram ?? false,
            ],
            "imageBlendWithGraphInternalPrevious": [
                "provider": imageBlendWithGraphInternalPrevious?
                    .providerLayerID ?? -1,
                "requiresProgram": imageBlendWithGraphInternalPrevious?
                    .requiresResolvedMaterialProgram ?? false,
            ],
            "nonNormalTransformedImageBlend": [
                "provider": nonNormalTransformedImageBlend?
                    .providerLayerID ?? -1,
                "blend": nonNormalTransformedImageBlend?.blendMode ?? -1,
                "requiresProgram": nonNormalTransformedImageBlend?
                    .requiresResolvedMaterialProgram ?? false,
            ],
            "programRequiredRuntimeRejects": [
                "transform": imageBlendBinding(
                    extraCombos: ["TRANSFORMUV": 1],
                    resolvedMaterialConsumerLayerIDs: []
                ) == nil,
                "graphInternal": imageBlendBinding(
                    sameLayerPreviousReference: true,
                    resolvedMaterialConsumerLayerIDs: []
                ) == nil,
            ],
            "visibleStaticImageBindings": [
                "backward": imageBlendBinding(providerVisible: true)?.providerLayerID == 300,
                "forward": imageBlendBinding(providerVisible: true, providerFirst: false)?.requiresForwardCapture == true,
                "implicitVisible": imageBlendBinding(providerVisible: nil)?.providerLayerID == 300,
                "effectfulNeverRaw": imageBlendBinding(providerVisible: true, providerEffectful: true)?.kind != .imageLayerBlend,
                "puppetRejected": imageBlendBinding(providerVisible: true, providerPuppetMeshPath: "models/mesh.mdl") == nil,
                "childrenRejected": imageBlendBinding(providerVisible: true, providerChildLayerIDs: [305]) == nil,
                "dependenciesRejected": imageBlendBinding(providerVisible: true, providerDependencies: [305]) == nil,
            ],
            "imageBlendRejects": [
                "wrongProviderKind": imageBlendBinding(providerContentKind: "solid") == nil,
                "secondary": imageBlendBinding(variantSuffix: "b") == nil,
                "userTextureOverride": imageBlendBinding(userTextureOverride: true) == nil,
                "extraReference": imageBlendBinding(extraReference: true) == nil,
                "invalidTransform": imageBlendBinding(
                    extraCombos: ["TRANSFORMUV": 2],
                    resolvedMaterialConsumerLayerIDs: []
                ) == nil,
                "repeatWithoutTransform": imageBlendBinding(
                    extraCombos: ["TRANSFORMREPEAT": 1],
                    resolvedMaterialConsumerLayerIDs: []
                ) == nil,
                "invalidTransformOffset": imageBlendBinding(
                    extraCombos: ["TRANSFORMUV": 1],
                    extraConstantShaderValues: [
                        "blendoffset": .init(components: [1]),
                    ],
                    resolvedMaterialConsumerLayerIDs: []
                ) == nil,
                "invalidTransformScale": imageBlendBinding(
                    extraCombos: ["TRANSFORMUV": 1],
                    extraConstantShaderValues: [
                        "blendscale": .init(components: [0]),
                    ],
                    resolvedMaterialConsumerLayerIDs: []
                ) == nil,
                "invalidBlendMode": imageBlendBinding(
                    extraCombos: ["BLENDMODE": 33],
                    resolvedMaterialConsumerLayerIDs: []
                ) == nil,
            ],
            "partialStrengthRequiresProgram":
                imageBlendBinding(multiply: 0.5)?
                    .requiresResolvedMaterialProgram == true,
            "imageBlendEffectfulProvider":
                imageBlendBinding(providerEffectful: true)?.providerLayerID == 300,
            "forwardImageBlendOrderIndependentAssetProvider":
                imageBlendBinding(
                    providerEffectful: true,
                    providerTexturePaths: ["assets/noise.tex"],
                    providerFirst: false
                )?.providerLayerID == 300,
            "forwardImageBlendRejects": [
                "inactiveEffect": imageBlendBinding(
                    providerEffectful: true,
                    providerEffectVisible: false,
                    providerFirst: false
                ) == nil,
                "dependency": imageBlendBinding(
                    providerDependencies: [299], providerFirst: false
                ) == nil,
                "child": imageBlendBinding(
                    providerChildLayerIDs: [302], providerFirst: false
                ) == nil,
                "secondary": imageBlendBinding(
                    variantSuffix: "b", providerFirst: false
                ) == nil,
                "sceneBackground": imageBlendBinding(
                    providerEffectful: true,
                    providerTexturePaths: ["_rt_FullFrameBuffer"],
                    providerFirst: false
                ) == nil,
                "implicitNamedInput": imageBlendBinding(
                    providerEffectful: true,
                    providerTexturePaths: ["_rt_imageLayerComposite_299_a"],
                    providerFirst: false
                ) == nil,
            ],
            "nestedImageBlend": [
                "bindings": nestedImageBlend.bindingsByConsumerLayerID.keys.sorted(),
                "providers": nestedImageBlend.requiredProviderLayerIDs.sorted(),
                "graphProviders": nestedImageBlend
                    .requiredGraphOutputProviderLayerIDs.sorted(),
                "effectConsumers": nestedImageBlend
                    .requiredEffectConsumerLayerIDs.sorted(),
                "passthroughBlocked": [400, 401, 402].filter {
                    nestedImageBlend.blocksStaticLayerSourcePassthrough(for: $0)
                },
                "issues": nestedImageBlend.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "nestedProgramReference": [
                "bindings": nestedProgramReference
                    .bindingsByConsumerLayerID.keys.sorted(),
                "providers": nestedProgramReference
                    .requiredProviderLayerIDs.sorted(),
                "graphProviders": nestedProgramReference
                    .requiredGraphOutputProviderLayerIDs.sorted(),
                "effectConsumers": nestedProgramReference
                    .requiredEffectConsumerLayerIDs.sorted(),
                "issues": nestedProgramReference.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "unexplainedProgramDependencyRejected":
                unexplainedProgramDependency.bindingsByConsumerLayerID[502]
                    == nil,
            "forwardNestedImageBlend": [
                "bindings": forwardNestedImageBlend
                    .bindingsByConsumerLayerID.keys.sorted(),
                "providers": forwardNestedImageBlend
                    .requiredProviderLayerIDs.sorted(),
                "graphProviders": forwardNestedImageBlend
                    .requiredGraphOutputProviderLayerIDs.sorted(),
                "forwardProviders": forwardNestedSchedule?.prepassProviderLayerIDs ?? [-1],
                "prepared": forwardNestedSchedule?.preparationLayerIDs ?? [-1],
                "issues": forwardNestedImageBlend.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "brokenNestedImageBlend": [
                "bindings": brokenNestedImageBlend
                    .bindingsByConsumerLayerID.keys.sorted(),
                "providers": brokenNestedImageBlend.requiredProviderLayerIDs.sorted(),
                "graphProviders": brokenNestedImageBlend
                    .requiredGraphOutputProviderLayerIDs.sorted(),
            ],
        ]
    }

    static func imageBlendBinding(
        providerVisible: Bool? = false,
        providerContentKind: String = "image",
        providerEffectful: Bool = false,
        providerEffectVisible: Bool? = true,
        providerTexturePaths: [String] = [],
        providerDependencies: [Int] = [],
        providerChildLayerIDs: [Int] = [],
        variantSuffix: String = "a",
        userTextureOverride: Bool = false,
        extraReference: Bool = false,
        dependencyMismatch: Bool = false,
        extraCombos: [String: Int] = [:],
        extraConstantShaderValues: [String: SceneDocument.ShaderValue] = [:],
        sameLayerPreviousReference: Bool = false,
        resolvedMaterialConsumerLayerIDs: Set<Int>? = nil,
        multiply: Double = 1,
        providerFirst: Bool = true,
        providerPuppetMeshPath: String? = nil
    ) -> SceneDependencyRenderPlan.Binding? {
        let providerID = 300
        let consumerID = 301
        let providerEffects: [SceneRenderDescriptor.EffectDescriptor] = providerEffectful
            ? [.init(
                id: "provider-effect",
                file: "effects/tint/effect.json",
                visible: providerEffectVisible,
                passes: providerTexturePaths.isEmpty ? [] : [.init(
                    passIndex: 0,
                    texturePaths: providerTexturePaths,
                    textureSlots: providerTexturePaths.map(Optional.some),
                    userTextureInputs: [],
                    combos: [:],
                    constantShaderValues: [:]
                )]
            )] : []
        var provider = SceneRenderDescriptor.Layer(
            id: providerID,
            contentKind: providerContentKind,
            utilityLayer: nil,
            dependencyLayerIDs: providerDependencies,
            childLayerIDs: providerChildLayerIDs,
            visible: providerVisible,
            effects: providerEffects
        )
        provider.puppetMeshPath = providerPuppetMeshPath
        let primary = "_rt_imageLayerComposite_\(providerID)_\(variantSuffix)"
        let extra = "_rt_imageLayerComposite_299_a"
        var slots: [String?] = [nil, primary]
        if extraReference { slots.append(extra) }
        var combos = ["BLENDMODE": 0]
        combos.merge(extraCombos) { _, new in new }
        var constantShaderValues: [String: SceneDocument.ShaderValue] = [
            "multiply": .init(components: [multiply]),
            "alpha": .init(components: [1]),
        ]
        constantShaderValues.merge(extraConstantShaderValues) { _, new in new }
        let blend = SceneRenderDescriptor.EffectDescriptor(
            id: "image-blend",
            file: "effects/blend/effect.json",
            visible: true,
            passes: [.init(
                passIndex: 0,
                texturePaths: extraReference ? [primary, extra] : [primary],
                textureSlots: slots,
                userTextureInputs: userTextureOverride ? [
                    nil,
                    .init(kind: .property, value: "userTexture"),
                ] : [],
                combos: combos,
                constantShaderValues: constantShaderValues
            )]
        )
        let previousPath = "_rt_imageLayerComposite_\(consumerID)_b"
        let graphInternalPrevious = SceneRenderDescriptor.EffectDescriptor(
            id: "graph-internal-previous",
            file: "effects/localcontrast/effect.json",
            visible: true,
            passes: [.init(
                passIndex: 0,
                texturePaths: [previousPath],
                textureSlots: [nil, previousPath],
                userTextureInputs: [],
                combos: [:],
                constantShaderValues: [:]
            )]
        )
        let consumer = SceneRenderDescriptor.Layer(
            id: consumerID,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: dependencyMismatch ? [299] : [providerID],
            childLayerIDs: [],
            visible: true,
            effects: [blend] + (sameLayerPreviousReference
                ? [graphInternalPrevious] : [])
        )
        let descriptor = SceneRenderDescriptor(
            layers: [provider, consumer],
            renderOrderLayerIDs: providerFirst
                ? [providerID, consumerID] : [consumerID, providerID]
        )
        let admittedReferences: Set<SceneDependencyRenderPlan.Reference> =
            resolvedMaterialConsumerLayerIDs == [] ? [] : Set(
                SceneDependencyGraphAnalysis.references(in: descriptor.layers)
            )
        return SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: [consumerID],
            admittedResolvedMaterialReferences: admittedReferences
        ).bindingsByConsumerLayerID[consumerID]
    }

    static func nestedImageBlendPlan(
        middleDependencyMismatch: Bool = false,
        forwardToConsumer: Bool = false
    ) -> SceneDependencyRenderPlan {
        func blend(_ id: Int, provider: Int) ->
            SceneRenderDescriptor.EffectDescriptor {
            let path = "_rt_imageLayerComposite_\(provider)_a"
            return .init(
                id: "blend-\(id)",
                file: "effects/blend/effect.json",
                visible: true,
                passes: [.init(
                    passIndex: 0,
                    texturePaths: [path],
                    textureSlots: [nil, path],
                    combos: ["BLENDMODE": 0],
                    constantShaderValues: [
                        "multiply": .init(components: [1]),
                        "alpha": .init(components: [1]),
                    ]
                )]
            )
        }
        let rootProvider = SceneRenderDescriptor.Layer(
            id: 400,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: [.init(
                id: "provider-color",
                file: "effects/tint/effect.json",
                visible: true,
                passes: []
            )]
        )
        let middleProvider = SceneRenderDescriptor.Layer(
            id: 401,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: middleDependencyMismatch ? [499] : [400],
            childLayerIDs: [],
            visible: false,
            effects: [blend(401, provider: 400)]
        )
        let consumer = SceneRenderDescriptor.Layer(
            id: 402,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [401],
            childLayerIDs: [],
            visible: true,
            effects: [blend(402, provider: 401)]
        )
        let independent = SceneRenderDescriptor.Layer(
            id: 399,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: true,
            effects: []
        )
        let descriptor = SceneRenderDescriptor(
            layers: [independent, rootProvider, middleProvider, consumer],
            renderOrderLayerIDs: forwardToConsumer
                ? [399, 402, 400, 401] : [399, 400, 401, 402]
        )
        return SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: [402]
        )
    }

    static func nestedProgramReferencePlan(
        includeInactiveAlternative: Bool = true
    ) -> SceneDependencyRenderPlan {
        func programEffect(_ id: Int, provider: Int) ->
            SceneRenderDescriptor.EffectDescriptor {
            let path = "_rt_imageLayerComposite_\(provider)_a"
            return .init(
                id: "program-reference-\(id)",
                file: "effects/workshop/unseen/program/effect.json",
                visible: true,
                passes: [.init(
                    passIndex: 0,
                    texturePaths: [path, "util/white"],
                    textureSlots: [nil, path, "util/white"],
                    combos: ["UNSEEN": 7],
                    constantShaderValues: [
                        "amount": .init(components: [0.375]),
                    ]
                )]
            )
        }
        let root = SceneRenderDescriptor.Layer(
            id: 500,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: [.init(
                id: "root-effect",
                file: "effects/workshop/unseen/root/effect.json",
                visible: true,
                passes: []
            )]
        )
        let middle = SceneRenderDescriptor.Layer(
            id: 501,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [root.id],
            childLayerIDs: [],
            visible: false,
            effects: [
                .init(
                    id: "middle-prefix",
                    file: "effects/workshop/unseen/prefix/effect.json",
                    visible: true,
                    passes: []
                ),
                programEffect(501, provider: root.id),
            ]
        )
        let consumer = SceneRenderDescriptor.Layer(
            id: 502,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [middle.id, 503],
            childLayerIDs: [],
            visible: true,
            effects: [
                .init(
                    id: "consumer-prefix",
                    file: "effects/workshop/unseen/prefix/effect.json",
                    visible: true,
                    passes: []
                ),
                programEffect(502, provider: middle.id),
            ] + (includeInactiveAlternative ? [
                .init(
                    id: "inactive-alternative",
                    file: "effects/workshop/unseen/alternate/effect.json",
                    visible: false,
                    passes: [.init(
                        passIndex: 0,
                        texturePaths: ["_rt_imageLayerComposite_503_a"],
                        textureSlots: [
                            nil, "_rt_imageLayerComposite_503_a",
                        ],
                        combos: [:],
                        constantShaderValues: [:]
                    )]
                ),
            ] : [])
        )
        let inactiveAlternative = SceneRenderDescriptor.Layer(
            id: 503,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: []
        )
        let descriptor = SceneRenderDescriptor(
            layers: [root, middle, inactiveAlternative, consumer],
            renderOrderLayerIDs: [
                root.id, middle.id, inactiveAlternative.id, consumer.id,
            ]
        )
        return SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: [consumer.id],
            admittedResolvedMaterialReferences: Set(
                SceneDependencyGraphAnalysis.references(in: descriptor.layers)
            )
        )
    }

    static func forwardPreparationPlan(
        providerEffectful: Bool = true
    ) -> (
        plan: SceneDependencyRenderPlan,
        authoredLayerIDs: [Int]
    ) {
        let providerID = 300
        let consumerID = 301
        let provider = SceneRenderDescriptor.Layer(
            id: providerID,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: providerEffectful ? [.init(
                id: "provider-effect",
                file: "effects/tint/effect.json",
                visible: true,
                passes: []
            )] : []
        )
        let reference = "_rt_imageLayerComposite_\(providerID)_a"
        let consumer = SceneRenderDescriptor.Layer(
            id: consumerID,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [providerID],
            childLayerIDs: [],
            visible: true,
            effects: [.init(
                id: "image-blend",
                file: "effects/blend/effect.json",
                visible: true,
                passes: [.init(
                    passIndex: 0,
                    texturePaths: [reference],
                    textureSlots: [nil, reference],
                    combos: ["BLENDMODE": 0],
                    constantShaderValues: [
                        "multiply": .init(components: [1]),
                        "alpha": .init(components: [1]),
                    ]
                )]
            )]
        )
        let independentLayerIDs = [800, 850, 900]
        let independent = independentLayerIDs.map { layer($0) }
        let authored = [800, consumerID, 850, providerID, 900]
        let descriptor = SceneRenderDescriptor(
            layers: independent + [provider, consumer],
            renderOrderLayerIDs: authored
        )
        let admittedReferences = Set(
            SceneDependencyGraphAnalysis.references(in: descriptor.layers)
        )
        return (
            SceneDependencyRenderPlan(
                descriptor: descriptor,
                visibleLayerIDs: Set(independentLayerIDs + [consumerID]),
                admittedResolvedMaterialReferences: admittedReferences
            ),
            authored
        )
    }
}
