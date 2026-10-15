import Foundation

/// Typed projection of one admitted catalog template. Wrapper equality and
/// trusted bytecode stay in the original C domain; this is its input metadata.
nonisolated struct SceneScriptPreparedTextTemplate {
    enum Kind: UInt32 { case value = 1, user = 2, script = 3 }
    let identity: UInt64
    let kind: Kind
    let sourceTarget: SceneDynamicTarget
    let authoredSeed: String
    let outerUserInstruction: ScenePropertyBindingInstruction?
    let scriptPropertyInputs: [String: SceneScriptPropertyInput]
    let scriptPropertyInputTargets: Set<SceneDynamicTarget>
    let sourceOwner: SceneScriptValueOwner?

    func definition(layerID: Int) -> SceneDynamicTargetDefinition {
        .init(target: .text(layerID: layerID, field: .content),
              valueType: .string, authoredValue: .string(authoredSeed))
    }
}

nonisolated struct SceneScriptPreparedTextCloneAdoption {
    var definitions: [SceneDynamicTargetDefinition] = []
    var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
    var queueFailure: SceneScriptScalarRuntimeFailure?
}

extension SceneScriptStringProgram {
    /// Called once after the original catalog, String owners and property
    /// program have prepared successfully. It never discovers new source.
    @discardableResult
    func configurePreparedTextTemplates(
        domain: SceneScriptQuickJSDomain?, descriptor: SceneRenderDescriptor,
        propertyBindingProgram: ScenePropertyBindingProgram
    ) -> [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] {
        guard preparedTextTemplateDomain == nil, let domain else { return [:] }
        preparedTextTemplateDomain = domain
        let validation = ScenePropertyBindingProgramValidator().validate(propertyBindingProgram)
        let instructions = Dictionary(grouping: validation.instructions, by: \.target)
        let propertyDefinitions = Dictionary(grouping: validation.definitions, by: \.target)
        let owners = Dictionary(uniqueKeysWithValues: bindings.map { ($0.target, $0) })
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        for layer in descriptor.layers where layer.contentKind == "text" {
            guard case let .object(configuration)? = layer.initialConfiguration,
                  case let .object(wrapper)? = configuration["text"],
                  case let .string(seed)? = wrapper["value"] else { continue }
            let keys = wrapper.keys.sorted()
            let target = SceneDynamicTarget.text(layerID: layer.id, field: .content)
            let hasScript = wrapper["script"] != nil
            let outerUserKey: String?
            switch wrapper["user"] {
            case let .string(key)?: outerUserKey = key
            case .null?, nil: outerUserKey = nil
            default: continue
            }
            let hasUser = outerUserKey != nil
            guard hasScript
                ? SceneScriptDynamicProviderHostContract.supports(keys: keys, host: .objectText)
                : (keys == ["value"] || keys == ["user", "value"]) else { continue }
            let instruction = instructions[target]?.count == 1 ? instructions[target]?.first : nil
            if hasUser {
                guard let instruction, instruction.valueType == .string,
                      instruction.propertyKey == outerUserKey,
                      propertyDefinitions[target]?.count == 1,
                      propertyDefinitions[target]?.first?.authoredValue == .string(seed)
                else { continue }
            }
            let sourceOwner = hasScript ? owners[target] : nil
            if hasScript && sourceOwner?.supportsPreparedTextClone != true { continue }
            let kind: SceneScriptPreparedTextTemplate.Kind = hasScript ? .script : (hasUser ? .user : .value)
            let properties = hasScript ? propertyInputsByTarget[target] ?? [:] : [:]
            guard let propertiesJSON = SceneScriptPropertyInputCodec.scriptPropertiesJSON(
                properties, effectiveValues: [:]
            ) else { continue }
            var identity: UInt64 = 0
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = seed.withCString { authored in
                propertiesJSON.withCString { inputs in
                    mwx_scene_quickjs_domain_prepare_text_template(
                        domain.handle, sourceOwner?.handle, Int64(layer.id), kind.rawValue,
                        authored, seed.utf8.count, authored, seed.utf8.count,
                        inputs, propertiesJSON.utf8.count, &identity,
                        &diagnostic, diagnostic.count
                    )
                }
            }
            guard result == MWX_SCENE_QUICKJS_OK, identity != 0 else {
                failures[target] = SceneScriptValueOwner.failure(result, diagnostic)
                continue
            }
            preparedTextTemplates[identity] = .init(
                identity: identity, kind: kind, sourceTarget: target, authoredSeed: seed,
                outerUserInstruction: hasUser ? instruction : nil,
                scriptPropertyInputs: properties,
                scriptPropertyInputTargets: (livePropertyInputTargetsByTarget[target] ?? [])
                    .subtracting([target]),
                sourceOwner: sourceOwner
            )
        }
        return failures
    }

