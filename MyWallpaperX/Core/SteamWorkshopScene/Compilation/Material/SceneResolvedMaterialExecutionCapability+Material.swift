import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    final class MaterialCapability {
        let key: MaterialKey
        let template: Template
        let variants: SceneResolvedMaterialVariantCache
        let attachmentStorage: SceneResolvedMaterialAttachmentKind
        let targetFormat: SceneGraphRenderTargetPlan.TextureFormat

        init(
            key: MaterialKey,
            template: Template,
            variants: SceneResolvedMaterialVariantCache,
            attachmentStorage: SceneResolvedMaterialAttachmentKind,
            targetFormat: SceneGraphRenderTargetPlan.TextureFormat
        ) {
            self.key = key
            self.template = template
            self.variants = variants
            self.attachmentStorage = attachmentStorage
            self.targetFormat = targetFormat
        }
    }
}
