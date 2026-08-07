import Foundation

extension SceneResolvedMaterialVariantCache {
    enum LaunchEnvelopeFailure: Error {
        enum Kind: String {
            case capacity
            case shaderPreparation = "shader-preparation"
            case frontend
            case samplerSchema = "sampler-schema"
            case uniformSchema = "uniform-schema"
            case texturePurpose = "texture-purpose"
            case textureBinding = "texture-binding"
            case colorContract = "color-contract"
            case invariant
        }

        case capacity
        case material(Failure)

        var kind: Kind {
            switch self {
            case .capacity: .capacity
            case let .material(failure): switch failure.code {
                case .shaderPreparationFailed: .shaderPreparation
                case .shaderFrontendFailed: .frontend
                case .activeSamplerSchemaInvalid: .samplerSchema
                case .uniformBindingInvalid: .uniformSchema
                case .texturePurposeUnproven: .texturePurpose
                case .textureBindingInvalid, .textureReferenceInvalid:
                    .textureBinding
                case .colorContractUnproven: .colorContract
                default: .invariant
                }
            }
        }
    }
}
