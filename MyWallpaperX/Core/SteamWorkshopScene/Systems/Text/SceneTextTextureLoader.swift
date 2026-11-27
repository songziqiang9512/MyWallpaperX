import CoreText
import Foundation
import Metal

struct SceneTextTextureLoadResult {
    let rasters: [Int: SceneTextTextureLoader.RasterizedTexture]
    let messages: [String]
}

enum SceneTextTextureLoader {
    struct RasterizedTexture {
        let texture: MTLTexture
        let renderSizeWH: [Float]
        let centerOffsetY: Float
        let rasterOffsetY: Float
        let sourceFont: SceneTextFontResolver.Resolution
    }

    private struct RenderedTexture {
        let raster: RasterizedTexture
        let font: SceneTextFontResolver.Resolution
        let lineBounds: SceneTextRowLimit.LineBounds
    }

    private struct PrimaryLineBox {
        let ascent: CGFloat
        let stride: CGFloat
        let finalDescent: CGFloat

        func height(rows: Int) -> CGFloat {
            ascent + CGFloat(rows - 1) * stride + finalDescent
        }
    }

    private static let maxDimension = 2048
    private static let maxAutoSizeDimension: Float = 16_384

    static func load(
        descriptor: SceneRenderDescriptor,
        resourceView: SceneResourceView?,
        device: MTLDevice,
        recordsDiagnostics: Bool = true,
        checkCancellation: (() throws -> Void)? = nil,
        effectSummary: (SceneRenderDescriptor.Layer) -> String? = { _ in nil }
    ) -> SceneTextTextureLoadResult {
        // Authored hidden text can be shown by a later script/property event.
        // Prepare its source once; frame visibility owns actual composition.
        let candidates = descriptor.layers.filter {
            $0.contentKind == "text"
        }
        var rasters: [Int: RasterizedTexture] = [:]
        var messages: [String] = []
        for layer in candidates {
            let preparedFont = rasters.values.first {
                $0.sourceFont.requestedPath == layer.textStyle?.fontPath
            }?.sourceFont
            let rendered: RenderedTexture?
            do {
                rendered = try makeRenderedTexture(for: layer, resourceView: resourceView,
                    preparedFont: preparedFont, device: device, checkCancellation: checkCancellation)
            } catch {
                if recordsDiagnostics {
                    messages.append("text layer \(layer.id): resource read failed: \(error)")
                }
                continue
            }
            guard let rendered else {
                if recordsDiagnostics {
                    messages.append(
                        "text layer \(layer.id) \"\(layer.name ?? "(unnamed)")\":"
                            + " render failed"
                    )
                }
                continue
            }
            rasters[layer.id] = rendered.raster
            if recordsDiagnostics {
                var message = "text layer \(layer.id)"
                    + " \"\(layer.name ?? "(unnamed)")\": OK"
                    + " \(rendered.raster.texture.width)×\(rendered.raster.texture.height);"
                    + " \(rendered.font.summary)"
                if rendered.lineBounds == .typographic {
                    message += "; layout=nativeTypographicFallback:unusableGlyphBounds"
                }
                if let summary = effectSummary(layer) {
                    message += "; \(summary)"
                }
                messages.append(message)
            }
        }
        if recordsDiagnostics {
            messages.append("text loaded: \(rasters.count) / \(candidates.count)")
        }
        return SceneTextTextureLoadResult(
            rasters: rasters, messages: messages
        )
    }

