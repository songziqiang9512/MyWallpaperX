import Foundation

/// The approved product default for an authored color pass that neither the
/// shared source analyzer nor the compiler-artifact analyzer could classify.
/// Every sampled color input in the boundary set enters authored math as
/// straight color and every terminal `return out;` premultiplies the output
/// once, matching the compositor's premultiplied publication. The authored
/// math itself is not proven here; a visual verdict on the real sample, not a
/// per-shape analyzer, accepts or rejects the result.
extension SceneGenericShaderArtifactBuilder {
    static let defaultStraightColorBoundaryKind = "default-straight-color-boundary"

    /// Proven shapes keep their exact lowering. When that lowering rejects the
    /// compiler output for a straight-color classification, the product
    /// default boundary takes over instead of failing the whole effect.
    static func prepareColorTransfer(
        msl source: String,
        authoredSource: String,
        expectedColorTransfer: SceneGenericShaderExpectedColorTransfer? = nil,
        defaultBoundaryColorSlots: Set<Int> = []
    ) throws -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    ) {
        do {
            return try prepareProvenColorTransfer(
                msl: source,
                authoredSource: authoredSource,
                expectedColorTransfer: expectedColorTransfer,
                defaultBoundaryColorSlots: defaultBoundaryColorSlots
            )
        } catch Failure.colorTransfer {
            // A profile that expects an independent signal describes a
            // non-color output; only straight-color expectations may fall
            // back to the default boundary.
            let expectedAllowsFallback = expectedColorTransfer == nil
                    || expectedColorTransfer?.kind == "straight-alpha-preserving"
            let classificationPermits = SceneAuthoredShaderColorTransferAnalyzer
                .analyze(fragmentSource: authoredSource)
                .permitsDefaultStraightColorBoundary
            let strictOwner = hasStrictCompilerOwner(authoredSource)
            let filterContractValid = compilerPreservedAlphaRGBFilterContractIsValid(
                msl: source,
                authoredSource: authoredSource
            )
            let lowered = SceneGenericShaderDefaultStraightColorBoundaryLowering
                .lower(source, colorSlots: defaultBoundaryColorSlots)
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains(
                "--mwx-debug-scene-evidence-dir"
            ) {
                NSLog(
                    "MWX DEBUG SCENE: phase=artifact-color-transfer-fallback-rejected expected=%d permits=%d strictOwner=%d filter=%d lowered=%d",
                    expectedAllowsFallback ? 1 : 0,
                    classificationPermits ? 1 : 0,
                    strictOwner ? 1 : 0,
                    filterContractValid ? 1 : 0,
                    lowered == nil ? 0 : 1
                )
            }
#endif
            guard expectedAllowsFallback,
                  classificationPermits,
                  !strictOwner,
                  filterContractValid,
                  let lowered else {
                throw Failure.colorTransfer
            }
            return (
                lowered.msl,
                .init(
                    kind: defaultStraightColorBoundaryKind,
                    slot: nil,
                    slots: lowered.appliedSlots
                )
            )
        }
    }

    /// A product default may recover a color pass whose exact compiler shape
    /// is not owned. It must not turn a rejected artifact into a successful
    /// result after the authored source has selected a narrower owner whose
    /// slot roles and terminal data flow are part of the contract.
    private static func hasStrictCompilerOwner(_ authoredSource: String) -> Bool {
        // The reconstruction owner validates slot projections and terminal
        // alpha flow. A rejected compiler artifact must not bypass that proof
        // through the default boundary, regardless of local identifier names.
        if SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer
            .analyze(fragmentSource: authoredSource) != nil {
            return true
        }
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: authoredSource, stage: .fragment
            ),
            stage: .fragment
        )
        if syntax.diagnostics.isEmpty, let fragment = syntax.unit,
           SceneAuthoredShaderAlphaAttenuationAnalyzer
            .directOutputFact(fragment) != nil {
            return true
        }
        if SceneAuthoredShaderSameSlotColorBlendAlphaUnionAnalyzer
            .analyze(fragmentSource: authoredSource) != nil {
            return true
        }
        if let fact = SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
            .analyzeSourceCarried(fragmentSource: authoredSource),
           fact.shape == .generatedCarrier {
            return true
        }
        if SceneAuthoredShaderAssociatedOverBlendAnalyzer.analyze(
            fragmentSource: authoredSource
        ) != nil {
            return true
        }
        let blendSlots = SceneAuthoredShaderColorTransferAnalyzer
            .blendSourceSlots(fragmentSource: authoredSource)
        if blendSlots.overlayAlpha != nil
            || blendSlots.overlayAlphaPreserving != nil {
            return true
        }
        if SceneAuthoredShaderColorTransferAnalyzer.rgbBlendScalarAlphaFact(
            fragmentSource: authoredSource
        ) != nil {
            return true
        }
        if SceneAuthoredShaderColorTransferAnalyzer.straightRGBScalarAlphaFact(
            fragmentSource: authoredSource
        ) != nil {
            return true
        }
        return SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
            fragmentSource: authoredSource
        ) != nil
    }

    /// The default straight-color boundary may cover an unclassified output
    /// shape, but it cannot hide a compiler change to a source-proven
    /// preserved-alpha RGB filter. Keep the sample count and projection
    /// contract from the authored fact in force before allowing that fallback.
    private static func compilerPreservedAlphaRGBFilterContractIsValid(
        msl source: String,
        authoredSource: String
    ) -> Bool {
        if case .generatedStraightAlpha =
            SceneAuthoredShaderColorTransferAnalyzer.analyze(
                fragmentSource: authoredSource
            ) {
            return SceneGenericShaderGeneratedStraightRGBALowering
                .compilerContractMatches(source)
        }
        guard case let .straightAlphaPreserving(expectedSlot) =
            SceneAuthoredShaderColorTransferAnalyzer.analyze(
                fragmentSource: authoredSource
            ) else {
            return true
        }
        if let slot = SceneAuthoredShaderColorTransferAnalyzer
            .sameSlotCarrierBlendSourceSlot(fragmentSource: authoredSource) {
            return SceneGenericShaderSameSlotCarrierBlendLowering
                .compilerContractMatches(source, expectedSlot: slot)
        }
        if let fact = SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer
            .analyzeAny(fragmentSource: authoredSource) {
            return SceneGenericShaderStraightAlphaPreservingLowering
                .preservedAlphaRGBFilterCompilerSamplesMatch(
                    in: source,
                    sourceSlot: fact.sourceSlot,
                    fullColorSampleCallCounts: fact.fullColorSampleCallCounts,
                    rgbColorSampleCallCounts: fact.rgbColorSampleCallCounts,
                    dataSampleCallCounts: fact.dataSampleCallCounts,
                    scalarDataSampleCallCounts:
                        fact.scalarDataSampleCallCounts
                )
        }
        if let fact = SceneAuthoredShaderTypedDataRGBFilterAnalyzer.analyze(
            fragmentSource: authoredSource
        ) {
            return SceneGenericShaderTypedDataRGBFilterLowering
                .compilerContractMatches(source, fact: fact)
        }
        if let fact = SceneAuthoredShaderStraightBlendOutputAnalyzer
            .analyzeAlphaPreservingGeneratedRGB(
                fragmentSource: authoredSource
            ) {
            return SceneGenericShaderGeneratedRGBPreservedAlphaLowering
                .compilerContractMatches(source, fact: fact)
        }
        if let match = SceneGenericShaderScalarizedRGBPreservedAlphaLowering
            .compilerContractMatchIfCandidate(
                source,
                expectedSlot: expectedSlot
            ) {
            return match
        }
        return true
    }

    static func prepareUnresolvedColorTransfer(
        msl source: String,
        boundaryColorSlots: Set<Int>
    ) throws -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    ) {
        do {
            return try prepareCompilerProvenColorTransfer(source)
        } catch {
            guard let lowered = SceneGenericShaderDefaultStraightColorBoundaryLowering
                .lower(source, colorSlots: boundaryColorSlots) else {
                throw Failure.colorTransfer
            }
            return (
                lowered.msl,
                .init(
                    kind: defaultStraightColorBoundaryKind,
                    slot: nil,
                    slots: lowered.appliedSlots
                )
            )
        }
    }

    static func defaultBoundaryTransfer(
        _ transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer,
        isBoundBy boundSlots: Set<Int>
    ) -> Bool {
        guard transfer.kind == defaultStraightColorBoundaryKind,
              transfer.slot == nil,
              let slots = transfer.slots else { return false }
        return slots == slots.sorted()
            && Set(slots).count == slots.count
            && Set(slots).isSubset(of: boundSlots)
    }
}

