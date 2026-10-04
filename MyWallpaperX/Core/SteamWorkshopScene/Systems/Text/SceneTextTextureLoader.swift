import CoreText
import Foundation
import Metal

struct SceneTextTextureLoadResult {
    let textures: [Int: MTLTexture]
    let renderSizes: [Int: [Float]]
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
        recordsDiagnostics: Bool = true,
        effectSummary: (SceneRenderDescriptor.Layer) -> String? = { _ in nil }
    ) -> SceneTextTextureLoadResult {
        // Authored hidden text can be shown by a later script/property event.
        // Prepare its source once; frame visibility owns actual composition.
        let candidates = descriptor.layers.filter {
            $0.contentKind == "text"
        }
        var textures: [Int: MTLTexture] = [:]
        var renderSizes: [Int: [Float]] = [:]
        var messages: [String] = []
        for layer in candidates {
            guard let rendered = makeRenderedTexture(
                for: layer,
                cacheDirectory: cacheDirectory,
                device: device
            ) else {
                if recordsDiagnostics {
                    messages.append(
                        "text layer \(layer.id) \"\(layer.name ?? "(unnamed)")\":"
                            + " render failed"
                    )
                }
                continue
            }
            textures[layer.id] = rendered.texture
            renderSizes[layer.id] = rendered.renderSizeWH
            if recordsDiagnostics {
                var message = "text layer \(layer.id)"
                    + " \"\(layer.name ?? "(unnamed)")\": OK"
                    + " \(rendered.texture.width)×\(rendered.texture.height);"
                    + " \(rendered.font.summary)"
                if let summary = effectSummary(layer) {
                    message += "; \(summary)"
                }
                messages.append(message)
            }
        }
        if recordsDiagnostics {
            messages.append("text loaded: \(textures.count) / \(candidates.count)")
        }
        return SceneTextTextureLoadResult(
            textures: textures, renderSizes: renderSizes, messages: messages
        )
    }

    static func makeDynamicTexture(
        for layer: SceneRenderDescriptor.Layer,
        content: String,
        fontPath: String? = nil,
        pointSize: Float,
        colorRGB: [Float],
        maxWidth: Float? = nil,
        cacheDirectory: URL,
        device: MTLDevice
    ) -> DynamicTexture? {
        guard let rendered = makeRenderedTexture(
            for: layer,
            content: content,
            fontPath: fontPath,
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
        fontPath: String? = nil,
        pointSize: Float? = nil,
        colorRGB: [Float]? = nil,
        maxWidth: Float? = nil,
        cacheDirectory: URL,
        device: MTLDevice
    ) -> RenderedTexture? {
        guard let text = content ?? layer.text, let authoredStyle = layer.textStyle else { return nil }
        let style = authoredStyle.replacing(
            fontPath: fontPath,
            pointSize: pointSize,
            colorRGB: colorRGB,
            maxWidth: maxWidth
        )
        let sourceFont = SceneTextFontResolver.resolve(
            path: style.fontPath,
            size: CGFloat(SceneTextGeometry.pointSizeInPixels(style.pointSize)),
            cacheDirectory: cacheDirectory
        )
        // Initial and updated content use the same font measurement contract.
        // Saved editor geometry is not an implicit wrapping/clipping limit.
        guard let prepared = prepareTextLayout(
                text: text,
                style: style,
                font: sourceFont.font
            ) else { return nil }
        let inset = style.decorationInset
        let renderSize = prepared.size.map { $0 + inset * 2 }
        guard let layout = SceneTextGeometry.rasterLayout(
            renderSize: renderSize,
            padding: style.padding + inset,
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
                text: prepared.text,
                wrapWidth: CGFloat(prepared.wrapWidth * layout.scale),
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
        guard let texture = device.makeSceneTexture(descriptor: descriptor) else { return nil }
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
            renderSizeWH: renderSize
        )
    }

    private static func prepareTextLayout(
        text: String,
        style: SceneTextDescriptor,
        font: CTFont
    ) -> (text: String, size: [Float], wrapWidth: Float)? {
        let attributes = [kCTFontAttributeName: font] as CFDictionary
        let wrapWidth = Float(SceneTextRowLimit.wrapWidth(
            contentWidth: CGFloat(maxAutoSizeDimension), style: style, scale: 1
        ))
        let content = SceneTextRowLimit.limitedText(
            text, style: style, attributes: attributes, wrapWidth: CGFloat(wrapWidth)
        )
        guard let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault,
            content as CFString,
            attributes
        ) else {
            return nil
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(
                width: CGFloat(wrapWidth),
                height: CGFloat(maxAutoSizeDimension)
            ),
            nil
        )
        // Saved editor size is an observation, not a text layout constraint.
        // Both initial and dynamic content derive their extent from the font,
        // width/row limits and full padding on each edge.
        let padding = max(0, style.padding) * 2
        let size = [
            max(1, Float(ceil(measured.width)) + padding),
            max(1, Float(ceil(measured.height)) + padding),
        ]
        // Padding is authored input. Reject an unrepresentable extent before
        // rasterLayout converts scaled dimensions to integer texture sizes.
        guard size.allSatisfy(\.isFinite) else { return nil }
        return (content, size, wrapWidth)
    }

    private static func draw(
        text: String,
        wrapWidth: CGFloat,
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
            let border = CGFloat(style.decorationInset * layout.scale)
            context.fill(bounds.insetBy(dx: border, dy: border))
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
        // Consume the prepared text and wrapping constraint. Rounded texture
        // dimensions must not trigger a second row-limit or wrapping decision.
        guard let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault,
            text as CFString,
            attributes as CFDictionary
        ) else { return }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        // Padding narrows the authored content box, but it must not become a
        // CoreText line-height limit. A font line may be taller than that box
        // while its glyph ink still fits inside the outer raster geometry.
        // Measuring against contentHeight makes CTFramesetter reject the whole
        // line and produces a fully transparent texture for valid HUD text.
        let constraint = CGSize(
            width: wrapWidth,
            height: .greatestFiniteMagnitude
        )
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            constraint,
            nil
        )
        let textHeight = max(1, ceil(measured.height))
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
        context.saveGState()
        let scale = CGFloat(layout.scale)
        let shadow = style.dropShadow
        if let shadow {
            context.setShadow(
                offset: CGSize(
                    width: CGFloat(shadow.offset[0]) * scale,
                    height: -CGFloat(shadow.offset[1]) * scale
                ),
                blur: max(4, CGFloat(shadow.size)) * scale,
                color: color(shadow.colorRGB, brightness: 1, alpha: CGFloat(shadow.opacity))
            )
            // The group contains glyphs and their outline, but not the opaque
            // background. Apply opacity and shadow once to the combined caster.
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        if let outline = style.outline,
           let outlined = CFAttributedStringCreateMutableCopy(kCFAllocatorDefault, 0, attributed) {
            // CoreText stroke width is a percentage of the font size and is
            // centered on the glyph edge. Authored thickness is the outward
            // radius in scene pixels, independent of point size. Restore the
            // original fill afterward so the outline cannot eat the glyph.
            let radius = min(
                CGFloat(outline.thickness) * CGFloat(layout.scale),
                CGFloat(max(width, height)) * 2
            )
            context.setLineJoin(.miter)
            context.setMiterLimit(CGFloat(SceneTextDescriptor.Outline.miterLimit))
            let strokePercent = radius * 200 / CTFontGetSize(font)
            let range = CFRange(location: 0, length: CFAttributedStringGetLength(outlined))
            CFAttributedStringSetAttribute(
                outlined, range, kCTStrokeWidthAttributeName, strokePercent as CFNumber
            )
            CFAttributedStringSetAttribute(
                outlined, range, kCTStrokeColorAttributeName, color(outline.colorRGB, brightness: 1)
            )
            let outlineFramesetter = CTFramesetterCreateWithAttributedString(outlined)
            let outlineFrame = CTFramesetterCreateFrame(
                outlineFramesetter, CFRange(location: 0, length: 0), path, nil
            )
            CTFrameDraw(outlineFrame, context)
        }
        CTFrameDraw(frame, context)
        if shadow != nil { context.endTransparencyLayer() }
        context.restoreGState()
    }

    private static func color(_ rgb: [Float], brightness: Float, alpha: CGFloat = 1) -> CGColor {
        let components = (0..<3).map { index in
            CGFloat(min(max((rgb.indices.contains(index) ? rgb[index] : 1) * brightness, 0), 1))
        }
        return CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: components + [alpha]
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