    static func makeDynamicTexture(
        for layer: SceneRenderDescriptor.Layer,
        content: String,
        fontPath: String? = nil,
        pointSize: Float,
        colorRGB: [Float],
        maxWidth: Float? = nil,
        resourceView: SceneResourceView?,
        preparedFont: SceneTextFontResolver.Resolution? = nil,
        device: MTLDevice,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> RasterizedTexture? {
        guard let rendered = try makeRenderedTexture(
            for: layer,
            content: content,
            fontPath: fontPath,
            pointSize: pointSize,
            colorRGB: colorRGB,
            maxWidth: maxWidth,
            resourceView: resourceView,
            preparedFont: preparedFont,
            device: device,
            checkCancellation: checkCancellation
        ) else {
            return nil
        }
        return rendered.raster
    }

    private static func makeRenderedTexture(
        for layer: SceneRenderDescriptor.Layer,
        content: String? = nil,
        fontPath: String? = nil,
        pointSize: Float? = nil,
        colorRGB: [Float]? = nil,
        maxWidth: Float? = nil,
        resourceView: SceneResourceView?,
        preparedFont: SceneTextFontResolver.Resolution? = nil,
        device: MTLDevice,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> RenderedTexture? {
        try checkCancellation?()
        guard let text = content ?? layer.text, let authoredStyle = layer.textStyle else { return nil }
        let style = authoredStyle.replacing(
            fontPath: fontPath,
            pointSize: pointSize,
            colorRGB: colorRGB,
            maxWidth: maxWidth
        )
        let sourceFont = try SceneTextFontResolver.resolve(
            path: style.fontPath,
            size: CGFloat(SceneTextGeometry.pointSizeInPixels(style.pointSize)),
            resourceView: resourceView,
            reusing: preparedFont,
            checkCancellation: checkCancellation
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
            ? sourceFont.font
            : CTFontCreateCopyWithAttributes(
                sourceFont.font, CTFontGetSize(sourceFont.font) * CGFloat(layout.scale), nil, nil
            )
        guard let positioned = positionText(
            prepared.text, wrapWidth: CGFloat(prepared.wrapWidth * layout.scale),
            lineBounds: prepared.lineBounds, primaryLineBox: prepared.primaryLineBox,
            style: style, font: font, layout: layout
        ) else { return nil }
        // Rebased fallback ink can extend outside the nominal content box.
        // Keep the existing decoration margin around that actual ink.
        let decorationOutset = positioned.origins == nil ? 0 : CGFloat(inset * layout.scale)
        let expansion = verticalInkExpansion(positioned.frame, origins: positioned.origins,
                                             height: layout.height, decorationOutset: decorationOutset)
        let expandedHeight = CGFloat(layout.height) + expansion.top + expansion.bottom
        let fit = min(1, CGFloat(maxDimension) / expandedHeight)
        let width = max(1, Int((CGFloat(layout.width) * fit).rounded()))
        let height = Int((expandedHeight * fit).rounded())
        let logicalRowHeight = renderSize[1] / Float(layout.height)
        let rasterOffsetY: Float
        switch style.verticalAlignment.localizedLowercase {
        case "top": rasterOffsetY = Float(expansion.top) * logicalRowHeight
        case "bottom": rasterOffsetY = -Float(expansion.bottom) * logicalRowHeight
        default: rasterOffsetY = Float(expansion.top - expansion.bottom) * logicalRowHeight / 2
        }
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
            context.scaleBy(x: CGFloat(width) / CGFloat(layout.width),
                            y: CGFloat(height) / expandedHeight)
            context.translateBy(x: 0, y: expansion.bottom)
            draw(frame: positioned.frame, attributed: positioned.attributed, origins: positioned.origins,
                 style: style, font: font, layout: layout, context: context)
            return true
        }
        try checkCancellation?()
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
        try checkCancellation?()
        // Center alignment anchors the line block without its trailing descent
        // region. Keep the raster intact (including descenders and decoration);
        // the shared layer pivot consumes this logical, pre-downsample offset.
        return RenderedTexture(
            raster: RasterizedTexture(
                texture: texture,
                renderSizeWH: [renderSize[0], renderSize[1]
                    + Float(expansion.top + expansion.bottom) * logicalRowHeight],
                centerOffsetY: Float(CTFontGetDescent(sourceFont.font)) / 2,
                rasterOffsetY: rasterOffsetY,
                sourceFont: sourceFont
            ),
            font: sourceFont,
            lineBounds: prepared.lineBounds
        )
    }

    private static func prepareTextLayout(
        text: String,
        style: SceneTextDescriptor,
        font: CTFont
    ) -> (text: String, size: [Float], wrapWidth: Float,
          lineBounds: SceneTextRowLimit.LineBounds, primaryLineBox: PrimaryLineBox?)? {
        let policy = SceneTextRowLimit.layoutPolicy(
            text: text, font: font, useEllipsis: style.limitRows && style.useEllipsis
        )
        let attributes = [
            kCTFontAttributeName: font,
            kCTParagraphStyleAttributeName: SceneTextRowLimit.paragraphStyle(
                alignment: .natural, lineBounds: policy.bounds
            )
        ] as CFDictionary
        let wrapWidth = Float(SceneTextRowLimit.wrapWidth(
            contentWidth: CGFloat(maxAutoSizeDimension), style: style, scale: 1
        ))
        let content = SceneTextRowLimit.limitedText(
            text, style: style, attributes: attributes,
            wrapWidth: CGFloat(wrapWidth), lineBounds: policy.bounds
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
        var measuredHeight = ceil(measured.height)
        let primaryLineBox = policy.usesPrimaryLineBox ? primaryLineBox(for: font) : nil
        if let primaryLineBox, measuredHeight > 0 {
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: CGFloat(wrapWidth),
                                           height: measuredHeight), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
            let rows = CFArrayGetCount(CTFrameGetLines(frame))
            if rows > 0 { measuredHeight = ceil(primaryLineBox.height(rows: rows)) }
        }
        // Saved editor size is an observation, not a text layout constraint.
        // Both initial and dynamic content derive their extent from the font,
        // width/row limits and full padding on each edge.
        let padding = max(0, style.padding) * 2
        let size = [
            max(1, Float(ceil(measured.width)) + padding),
            max(1, Float(measuredHeight) + padding),
        ]
        // Padding is authored input. Reject an unrepresentable extent before
        // rasterLayout converts scaled dimensions to integer texture sizes.
        guard size.allSatisfy(\.isFinite) else { return nil }
        return (content, size, wrapWidth, policy.bounds, primaryLineBox)
    }

    /// Read the authored font's native baseline rounding independent of fallback runs.
    private static func primaryLineBox(for font: CTFont) -> PrimaryLineBox? {
        let reference = NSAttributedString(string: " \n ", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(reference)
        let maximum = CGFloat(maxAutoSizeDimension)
        let height = ceil(CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(), nil, CGSize(width: maximum, height: maximum), nil).height)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: maximum, height: height), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
        guard CFArrayGetCount(CTFrameGetLines(frame)) == 2 else { return nil }
        var origins = [CGPoint](repeating: .zero, count: 2)
        CTFrameGetLineOrigins(frame, CFRange(), &origins)
        return PrimaryLineBox(ascent: height - origins[0].y, stride: origins[0].y - origins[1].y,
                              finalDescent: origins[1].y)
    }

    private static func positionText(
        _ text: String,
        wrapWidth: CGFloat,
        lineBounds: SceneTextRowLimit.LineBounds,
        primaryLineBox: PrimaryLineBox?,
        style: SceneTextDescriptor,
        font: CTFont,
        layout: SceneTextGeometry.RasterLayout
    ) -> (frame: CTFrame, attributed: CFAttributedString, origins: [CGPoint]?)? {
        let padding = CGFloat(layout.padding)
        let contentWidth = CGFloat(layout.contentWidth)
        let contentHeight = CGFloat(layout.contentHeight)
        let paragraph = SceneTextRowLimit.paragraphStyle(
            alignment: textAlignment(style.horizontalAlignment), lineBounds: lineBounds
        )
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
        ) else { return nil }
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
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
        guard let primaryLineBox else { return (frame, attributed, nil) }
        let rows = CFArrayGetCount(CTFrameGetLines(frame))
        guard rows > 0 else { return (frame, attributed, nil) }
        let scale = CGFloat(layout.scale)
        let height = primaryLineBox.height(rows: rows) * scale
        let top = verticalOrigin(alignment: style.verticalAlignment, padding: padding,
                                 contentHeight: contentHeight, textHeight: height) + height
        var origins = [CGPoint](repeating: .zero, count: rows)
        CTFrameGetLineOrigins(frame, CFRange(), &origins)
        for index in origins.indices {
            origins[index] = CGPoint(x: x + origins[index].x,
                y: top - (primaryLineBox.ascent + CGFloat(index) * primaryLineBox.stride) * scale)
        }
        return (frame, attributed, origins)
    }

