import Foundation

/// Launch-immutable projection of authored base-material provider slots. The
/// binding selects one typed resource in the existing frame registry; it never
/// publishes that resource as a layer source or owns compositor output.
nonisolated struct SceneBaseMaterialProviderBindingProgram {
    struct BaseMaterialBinding: Hashable {
        enum Source: String, Hashable {
            case layerInstance = "layer-instance"
            case materialPass = "material-pass"
        }

        enum Provider: Hashable {
            case current
            case previous
            case userProperty(SceneUserPropertyTextureIdentity)

            var authoredName: String {
                switch self {
                case .current:
                    SceneBaseMaterialProviderBindingProgram.currentIdentity
                case .previous:
                    SceneBaseMaterialProviderBindingProgram.previousIdentity
                case let .userProperty(identity):
                    identity.propertyKey
                }
            }

            var authoredKind: SceneEffectTextureInput.Kind {
                switch self {
                case .current, .previous: .system
                case .userProperty: .property
                }
            }

            var frameIdentity: SceneFrameTextureIdentity {
                switch self {
                case .current:
                    .system(.init(
                        name: authoredName,
                        purpose: .premultipliedColor
                    ))
                case .previous:
                    .system(.init(
                        name: authoredName,
                        purpose: .premultipliedColor
                    ))
                case let .userProperty(identity):
                    .materialUserProperty(identity)
                }
            }

            var diagnosticPrefix: String {
                switch self {
                case .current: "base-material-current"
                case .previous: "base-material-previous"
                case .userProperty: "base-material-user-property"
                }
            }

            var reportToken: String {
                switch self {
                case .current: "current"
                case .previous: "previous"
                case let .userProperty(identity):
                    "user-property:\(identity.reportToken)"
                }
            }

            var systemProviderIdentity: SceneSystemProviderTextureIdentity? {
                guard case let .system(identity) = frameIdentity else {
                    return nil
                }
                return identity
            }

            var userPropertyIdentity: SceneUserPropertyTextureIdentity? {
                guard case let .userProperty(identity) = self else {
                    return nil
                }
                return identity
            }

            var isSystemProvider: Bool {
                systemProviderIdentity != nil
            }

            func accepts(_ candidate: SceneTextureCandidate) -> Bool {
                switch self {
                case .current:
                    return candidate.identity == .provider(.mediaThumbnailCurrent)
                case .previous:
                    return candidate.identity == .provider(.mediaThumbnailPrevious)
                case let .userProperty(identity):
                    guard candidate.purpose == identity.purpose else {
                        return false
                    }
                    if case .file = candidate.identity { return true }
                    return false
                }
            }
        }

        let layerID: Int
        let source: Source
        let slotIndex: Int
        let provider: Provider

        init(
            layerID: Int,
            source: Source,
            slotIndex: Int,
            provider: Provider = .current
        ) {
            self.layerID = layerID
            self.source = source
            self.slotIndex = slotIndex
            self.provider = provider
        }

    }

    static let currentIdentity = "$mediaThumbnail"
    static let previousIdentity = "$mediaPreviousThumbnail"

    let baseMaterialBindings: [Int: BaseMaterialBinding]
    let rejectedBaseMaterialReasons: [Int: String]

    nonisolated init(
        baseMaterialBindings: [Int: BaseMaterialBinding],
        rejectedBaseMaterialReasons: [Int: String] = [:]
    ) {
        self.baseMaterialBindings = baseMaterialBindings
        self.rejectedBaseMaterialReasons = rejectedBaseMaterialReasons
    }

    static let empty = SceneBaseMaterialProviderBindingProgram(
        baseMaterialBindings: [:]
    )

    var currentLayerIDs: Set<Int> {
        layerIDs(for: .current)
    }

    var previousLayerIDs: Set<Int> {
        layerIDs(for: .previous)
    }

    var hasConsumers: Bool {
        !baseMaterialBindings.isEmpty
    }

    var systemProviderDemands: Set<SceneSystemProviderTextureIdentity> {
        Set(baseMaterialBindings.values.compactMap {
            $0.provider.systemProviderIdentity
        })
    }

    var userPropertyDemands: Set<SceneUserPropertyTextureIdentity> {
        Set(baseMaterialBindings.values.compactMap {
            $0.provider.userPropertyIdentity
        })
    }

    func reportLines() -> [String] {
        let previousRejectedCount = rejectedBaseMaterialReasons.values.filter {
            $0.hasPrefix("base-material-previous-")
        }.count
        let propertyRejectedCount = rejectedBaseMaterialReasons.values.filter {
            $0.hasPrefix("base-material-user-property-")
        }.count
        let currentRejectedCount = rejectedBaseMaterialReasons.values.filter {
            $0.hasPrefix("base-material-current-")
        }.count
        let otherRejectedCount = rejectedBaseMaterialReasons.count
            - previousRejectedCount - propertyRejectedCount
            - currentRejectedCount
        let propertyLayerIDs = layerIDs(matching: {
            if case .userProperty = $0 { return true }
            return false
        })
        var lines = [
            "mediaThumbnailCurrentBindingCount: \(currentLayerIDs.count)",
            "mediaThumbnailCurrentBindingLayerIDs: "
                + currentLayerIDs.sorted().map(String.init).joined(separator: ","),
            "mediaThumbnailCurrentBaseMaterialBindingCount: "
                + "\(currentLayerIDs.count)",
            "mediaThumbnailPreviousBindingCount: \(previousLayerIDs.count)",
            "mediaThumbnailPreviousBindingLayerIDs: "
                + previousLayerIDs.sorted().map(String.init).joined(separator: ","),
            "mediaThumbnailPreviousBaseMaterialBindingCount: "
                + "\(previousLayerIDs.count)",
            "mediaThumbnailCurrentBaseMaterialRejectedCount: "
                + "\(currentRejectedCount)",
            "mediaThumbnailPreviousBaseMaterialRejectedCount: "
                + "\(previousRejectedCount)",
            "baseMaterialUserPropertyBindingCount: \(propertyLayerIDs.count)",
            "baseMaterialUserPropertyBindingLayerIDs: "
                + propertyLayerIDs.sorted().map(String.init).joined(separator: ","),
            "baseMaterialUserPropertyRejectedCount: \(propertyRejectedCount)",
            "baseMaterialProviderOtherRejectedCount: \(otherRejectedCount)",
            "mediaThumbnailBaseMaterialRejectedCount: "
                + "\(currentRejectedCount + previousRejectedCount)",
            "baseMaterialProviderRejectedCount: "
                + "\(rejectedBaseMaterialReasons.count)",
        ]
        lines.append(contentsOf: baseMaterialBindings.values.sorted(by: {
            $0.layerID < $1.layerID
        }).compactMap { binding in
            guard let identity = binding.provider.userPropertyIdentity else {
                return nil
            }
            return "baseMaterialUserPropertyBinding: layer=\(binding.layerID) "
                + "identity=\(identity.reportToken) source=\(binding.source.rawValue) "
                + "slot=\(binding.slotIndex)"
        })
        return lines
    }

    private func layerIDs(for provider: BaseMaterialBinding.Provider) -> Set<Int> {
        layerIDs(matching: { $0 == provider })
    }

    private func layerIDs(
        matching predicate: (BaseMaterialBinding.Provider) -> Bool
    ) -> Set<Int> {
        Set(baseMaterialBindings.compactMap { layerID, binding in
            predicate(binding.provider) ? layerID : nil
        })
    }
}
