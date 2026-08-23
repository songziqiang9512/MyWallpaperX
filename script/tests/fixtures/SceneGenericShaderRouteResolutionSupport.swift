import Foundation

struct SceneGenericShaderRouteFixtureOutput: Codable {
    let status: String
    let code: String?
    let requestKey: String
    let permitsBoundedFrontend: Bool?
    let backend: String?
    let uniformBufferIndex: Int?
    let uniformNames: [String]?
    let textureSlots: [Int]?
    let colorTransfer: String?
    let fragmentOutputChannelUse: String?
    let routeProfile: String?
    let routeState: String?
    let fallbackOwner: String?

    static func unavailable(
        status: String,
        code: String,
        requestKey: String,
        permitsBoundedFrontend: Bool?,
        decision: SceneGenericShaderRouteDecision
    ) -> Self {
        .init(
            status: status,
            code: code,
            requestKey: requestKey,
            permitsBoundedFrontend: permitsBoundedFrontend,
            backend: nil,
            uniformBufferIndex: nil,
            uniformNames: nil,
            textureSlots: nil,
            colorTransfer: nil,
            fragmentOutputChannelUse: nil,
            routeProfile: decision.profile,
            routeState: decision.state,
            fallbackOwner: decision.fallbackOwner
        )
    }
}