    private static func verticalInkExpansion(
        _ frame: CTFrame, origins adjustedOrigins: [CGPoint]?, height: Int, decorationOutset: CGFloat
    ) -> (top: CGFloat, bottom: CGFloat) {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = adjustedOrigins ?? [CGPoint](repeating: .zero, count: lines.count)
        if adjustedOrigins == nil { CTFrameGetLineOrigins(frame, CFRange(), &origins) }
        let pathY = adjustedOrigins == nil ? CTFrameGetPath(frame).boundingBoxOfPath.minY : 0
        var low = CGFloat.infinity
        var high = -CGFloat.infinity
        for (line, origin) in zip(lines, origins) {
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let baseline = pathY + origin.y
            let minY = baseline + ink.minY
            let maxY = baseline + ink.maxY
            guard minY.isFinite, maxY.isFinite, minY < maxY else { continue }
            low = min(low, minY)
            high = max(high, maxY)
        }
        guard low - decorationOutset < 0 || high + decorationOutset > CGFloat(height) else {
            return (0, 0)
        }
        // Native ink can cover one row above its ideal outline. Keep a clear
        // sampling row outside that coverage and the rounded lower edge.
        return (max(0, ceil(high + decorationOutset) + 2 - CGFloat(height)),
                max(0, 1 - floor(low - decorationOutset)))
    }