    /// Refresh before any VM family runs. The property state owns the values
    /// and revision; these bytes are only its cached host-input projection.
    @discardableResult
    func preparePreparedTextCloneInputs(
        userValues: [SceneDynamicTarget: SceneDynamicValue],
        effectivePropertyValues: [String: SceneUserPropertyValue],
        propertyRevision: UInt64?
    ) -> [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] {
        guard let domain = preparedTextTemplateDomain else { return [:] }
        if let propertyRevision, preparedTextTemplateInputRevision == propertyRevision { return [:] }
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        for template in preparedTextTemplates.values {
            let current: String
            if template.outerUserInstruction != nil,
               case let .string(value)? = userValues[template.sourceTarget] {
                current = value
            } else {
                current = template.authoredSeed
            }
            guard let propertiesJSON = scriptPropertiesJSONCache.value(
                for: template.sourceTarget, inputs: template.scriptPropertyInputs,
                effectiveValues: effectivePropertyValues, revision: propertyRevision
            ) else {
                failures[template.sourceTarget] = .invalidArgument("SceneScript properties unavailable")
                var diagnostic = [CChar](repeating: 0, count: 512)
                let unavailable = mwx_scene_quickjs_domain_refresh_text_template_inputs(
                    domain.handle, template.identity, nil, 0, nil, 0,
                    &diagnostic, diagnostic.count
                )
                if unavailable != MWX_SCENE_QUICKJS_OK {
                    failures[template.sourceTarget] = SceneScriptValueOwner.failure(unavailable, diagnostic)
                }
                continue
            }
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = current.withCString { value in
                propertiesJSON.withCString { properties in
                    mwx_scene_quickjs_domain_refresh_text_template_inputs(
                        domain.handle, template.identity, value, current.utf8.count,
                        properties, propertiesJSON.utf8.count, &diagnostic, diagnostic.count
                    )
                }
            }
            if result != MWX_SCENE_QUICKJS_OK {
                failures[template.sourceTarget] = SceneScriptValueOwner.failure(result, diagnostic)
                let unavailable = mwx_scene_quickjs_domain_refresh_text_template_inputs(
                    domain.handle, template.identity, nil, 0, nil, 0,
                    &diagnostic, diagnostic.count
                )
                if unavailable != MWX_SCENE_QUICKJS_OK {
                    failures[template.sourceTarget] = SceneScriptValueOwner.failure(unavailable, diagnostic)
                }
            }
        }
        if failures.isEmpty { preparedTextTemplateInputRevision = propertyRevision }
        return failures
    }

    /// Drain only after every family finalized the shared frame transaction.
    /// C has already initialized and committed each child; Swift takes its
    /// handle once and enrolls it in the ordinary String lifecycle.
    func adoptCommittedPreparedTextClones(
        frame: SceneScriptFrameInput,
        liveTextTemplates: [Int: UInt64]
    ) -> SceneScriptPreparedTextCloneAdoption {
        var adoption = SceneScriptPreparedTextCloneAdoption()
        guard let domain = preparedTextTemplateDomain else { return adoption }
        while true {
            var child: OpaquePointer?
            var identity: UInt64 = 0
            var layerID: Int64 = 0
            var creatorIdentity: UInt64 = 0
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = mwx_scene_quickjs_domain_take_committed_text_clone(
                domain.handle, &child, &identity, &layerID, &creatorIdentity,
                &diagnostic, diagnostic.count
            )
            guard result == MWX_SCENE_QUICKJS_OK else {
                adoption.queueFailure = SceneScriptValueOwner.failure(result, diagnostic)
                return adoption
            }
            guard let child else { return adoption }
            // The accepted topology may remove a creator born this cadence.
            // C has not received that authored tombstone yet, so its committed
            // queue alone cannot authorize a live String binding.
            guard liveTextTemplates[Int(layerID)] == identity else {
                mwx_scene_quickjs_owner_destroy(child)
                continue
            }
            let target = SceneDynamicTarget.text(layerID: Int(layerID), field: .content)
            guard layerID < 0, layerID >= -9_007_199_254_740_991,
                  creatorIdentity != 0, bindingIndicesByTarget[target] == nil,
                  let template = preparedTextTemplates[identity], template.kind == .script,
                  let sourceOwner = template.sourceOwner else {
                mwx_scene_quickjs_owner_destroy(child)
                adoption.failures[target] = .invalidArgument("committed text clone metadata mismatch")
                continue
            }
            let owner: SceneScriptValueOwner
            do {
                owner = try .init(adoptingPreparedTextClone: child,
                                  layerID: Int(layerID), templateOwner: sourceOwner)
            } catch let failure as SceneScriptScalarRuntimeFailure {
                mwx_scene_quickjs_owner_destroy(child)
                adoption.failures[target] = failure
                continue
            } catch {
                mwx_scene_quickjs_owner_destroy(child)
                adoption.failures[target] = .invalidArgument(String(describing: error))
                continue
            }
            bindingIndicesByTarget[target] = bindings.count
            bindings.append(owner)
            let definition = template.definition(layerID: Int(layerID))
            definitions.append(definition)
            inputTargets.insert(target)
            propertyInputsByTarget[target] = template.scriptPropertyInputs
            // Existing prepared property targets remain the input producers;
            // the clone owns its result, not another property binding tree.
            var liveInputs = template.scriptPropertyInputTargets
            if owner.handlesUserProperties {
                liveInputs.insert(target)
                for key in liveUserPropertyConsumerTargetsByKey.keys {
                    liveUserPropertyConsumerTargetsByKey[key, default: []].insert(target)
                }
            }
            livePropertyInputTargetsByTarget[target] = liveInputs
            livePropertyInputTargets.formUnion(liveInputs)
            adoption.definitions.append(definition)
        }
    }
}
