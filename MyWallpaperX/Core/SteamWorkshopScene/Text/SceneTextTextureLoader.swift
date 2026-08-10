import CoreText
import Foundation
import Metal

struct SceneTextTextureLoadResult {
    let textures: [Int: MTLTexture]
    let messages: [String]
}

enum SceneTextTextureLoader {
    struct DynamicTexture {
        let texture: MTLTexture
        let renderSizeWH: [Float]
    }

    private struct RenderedTexture {
        let texture: MTLTexture
        let font: SceneTextFontResolver.Resolution
        let renderSizeWH: [Float]
    }

    private static let maxDimension = 2048
    private static let maxAutoSizeDimension: Float = 16_384

    static func load(
        descriptor: SceneRenderDescriptor,
        cacheDirectory: URL,
        device: MTLDevice,
        effectSummary: (SceneRenderDescriptor.Layer) -> String? = {
            SceneEffectRuntimePlanner.runtimeSummary(for: $0)
        },
        legacyEffectRuntimeExcludedLayerIDs: Set<Int> = []
    ) -> SceneTextTextureLoadResult {
        let visibleIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let candidates = descriptor.layers.filter {
            $0.contentKind == "text" && visibleIDs.contains($0.id)
        }
        var textures: [Int: MTLTexture] = [:]
        var messages: [String] = []
        for layer in candidates {
            guard let rendered = makeRenderedTexture(
                for: layer,
                cacheDirectory: cacheDirectory,
                device: device
            ) else {
                messages.append("text layer \(layer.id) \"\(layer.name ?? "(unnamed)")\": render failed")
                continue
            }
            textures[layer.id] = rendered.texture
            var message = "text layer \(layer.id) \"\(layer.name ?? "(unnamed)")\": OK \(rendered.texture.width)×\(rendered.texture.height); \(rendered.font.summary)"
            if let summary = effectSummary(layer) {
                message += "; \(summary)"
            }
            if !legacyEffectRuntimeExcludedLayerIDs.contains(layer.id),
               let inlineSummary = SceneInlineEffectRuntime.summary(
                   for: layer,
                   hasWaterMask: false
               ) {
                message += "; \(inlineSummary)"
            }
            messages.append(message)
        }
        messages.append("text loaded: \(textures.count) / \(candidates.count)")
        return SceneTextTextureLoadResult(textures: textures, messages: messages)
    }

    static func makeDynamicTexture(
        for layer: SceneRenderDescriptor.Layer,
        content: String,
        pointSize: Float,
        colorRGB: [Float],
        maxWidth: Float? = nil,
        cacheDirectory: URL,
        device: MTLDevice
    ) -> DynamicTexture? {
        guard let rendered = makeRenderedTexture(
            for: layer,
            content: content,
            pointSize: pointSize,
            colorRGB: colorRGB,
            maxWidth: maxWidth,
            cacheDirectory: cacheDirectory,
            device: device
        ) else {
            return nil
        }
        return DynamicTexture(
            texture: rendered.texture,
            renderSizeWH: rendered.renderSizeWH
        )
    }

    private static func makeRenderedTexture(
        for layer: SceneRenderDescriptor.Layer,
        content: String? = nil,
        pointSize: Float? = nil,
        colorRGB: [Float]? = nil,
        maxWidth: Float? = nil,
        cacheDirectory: URL,
        device: MTLDevice
    ) -> RenderedTexture? {
        guard let text = content ?? layer.text, let authoredStyle = layer.textStyle else { return nil }
        let style = authoredStyle.replacing(
            pointSize: pointSize,
            colorRGB: colorRGB,
            maxWidth: maxWidth
        )
        let baseRenderSize = layer.renderSizeWH
        let sourceFont = SceneTextFontResolver.resolve(
            path: style.fontPath,
            size: CGFloat(SceneTextGeometry.pointSizeInPixels(style.pointSize)),
            cacheDirectory: cacheDirectory
        )
        let renderSize = content == nil
            ? baseRenderSize
            : autoSizedRenderSize(
                text: text,
                style: style,
                font: sourceFont.font,
                baseRenderSize: baseRenderSize
            )
        guard let layout = SceneTextGeometry.rasterLayout(
            renderSize: renderSize,
            padding: style.padding,
            maxDimension: maxDimension
        ) else { return nil }
        let font = layout.scale == 1
            ? sourceFont
            : SceneTextFontResolver.resolve(
                path: style.fontPath,
                size: CGFloat(SceneTextGeometry.pointSizeInPixels(style.pointSize) * layout.scale),
                cacheDirectory: cacheDirectory
            )
        let width = layout.width
        let height = layout.height
        let rowBytes = width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * height)

