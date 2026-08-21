import Foundation

nonisolated enum SceneResolvedMaterialAttachmentKind: Equatable {
    case color
    case scalarRedUnorm
    case redGreenUnorm
    case scalarRedFloat16
    case redGreenFloat16
    /// Four normalized channels whose authored values are graph state, not a
    /// compositor color. This is intentionally distinct from `.color` even
    /// though both use an RGBA8 Metal attachment.
    case preservedRGBAUnorm
}