nonisolated enum SceneGenericShaderDefaultStraightColorBoundaryLowering {
    struct Lowered: Equatable {
        let msl: String
        /// Sorted color slots whose sample calls were unpremultiplied. Slots
        /// in the boundary set that the fragment never samples are omitted.
        let appliedSlots: [Int]
    }

    private static let unpremultiply = "mwxGenericUnpremultiply"
    private static let premultiply = "mwxGenericPremultiply"

    /// Applies the prepared ordinary-color ABI to original compiler MSL after
    /// the source/compiler proof has succeeded. No authored expression is
    /// replaced by a shape-specific reconstructed output.
    static func lowerOrdinary(
        _ original: String,
        boundary: SceneShaderColorBoundary,
        stage: SceneShaderContract.StageKind = .fragment,
        includeBoundaryHelpers: Bool = true
    ) -> String? {
        guard boundary.isValid,
              !original.contains("mwxStraightColorInput"),
              !original.contains("mwxStraightColorOutput"),
              !original.contains("mwxPassthroughColorOutput"),
              !original.contains("mwxUnpremultiply"),
              !original.contains(unpremultiply),
              !original.contains(premultiply),
              SceneShaderSourceTextFacts.matches(#"\busing\s+namespace\s+metal\s*;"#, in: original).count == 1,
              let source = ordinaryUniformContexts(original, boundary: boundary),
              let calls = SceneGenericShaderStraightAlphaPreservingLowering
                .compilerTextureSampleCalls(in: source),
              let scopes = ordinaryFunctionScopes(source) else { return nil }
        let returns = SceneShaderSourceTextFacts.matches(
            #"(?m)^([ \t]*)return\s+out\s*;[ \t]*$"#, in: source
        )
        guard stage == .vertex || (!returns.isEmpty && returns.allSatisfy({ result in
            scopes.contains { $0.name == "mwxGenericFragment" && $0.contains(result.range) }
        })) else { return nil }

        var edits: [(range: NSRange, replacement: String)] = []
        if stage == .fragment,
           boundary.signalPassthroughSlot != nil
            || [.straightAlpha, .premultipliedAlpha].contains(boundary.outputRepresentation) {
            for result in returns {
                guard let scope = scopes.first(where: { $0.contains(result.range) }),
                      boundary.signalPassthroughSlot == nil || scope.uniforms != nil else { return nil }
                let expression = SceneAuthoredShaderMetalSource.ordinaryColorOutputExpression(
                    "out.mwxFragColor", boundary: boundary, uniforms: scope.uniforms ?? ""
                )
                let indent = SceneShaderSourceTextFacts.capture(result, 1, in: source) ?? ""
                edits.append((result.range,
                    "\(indent)out.mwxFragColor = \(expression);\n"
                        + "\(indent)return out;"))
            }
        }
        for call in calls where boundary.colorInputSlots.contains(call.slot) {
            guard let range = Range(call.range, in: source),
                  let scope = scopes.first(where: { $0.contains(call.range) }),
                  let uniforms = scope.uniforms else { return nil }
            edits.append((call.range,
                "mwxStraightColorInput(\(source[range]), \(uniforms).\(SceneShaderColorBoundary.uniformName), \(call.slot)u)"))
        }
        var transformed = source
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            guard let range = Range(edit.range, in: transformed) else { return nil }
            transformed.replaceSubrange(range, with: edit.replacement)
        }
        guard includeBoundaryHelpers else { return transformed }
        guard let namespace = SceneShaderSourceTextFacts.matches(
            #"\busing\s+namespace\s+metal\s*;"#, in: transformed
        ).first, let range = Range(namespace.range, in: transformed) else { return nil }
        transformed.insert(contentsOf: SceneAuthoredShaderMetalSource
            .ordinaryColorBoundaryHelpers(boundary), at: range.upperBound)
        return transformed
    }

    private struct OrdinaryFunctionScope {
        let name: String
        let parameters: NSRange
        let body: NSRange
        let uniforms: String?
        let entryStage: SceneShaderContract.StageKind?

        func contains(_ range: NSRange) -> Bool {
            body.location <= range.location && NSMaxRange(range) <= NSMaxRange(body)
        }
    }

    /// SPIRV-Cross omits an unused uniform entry argument. The prepared mask
    /// makes it used, so thread that same buffer through only the compiler
    /// functions that now need it. Existing context names remain authoritative.
    private static func ordinaryUniformContexts(
        _ source: String, boundary: SceneShaderColorBoundary
    ) -> String? {
        guard let scopes = ordinaryFunctionScopes(source),
              let samples = SceneGenericShaderStraightAlphaPreservingLowering
                .compilerTextureSampleCalls(in: source) else { return nil }
        var needed = Set<Int>()
        for sample in samples where boundary.colorInputSlots.contains(sample.slot) {
            guard let index = scopes.firstIndex(where: { $0.contains(sample.range) }) else { return nil }
            needed.insert(index)
        }
        if boundary.signalPassthroughSlot != nil {
            needed.formUnion(scopes.indices.filter { scopes[$0].entryStage == .fragment })
        }
        struct Call { let caller: Int; let target: Int; let arguments: NSRange }
        var calls: [Call] = []
        for target in scopes.indices {
            let pattern = #"\b"# + SceneShaderSourceTextFacts.escaped(scopes[target].name) + #"\s*\("#
            for match in SceneShaderSourceTextFacts.matches(pattern, in: source) {
                guard let caller = scopes.firstIndex(where: { $0.contains(match.range) }) else { continue }
                guard let range = Range(match.range, in: source),
                      let open = source[range].lastIndex(of: "("),
                      let close = ordinaryCallClose(source, opening: open) else { return nil }
                calls.append(.init(caller: caller, target: target,
                    arguments: NSRange(source.index(after: open)..<close, in: source)))
            }
        }
        var changed = true
        while changed {
            changed = false
            for call in calls where needed.contains(call.target) && scopes[call.target].uniforms == nil {
                if needed.insert(call.caller).inserted { changed = true }
            }
        }
        let missing = needed.filter { scopes[$0].uniforms == nil }
        guard !missing.isEmpty else { return source }
        let injected = "mwxColorUniforms"
        guard SceneShaderSourceTextFacts.matches(#"\b"# + injected + #"\b"#, in: source).isEmpty,
              Set(scopes.map(\.name)).count == scopes.count else { return nil }
        var edits: [(NSRange, String)] = []
        for index in missing {
            let scope = scopes[index]
            let isEntry = scope.entryStage != nil
            let entryName = scope.entryStage == .vertex ? "mwxGenericVertex" : "mwxGenericFragment"
            guard isEntry ? scope.name == entryName : calls.contains(where: { $0.target == index }),
                  let parameters = SceneShaderSourceTextFacts.substring(scope.parameters, in: source),
                  !isEntry || !parameters.contains("[[buffer(8)]]") else { return nil }
            let attribute = isEntry ? " [[buffer(8)]]" : ""
            let separator = parameters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : ", "
            edits.append((NSRange(location: scope.parameters.location, length: 0),
                "constant MWXUniforms& \(injected)\(attribute)\(separator)"))
        }
        for call in calls where missing.contains(call.target) {
            guard let arguments = SceneShaderSourceTextFacts.substring(call.arguments, in: source) else { return nil }
            let uniforms = scopes[call.caller].uniforms ?? injected
            let separator = arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : ", "
            edits.append((NSRange(location: call.arguments.location, length: 0), "\(uniforms)\(separator)"))
        }
        var result = source
        for (range, replacement) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            guard let swiftRange = Range(range, in: result) else { return nil }
            result.replaceSubrange(swiftRange, with: replacement)
        }
        return result
    }

    private static func ordinaryCallClose(_ source: String, opening: String.Index) -> String.Index? {
        var depth = 0
        var cursor = opening
        while cursor < source.endIndex {
            if source[cursor] == "(" { depth += 1 }
            if source[cursor] == ")" {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    /// Resolve the enclosing compiler signature for each adapted sample.
    private static func ordinaryFunctionScopes(_ source: String) -> [OrdinaryFunctionScope]? {
        let signatures = SceneShaderSourceTextFacts.matches(
            #"(?m)^[ \t]*(?:(?:fragment|vertex|inline|static)\s+|__attribute__\s*\(\(\s*always_inline\s*\)\)\s*)*[A-Za-z_]\w*(?:<[^{};\n]+>)?\s+([A-Za-z_]\w*)\s*\(([^{};]*)\)\s*\{"#,
            in: source
        )
        var result: [OrdinaryFunctionScope] = []
        for signature in signatures {
            guard let range = Range(signature.range, in: source),
                  let name = SceneShaderSourceTextFacts.capture(signature, 1, in: source),
                  let parameters = SceneShaderSourceTextFacts.capture(signature, 2, in: source),
                  let open = source[..<range.upperBound].lastIndex(of: "{") else { return nil }
            let declarations = SceneShaderSourceTextFacts.matches(
                #"\bconstant\s+MWXUniforms\s*&\s*([A-Za-z_]\w*)\b"#, in: parameters
            )
            guard declarations.count <= 1 else { return nil }
            let uniforms = declarations.first.flatMap {
                SceneShaderSourceTextFacts.capture($0, 1, in: parameters)
            }
            var depth = 0
            var cursor = open
            var close: String.Index?
            while cursor < source.endIndex {
                if source[cursor] == "{" { depth += 1 }
                if source[cursor] == "}" {
                    depth -= 1
                    if depth == 0 { close = cursor; break }
                    if depth < 0 { return nil }
                }
                cursor = source.index(after: cursor)
            }
            guard let close else { return nil }
            let declaration = SceneShaderSourceTextFacts.substring(signature.range, in: source)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let entryStage: SceneShaderContract.StageKind? = declaration.hasPrefix("vertex ")
                ? .vertex : declaration.hasPrefix("fragment ") ? .fragment : nil
            result.append(.init(name: name, parameters: signature.range(at: 2),
                body: NSRange(source.index(after: open)..<close, in: source), uniforms: uniforms,
                entryStage: entryStage))
        }
        return result
    }

    static func lower(_ source: String, colorSlots: Set<Int>) -> Lowered? {
        guard colorSlots.allSatisfy({ (0 ..< 8).contains($0) }),
              !source.contains(unpremultiply),
              !source.contains(premultiply),
              SceneShaderSourceTextFacts.matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              !SceneShaderSourceTextFacts.matches(#"\bout\.mwxFragColor\b"#, in: source).isEmpty,
              let calls = SceneGenericShaderStraightAlphaPreservingLowering
                .compilerTextureSampleCalls(in: source) else { return nil }
        let returns = SceneShaderSourceTextFacts.matches(#"(?m)^([ \t]*)return\s+out\s*;[ \t]*$"#, in: source)
        guard !returns.isEmpty else { return nil }

        var edits: [(range: NSRange, replacement: String)] = []
        for match in returns {
            let indent = SceneShaderSourceTextFacts.capture(match, 1, in: source) ?? ""
            edits.append((
                match.range,
                "\(indent)out.mwxFragColor = \(premultiply)(out.mwxFragColor);\n"
                    + "\(indent)return out;"
            ))
        }
        var applied = Set<Int>()
        for call in calls where colorSlots.contains(call.slot) {
            guard let range = Range(call.range, in: source) else { return nil }
            edits.append((call.range, "\(unpremultiply)(\(source[range]))"))
            applied.insert(call.slot)
        }
        // Every edit range is disjoint; apply from the end so earlier
        // UTF-16 offsets stay valid in the transformed string.
        var transformed = source
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            guard let range = Range(edit.range, in: transformed) else { return nil }
            transformed.replaceSubrange(range, with: edit.replacement)
        }
        guard let withHelpers = SceneGenericShaderStraightAlphaPreservingLowering
            .insertingBoundaryHelpers(into: transformed) else { return nil }
        return Lowered(msl: withHelpers, appliedSlots: applied.sorted())
    }
}