    private static func draw(
        frame: CTFrame,
        attributed: CFAttributedString,
        origins: [CGPoint]?,
        style: SceneTextDescriptor,
        font: CTFont,
        layout: SceneTextGeometry.RasterLayout,
        context: CGContext
    ) {
        // Glyph-path margins can place the first outline at a fractional
        // origin. Quantizing that origin again clips its edge at padding=0.
        context.setShouldSubpixelPositionFonts(true)
        context.setShouldSubpixelQuantizeFonts(false)
        if style.opaqueBackground {
            let bounds = CGRect(x: 0, y: 0, width: layout.width, height: layout.height)
            let border = CGFloat(style.decorationInset * layout.scale)
            context.setFillColor(color(style.backgroundColorRGB, brightness: style.backgroundBrightness))
            context.fill(bounds.insetBy(dx: border, dy: border))
        }
        context.textMatrix = .identity
        context.saveGState()
        let scale = CGFloat(layout.scale)
        let shadow = style.dropShadow
        if let shadow {
            // Empirical positive-axis response from owned official probes:
            // 32/64 authored points saturate near 25/50 scene units. Use the
            // live point size before raster scaling, not the scaled CTFont.
            // Negative offsets retain the existing project behavior; official
            // large-negative clipping is not a symmetric version of this law.
            // Keep the conservative authored border shared with the quad pivot.
            let positiveOffsetLimit = CGFloat(style.pointSize) * 25 / 32
            context.setShadow(
                offset: CGSize(
                    width: min(CGFloat(shadow.offset[0]), positiveOffsetLimit) * scale,
                    height: -min(CGFloat(shadow.offset[1]), positiveOffsetLimit) * scale
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
                CGFloat(max(layout.width, layout.height)) * 2
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
                outlineFramesetter, CFRange(location: 0, length: 0), CTFrameGetPath(frame), nil
            )
            drawLines(outlineFrame, origins: origins, context: context)
        }
        drawLines(frame, origins: origins, context: context)
        if shadow != nil { context.endTransparencyLayer() }
        context.restoreGState()
    }

    private static func drawLines(_ frame: CTFrame, origins: [CGPoint]?, context: CGContext) {
        guard let origins else {
            CTFrameDraw(frame, context)
            return
        }
        let lines = CTFrameGetLines(frame) as! [CTLine]
        for (line, origin) in zip(lines, origins) {
            context.textPosition = origin
            CTLineDraw(line, context)
        }
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