        let drewText = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: rowBytes,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else {
                return false
            }
            draw(
                text: text,
                style: style,
                font: font.font,
                layout: layout,
                width: width,
                height: height,
                context: context
            )
            return true
        }
        guard drewText else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "SceneText \(layer.id)"
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: rowBytes
        )
        return RenderedTexture(
            texture: texture,
            font: font,
            renderSizeWH: renderSize ?? [Float(width), Float(height)]
        )
    }

    private static func autoSizedRenderSize(
        text: String,
        style: SceneTextDescriptor,
        font: CTFont,
        baseRenderSize: [Float]?
    ) -> [Float]? {
        guard let baseRenderSize, baseRenderSize.count >= 2,
              !style.limitWidth else {
            return baseRenderSize
        }
        let attributes = [kCTFontAttributeName: font] as CFDictionary
        guard let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault,
            text as CFString,
            attributes
        ) else {
            return baseRenderSize
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(
                width: CGFloat(maxAutoSizeDimension),
                height: CGFloat(maxAutoSizeDimension)
            ),
            nil
        )
        let padding = max(0, style.padding) * 2
        return [
            min(maxAutoSizeDimension, max(baseRenderSize[0], Float(ceil(measured.width)) + padding)),
            min(maxAutoSizeDimension, max(baseRenderSize[1], Float(ceil(measured.height)) + padding)),
        ]
    }

    private static func draw(
        text: String,
        style: SceneTextDescriptor,
        font: CTFont,
        layout: SceneTextGeometry.RasterLayout,
        width: Int,
        height: Int,
        context: CGContext
    ) {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(bounds)
        if style.opaqueBackground {
            context.setFillColor(color(style.backgroundColorRGB, brightness: style.backgroundBrightness))
            context.fill(bounds)
        }

        let padding = CGFloat(layout.padding)
        let contentWidth = CGFloat(layout.contentWidth)
        let contentHeight = CGFloat(layout.contentHeight)
        var alignment = textAlignment(style.horizontalAlignment)
        var lineBreak = CTLineBreakMode.byWordWrapping
        let paragraph = withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &lineBreak) { lineBreakPointer in
                var settings = [
                    CTParagraphStyleSetting(
                        spec: .alignment,
                        valueSize: MemoryLayout<CTTextAlignment>.size,
                        value: alignmentPointer
                    ),
                    CTParagraphStyleSetting(
                        spec: .lineBreakMode,
                        valueSize: MemoryLayout<CTLineBreakMode>.size,
                        value: lineBreakPointer
                    )
                ]
                return CTParagraphStyleCreate(&settings, settings.count)
            }
        }
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color(style.colorRGB, brightness: style.brightness),
            kCTParagraphStyleAttributeName: paragraph
        ]
        // 作者的 Limit width 决定换行宽度，Limit rows / Overflow ellipsis 决定行数与省略号；
        // 三个开关都关闭时 wrapWidth 就是内容宽、文本原样，排版与之前完全一致。
        let wrapWidth = SceneTextRowLimit.wrapWidth(
            contentWidth: contentWidth,
            style: style,
            scale: layout.scale
        )
        let limited = SceneTextRowLimit.limitedText(
            text,
            style: style,
            attributes: attributes as CFDictionary,
            wrapWidth: wrapWidth
        )
        guard let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault,
            limited as CFString,
            attributes as CFDictionary
        ) else { return }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let constraint = CGSize(width: wrapWidth, height: contentHeight)
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            constraint,
            nil
        )
        let textHeight = min(contentHeight, ceil(measured.height))
        let y = verticalOrigin(
            alignment: style.verticalAlignment,
            padding: padding,
            contentHeight: contentHeight,
            textHeight: textHeight
        )
        // 换行宽度被 Max width 压窄时，窄框按水平对齐落在内容框里，
        // 否则 center/right 的 layer 会整块左移。
        let x = padding + horizontalOrigin(
            alignment: style.horizontalAlignment,
            contentWidth: contentWidth,
            textWidth: wrapWidth
        )
        let path = CGPath(rect: CGRect(x: x, y: y, width: wrapWidth, height: textHeight), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
    }

    private static func color(_ rgb: [Float], brightness: Float) -> CGColor {
        let components = (0..<3).map { index in
            CGFloat(min(max((rgb.indices.contains(index) ? rgb[index] : 1) * brightness, 0), 1))
        }
        return CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: components + [1]
        )!
    }

    private static func textAlignment(_ value: String) -> CTTextAlignment {
        switch value.localizedLowercase {
        case "left": .left
        case "right": .right
        default: .center
        }
    }

    private static func verticalOrigin(
        alignment: String,
        padding: CGFloat,
        contentHeight: CGFloat,
        textHeight: CGFloat
    ) -> CGFloat {
        switch alignment.localizedLowercase {
        case "top": padding + contentHeight - textHeight
        case "bottom": padding
        default: padding + (contentHeight - textHeight) * 0.5
        }
    }

    private static func horizontalOrigin(
        alignment: String,
        contentWidth: CGFloat,
        textWidth: CGFloat
    ) -> CGFloat {
        switch alignment.localizedLowercase {
        case "left": 0
        case "right": contentWidth - textWidth
        default: (contentWidth - textWidth) * 0.5
        }
    }
}
