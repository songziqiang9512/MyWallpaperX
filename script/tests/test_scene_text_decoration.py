"""Authored text decoration through the existing descriptor and raster owner.

All text, colors, and style inputs are owned fixtures. The native probe reuses
the nearest text source closure and reads the real premultiplied Metal texture.
Outline distances follow the measured scene-pixel contract; shadow checks do
not assume a blur kernel.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from .test_scene_text_row_limit import HARNESS_SOURCE as ROW_HARNESS
from .test_scene_text_row_limit import SWIFT_SOURCES as ROW_SWIFT_SOURCES

SWIFT_SOURCES = [*ROW_SWIFT_SOURCES, Path(__file__).resolve().parents[2]
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneTextLayerPivot.swift"]


OUTLINE = {"outline": True, "outlinethickness": 4, "outlinecolor": "1 0 0"}
SHADOW = {
    "dropshadow": True,
    "dropshadowoffset": "16 12",
    "dropshadowsize": 6,
    "dropshadowopacity": 1,
    "dropshadowcolor": "0 0 1",
}


def fixture_scene() -> dict:
    base = {
        "text": "MWX",
        "font": "systemfont_arial",
        "pointsize": 20,
        "color": "0 1 0",
        "size": "640 320",
        "padding": "64 64",
        "spacing": "0 0",
        "horizontalalign": "center",
        "verticalalign": "center",
    }
    cases = [
        ("baseline", {}),
        ("color-control", {"color": "0 1 1"}),
        ("outline", OUTLINE),
        ("shadow", SHADOW),
        ("combined", OUTLINE | SHADOW),
        ("outline-disabled", OUTLINE | {"outline": False}),
        ("outline-zero", OUTLINE | {"outlinethickness": 0}),
        ("shadow-disabled", SHADOW | {"dropshadow": False}),
        ("shadow-zero-opacity", SHADOW | {"dropshadowopacity": 0}),
        ("shadow-quarter-opacity", SHADOW | {"dropshadowopacity": 0.25}),
        ("shadow-zero-size", SHADOW | {"dropshadowsize": 0}),
        ("msdf-combined", OUTLINE | SHADOW | {"msdf": True}),
        ("wrapped-combined", {key: {"value": value} for key, value in (OUTLINE | SHADOW).items()}),
        ("opaque-baseline", {"opaquebackground": True, "backgroundcolor": "0.25 0.25 0.25"}),
        ("opaque-combined", OUTLINE | SHADOW | {"opaquebackground": True, "backgroundcolor": "0.25 0.25 0.25"}),
        ("tight-baseline", {"size": "320 128", "padding": "0 0"}),
        ("tight-combined", OUTLINE | SHADOW | {"size": "320 128", "padding": "0 0"}),
        ("cap-baseline", {"text": "M" * 48, "pointsize": 12}),
        ("cap-combined", OUTLINE | SHADOW | {"text": "M" * 48, "pointsize": 12}),
        ("scaled-baseline", {"text": "M" * 48, "padding": 128, "pointsize": 24}),
        ("scaled-combined", OUTLINE | SHADOW | {"text": "M" * 48, "padding": 128, "pointsize": 24,
            "outlinethickness": 8, "dropshadowoffset": "32 24", "dropshadowsize": 12}),
        ("radius-baseline", {"text": "O"}),
        ("radius-four", OUTLINE | {"text": "O"}),
        ("radius-eight", OUTLINE | {"text": "O", "outlinethickness": 8}),
        ("radius-large-baseline", {"text": "O", "pointsize": 32}),
        ("radius-large-four", OUTLINE | {"text": "O", "pointsize": 32}),
        ("radius-large-eight", OUTLINE | {"text": "O", "pointsize": 32, "outlinethickness": 8}),
        # The unstyled control has an authored margin that produces the same
        # measured extent as radius-scaled-four. Assert that grid identity in
        # the probe before using its contour as a physical-radius reference.
        ("radius-scaled-baseline", {"text": "O" * 49, "padding": 140, "pointsize": 24}),
        ("radius-scaled-four", OUTLINE | {"text": "O" * 49, "padding": 128, "pointsize": 24}),
        ("corner-baseline", {"text": "MWXMWX"}),
        ("corner-four", OUTLINE | {"text": "MWXMWX"}),
        ("corner-eight", OUTLINE | {"text": "MWXMWX", "outlinethickness": 8}),
        ("axis-baseline", {"text": "I", "pointsize": 32}),
        ("axis-first-line-marker", {"text": "I\n.", "pointsize": 32}),
        ("axis-last-line-marker", {"text": ".\nI", "pointsize": 32}),
        ("axis-positive", SHADOW | {"text": "I", "pointsize": 32, "dropshadowoffset": "96 48"}),
        ("axis-negative", SHADOW | {"text": "I", "pointsize": 32, "dropshadowoffset": "-96 -48"}),
        ("axis-horizontal", SHADOW | {"text": "I", "pointsize": 128, "dropshadowoffset": "96 0"}),
        ("axis-combined", OUTLINE | SHADOW | {"text": "I", "pointsize": 128,
            "dropshadowoffset": "96 0", "outlinethickness": 8}),
        ("axis-low-positive", SHADOW | {"text": "I", "pointsize": 32}),
        ("axis-mixed-sign", SHADOW | {"text": "I", "pointsize": 32,
            "dropshadowoffset": "96 -48"}),
        ("axis-positive-small-font", SHADOW | {"text": "I", "pointsize": 1,
            "dropshadowoffset": "4 4"}),
        ("axis-positive-large-font", SHADOW | {"text": "I", "pointsize": 64,
            "dropshadowoffset": "96 96"}),
        ("axis-positive-downsampled", SHADOW | {"text": "I", "pointsize": 64,
            "padding": 1400, "dropshadowoffset": "96 96"}),
        ("large-finite-outline", OUTLINE | {"outlinethickness": 1e30}),
        ("large-finite-shadow-size", SHADOW | {"dropshadowsize": 1e30}),
        ("large-finite-shadow-offset", SHADOW | {"dropshadowoffset": [1e30, -1e30]}),
        ("combined-bad-outline", OUTLINE | SHADOW | {"outlinethickness": "nan"}),
        ("combined-bad-shadow", OUTLINE | SHADOW | {"dropshadowoffset": "inf 12"}),
    ]
    for label, field, value, style in [
        ("outline-negative", "outlinethickness", -4, OUTLINE),
        ("outline-nan", "outlinethickness", "nan", OUTLINE),
        ("outline-infinite", "outlinethickness", "inf", OUTLINE),
        ("outline-float-overflow", "outlinethickness", "1e300", OUTLINE),
        ("outline-nan-color", "outlinecolor", "nan 0 0", OUTLINE),
        ("shadow-negative-size", "dropshadowsize", -6, SHADOW),
        ("shadow-nan-size", "dropshadowsize", "nan", SHADOW),
        ("shadow-nan-color", "dropshadowcolor", "0 0 nan", SHADOW),
        ("shadow-infinite-offset", "dropshadowoffset", "inf 12", SHADOW),
        ("shadow-nan-opacity", "dropshadowopacity", "nan", SHADOW),
        ("shadow-float-overflow", "dropshadowopacity", "1e300", SHADOW),
    ]:
        cases.append((label, style | {field: value}))
    for text_name, text in [("o", "O"), ("long", "MWXMWX")]:
        for geometry, size in [("tight", "1 1"), ("wide", "640 320")]:
            for decoration, fields in [("baseline", {}), ("outline4", OUTLINE),
                ("outline8", OUTLINE | {"outlinethickness": 8}), ("positive-shadow", SHADOW),
                ("negative-shadow", SHADOW | {"dropshadowoffset": "-16 -12"}),
                ("positive-combined", OUTLINE | SHADOW),
                ("negative-combined", OUTLINE | SHADOW | {"outlinethickness": 8, "dropshadowoffset": "-16 -12"})]:
                cases.append((f"clip-{text_name}-{geometry}-{decoration}", fields
                    | {"text": text, "size": size, "padding": 128 if geometry == "wide" else 0}))
    for alignment in ["left", "right", "top", "bottom"]:
        fields = {"horizontalalign": alignment if alignment in ("left", "right") else "center",
            "verticalalign": alignment if alignment in ("top", "bottom") else "center"}
        cases.extend([(f"anchor-{alignment}-baseline", fields),
            (f"anchor-{alignment}-combined", fields | OUTLINE | SHADOW)])
    return {"version": 3, "objects": [base | fields | {"id": index + 1, "name": name}
        for index, (name, fields) in enumerate(cases)]}


# These are the existing standalone DTO seams, not a second raster/model owner.
SWIFT_SUPPORT = ROW_HARNESS.partition("\n@main\n")[0]
HARNESS = SWIFT_SUPPORT + r'''

@main
enum DecorationProbe {
    struct Image {
        let size: [Int]
        let logicalSize: [Float]
        let bytes: [UInt8]
        var scale: Double { Double(max(size[0], size[1])) / Double(logicalSize.max()!) }

        init(_ texture: MTLTexture, logicalSize: [Float]) {
            size = [texture.width, texture.height]
            self.logicalSize = logicalSize
            var data = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
            texture.getBytes(&data, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            bytes = data
        }

        private init(size: [Int], logicalSize: [Float], bytes: [UInt8]) {
            self.size = size; self.logicalSize = logicalSize; self.bytes = bytes
        }

        func physicalCoordinates() -> Image {
            Image(size: size, logicalSize: size.map(Float.init), bytes: bytes)
        }

        var statistics: [String: Any] {
            var ink = 0, red = 0, blue = 0, green = 0, cyan = 0
            var partial = 0, premultipliedViolations = 0
            var transparentColor = 0, minX = size[0], minY = size[1], maxX = -1, maxY = -1
            var maxBlueAlpha = 0, blueMass = 0, greenMass = 0, redMass = 0
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let b = Int(bytes[offset]), g = Int(bytes[offset + 1])
                let r = Int(bytes[offset + 2]), a = Int(bytes[offset + 3])
                blueMass += b; greenMass += g; redMass += r
                if max(r, max(g, b)) > a { premultipliedViolations += 1 }
                if a == 0 && (r != 0 || g != 0 || b != 0) { transparentColor += 1 }
                guard a > 0 else { continue }
                ink += 1
                let index = offset / 4, x = index % size[0], y = index / size[0]
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                if a < 255 { partial += 1 }
                if g > 8 && r <= 2 && b <= 2 { green += 1 }
                if g > 8 && b > 8 && r <= 2 { cyan += 1 }
                if r > 8 && g <= 2 && b <= 2 { red += 1 }
                if b > 8 && g <= 2 && r <= 2 {
                    blue += 1; maxBlueAlpha = max(maxBlueAlpha, a)
                }
            }
            let lower = point(minX, minY), upper = point(maxX, maxY)
            return ["size": size, "logicalSize": logicalSize, "ink": ink, "red": red, "blue": blue,
                "channelMass": [blueMass, greenMass, redMass],
                "logicalBounds": [lower.x, lower.y, upper.x, upper.y],
                "edgeTouches": [minX == 0, minY == 0, maxX == size[0] - 1, maxY == size[1] - 1],
                "green": green, "cyan": cyan,
                "partialAlpha": partial, "premultipliedViolations": premultipliedViolations,
                "transparentColor": transparentColor, "maxBlueAlpha": maxBlueAlpha,
                "bounds": [minX, minY, maxX, maxY]]
        }

        func point(_ x: Int, _ y: Int) -> SIMD2<Double> {
            SIMD2((Double(x) + 0.5 - Double(size[0]) / 2) / scale,
                  (Double(y) + 0.5 - Double(size[1]) / 2) / scale)
        }

        func pixel(at point: SIMD2<Double>) -> SIMD4<UInt8> {
            let x = Int(floor(point[0] * scale + Double(size[0]) / 2))
            let y = Int(floor(point[1] * scale + Double(size[1]) / 2))
            guard x >= 0, y >= 0, x < size[0], y < size[1] else { return SIMD4(repeating: 0) }
            let offset = (y * size[0] + x) * 4
            return SIMD4(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
        }

        func comparison(to reference: Image) -> [String: Any] {
            var changed = 0, core = 0, preserved = 0
            let width = reference.size[0], height = reference.size[1]
            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let observed = pixel(at: reference.point(x, y))
                    if (0..<4).contains(where: { observed[$0] != reference.bytes[offset + $0] }) { changed += 1 }
                    guard x >= 2, x < width - 2, y >= 2, y < height - 2,
                          reference.bytes[offset + 3] == 255 else { continue }
                    let isCore = (-2...2).allSatisfy { dy in
                        (-2...2).allSatisfy { dx in
                            let other = ((y + dy) * width + x + dx) * 4
                            return reference.bytes[other..<other + 4] == reference.bytes[offset..<offset + 4]
                        }
                    }
                    guard isCore else { continue }
                    core += 1
                    if (0..<4).allSatisfy({ abs(Int(observed[$0]) - Int(reference.bytes[offset + $0])) <= 2 }) {
                        preserved += 1
                    }
                }
            }
            return ["validLogicalExtent": logicalSize.count == 2 && logicalSize.allSatisfy { $0.isFinite && $0 > 0 },
                "identical": size == reference.size && bytes == reference.bytes,
                "changed": changed, "glyphCore": core, "preservedGlyphCore": preserved]
        }

        func channelMask(_ component: Int) -> [String: Any] {
            var mass = 0.0, momentX = 0.0, momentY = 0.0
            var minimumX = size[0], maximumX = -1, minimumY = size[1], maximumY = -1
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let value = Int(bytes[offset + component])
                guard value > 0 else { continue }
                let x = (offset / 4) % size[0], y = (offset / 4) / size[0]
                let position = point(x, y)
                mass += Double(value)
                momentX += Double(value) * position[0]; momentY += Double(value) * position[1]
                if value >= 128 {
                    minimumX = min(minimumX, x); maximumX = max(maximumX, x)
                    minimumY = min(minimumY, y); maximumY = max(maximumY, y)
                }
            }
            let lower = point(minimumX, minimumY), upper = point(maximumX, maximumY)
            return ["mass": mass, "centroid": mass > 0 ? [momentX / mass, momentY / mass] : [0, 0],
                "halfIntensityBounds": [lower.x, lower.y, upper.x, upper.y]]
        }

        // Coordinates come from published logical extent and observed raster
        // scale. The oracle does not recreate decoration-inset preparation.
        func outlineGeometry(to reference: Image) -> [String: Any] {
            func covered(_ image: Image, _ x: Int, _ y: Int, component: Int) -> Bool {
                x >= 0 && y >= 0 && x < image.size[0] && y < image.size[1]
                    && image.bytes[(y * image.size[0] + x) * 4 + component] >= 128
            }
            var boundary: [SIMD2<Double>] = []
            var minimumX = reference.size[0], maximumX = -1
            var minimumY = reference.size[1], maximumY = -1
            var baselineFillMaskPixels = 0
            for y in 0..<reference.size[1] {
                for x in 0..<reference.size[0] where covered(reference, x, y, component: 1) {
                    baselineFillMaskPixels += 1
                    minimumX = min(minimumX, x); maximumX = max(maximumX, x)
                    minimumY = min(minimumY, y); maximumY = max(maximumY, y)
                    if !covered(reference, x - 1, y, component: 1) || !covered(reference, x + 1, y, component: 1)
                        || !covered(reference, x, y - 1, component: 1) || !covered(reference, x, y + 1, component: 1) {
                        boundary.append(reference.point(x, y))
                    }
                }
            }
            // An exact X-sorted nearest-boundary query keeps long authored
            // text bounded without changing the Euclidean distance oracle.
            boundary.sort { $0.x < $1.x }
            func nearestSquared(_ point: SIMD2<Double>) -> Double {
                var lower = 0, upper = boundary.count
                while lower < upper {
                    let middle = (lower + upper) / 2
                    if boundary[middle].x < point.x { lower = middle + 1 } else { upper = middle }
                }
                var left = lower - 1, right = lower, nearest = Double.greatestFiniteMagnitude
                while left >= 0 || right < boundary.count {
                    let leftDX = left >= 0 ? point.x - boundary[left].x : Double.infinity
                    let rightDX = right < boundary.count ? boundary[right].x - point.x : Double.infinity
                    let useLeft = leftDX <= rightDX
                    let dx = useLeft ? leftDX : rightDX
                    if dx * dx > nearest { break }
                    let other = boundary[useLeft ? left : right]
                    let dy = point.y - other.y
                    nearest = min(nearest, dx * dx + dy * dy)
                    if useLeft { left -= 1 } else { right += 1 }
                }
                return nearest
            }
            var maximumDistanceSquared = 0.0, mismatchSquared = 0.0, observedRed = 0
            for y in 0..<size[1] {
                for x in 0..<size[0] {
                    let offset = (y * size[0] + x) * 4, position = point(x, y)
                    if bytes[offset + 1] >= 128 && reference.pixel(at: position)[1] < 128 {
                        mismatchSquared = max(mismatchSquared, nearestSquared(position))
                    }
                    guard bytes[offset + 2] >= 128, bytes[offset + 1] <= 2, bytes[offset] <= 2 else { continue }
                    observedRed += 1
                    maximumDistanceSquared = max(maximumDistanceSquared, nearestSquared(position))
                }
            }
            for y in 0..<reference.size[1] {
                for x in 0..<reference.size[0] where covered(reference, x, y, component: 1) {
                    let position = reference.point(x, y)
                    if pixel(at: position)[1] < 128 {
                        mismatchSquared = max(mismatchSquared, nearestSquared(position))
                    }
                }
            }
            let middle = reference.point((minimumX + maximumX) / 2, (minimumY + maximumY) / 2)
            func holeWidth(_ image: Image) -> Double {
                let x = Int(floor(middle[0] * image.scale + Double(image.size[0]) / 2))
                let y = Int(floor(middle[1] * image.scale + Double(image.size[1]) / 2))
                guard !covered(image, x, y, component: 3) else { return 0 }
                var left = x, right = x
                while left >= 0 && !covered(image, left, y, component: 3) { left -= 1 }
                while right < image.size[0] && !covered(image, right, y, component: 3) { right += 1 }
                return Double(right - left - 1) / image.scale * reference.scale
            }
            return ["redPixels": observedRed, "baselineFillMaskPixels": baselineFillMaskPixels,
                "referenceRasterScale": reference.scale,
                "sameRasterGrid": size == reference.size && logicalSize == reference.logicalSize,
                "maximumFillMaskMismatchDistance": sqrt(mismatchSquared) * reference.scale,
                "maximumDistance": sqrt(maximumDistanceSquared) * reference.scale,
                "baselineHole": holeWidth(reference), "decoratedHole": holeWidth(self)]
        }
    }

    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = try SceneDocumentLoader().load(from: url)
        let project = SceneProject(rootURL: url.deletingLastPathComponent(),
            entryPath: url.lastPathComponent, userProperties: .empty)
        guard let descriptor = SceneRenderDescriptorBuilder().build(project: project, sceneDocument: document,
            assetCatalog: SceneAssetCatalog(models: [], materials: [], effectDefinitions: [],
                effectDefinitionDiagnostics: [], shaderReferences: [], textureReferences: []),
            resourceReferences: SceneResourceReferenceIndex(missingReferences: [],
                builtInReferenceCount: 0, runtimeProvidedReferenceCount: 0),
            capabilityProfile: SceneCapabilityProfile(firstStageRendererGaps: [])) else { throw ProbeError.descriptor }
        guard let device = MTLCreateSystemDefaultDevice() else { throw ProbeError.metal }
        let loaded = SceneTextTextureLoader.load(descriptor: descriptor,
            cacheDirectory: url.deletingLastPathComponent(), device: device)
        let layers = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.name!, $0) })
        var images: [String: Image] = [:], styleEncoding: [String: Bool] = [:]
        for (name, layer) in layers {
            guard let texture = loaded.textures[layer.id] else { throw ProbeError.texture(name) }
            images[name] = Image(texture, logicalSize: loaded.renderSizes[layer.id]!)
            styleEncoding[name] = (try? JSONEncoder().encode(layer.textStyle)) != nil
        }
        let baseline = images["baseline"]!
        var cases: [String: Any] = [:]
        for (name, image) in images {
            let reference = name == "combined-bad-shadow" ? images["outline"]!
                : name == "combined-bad-outline" ? images["shadow"]!
                : name.hasPrefix("radius-scaled-") ? images["radius-scaled-baseline"]!
                : name.hasPrefix("radius-large-") ? images["radius-large-baseline"]!
                : name.hasPrefix("radius-") ? images["radius-baseline"]!
                : name.hasPrefix("corner-") ? images["corner-baseline"]!
                : name.hasPrefix("axis-") ? images["axis-baseline"]!
                : name.hasPrefix("anchor-") ? images[name.replacingOccurrences(of: "-combined", with: "-baseline")]!
                : name.hasPrefix("clip-") ? images[name.split(separator: "-").prefix(3).joined(separator: "-") + "-baseline"]!
                : name.hasPrefix("tight-") ? images["tight-baseline"]!
                : name.hasPrefix("scaled-") ? images["scaled-baseline"]!
                : name.hasPrefix("cap-") ? images["cap-baseline"]!
                : name.hasPrefix("opaque-") ? images["opaque-baseline"]! : baseline
            cases[name] = ["pixels": image.statistics, "control": image.comparison(to: reference),
                "styleEncodesFiniteJSON": styleEncoding[name]!]
        }
        var dynamic: [String: Any] = [:]
        for variant in ["same", "content", "font", "pointSize", "color"] {
            var rendered: [String: Image] = [:], sizes: [String: [Float]] = [:]
            for name in ["baseline", "outline", "shadow", "combined", "msdf-combined"] {
                let layer = layers[name]!, style = layer.textStyle!
                guard let texture = SceneTextTextureLoader.makeDynamicTexture(for: layer,
                    content: variant == "content" ? "WMWX" : layer.text!,
                    fontPath: variant == "font" ? "systemfont_consolas" : style.fontPath,
                    pointSize: variant == "pointSize" ? 28 : style.pointSize,
                    colorRGB: variant == "color" ? [0, 1, 1] : style.colorRGB,
                    cacheDirectory: url.deletingLastPathComponent(), device: device) else {
                    throw ProbeError.texture(name + variant)
                }
                rendered[name] = Image(texture.texture, logicalSize: texture.renderSizeWH); sizes[name] = texture.renderSizeWH
            }
            var entries: [String: Any] = [:]
            for (name, image) in rendered {
                entries[name] = ["pixels": image.statistics,
                    "control": image.comparison(to: rendered["baseline"]!),
                    "sameAsStatic": image.bytes == images[name]!.bytes && image.size == images[name]!.size
                        && image.logicalSize == images[name]!.logicalSize,
                    "logicalSize": sizes[name]!]
            }
            dynamic[variant] = entries
        }
        let combined = images["combined"]!, opaque = images["opaque-combined"]!
        let background = images["opaque-baseline"]!
        var backgroundError = 0, transparentBorderPixels = 0
        if combined.size == opaque.size && combined.logicalSize == opaque.logicalSize {
            for y in 0..<opaque.size[1] {
                for x in 0..<opaque.size[0] {
                    let offset = (y * opaque.size[0] + x) * 4
                    let position = opaque.point(x, y)
                    let inOriginalBox = abs(position.x) < Double(background.logicalSize[0]) / 2
                        && abs(position.y) < Double(background.logicalSize[1]) / 2
                    let alpha = Int(combined.bytes[offset + 3])
                    for component in 0..<3 {
                        let bg = inOriginalBox ? Int(background.bytes[component]) : 0
                        let expected = Int(combined.bytes[offset + component]) + (bg * (255 - alpha) + 127) / 255
                        backgroundError = max(backgroundError, abs(expected - Int(opaque.bytes[offset + component])))
                    }
                    let expectedAlpha = inOriginalBox ? 255 : alpha
                    backgroundError = max(backgroundError, abs(expectedAlpha - Int(opaque.bytes[offset + 3])))
                    if !inOriginalBox && alpha == 0 && opaque.bytes[offset + 3] == 0 { transparentBorderPixels += 1 }
                }
            }
        } else { backgroundError = 256 }
        var outlineGeometry: [String: Any] = [:]
        for name in ["radius-four", "radius-eight", "radius-large-four", "radius-large-eight", "radius-scaled-four",
            "corner-four", "corner-eight"] {
            let control = name.hasPrefix("corner-") ? "corner-baseline"
                : name.hasPrefix("radius-scaled-") ? "radius-scaled-baseline"
                : name.hasPrefix("radius-large-") ? "radius-large-baseline" : "radius-baseline"
            outlineGeometry[name] = images[name]!.outlineGeometry(to: images[control]!)
        }
        var shadowGeometry: [String: Any] = [:]
        for name in images.keys.filter({ $0.hasPrefix("axis-") }) {
            shadowGeometry[name] = ["fill": images[name]!.channelMask(1), "shadow": images[name]!.channelMask(0),
                "rasterScale": images[name]!.scale]
        }
        let dynamicShadowLayer = layers["axis-positive"]!
        guard let updatedShadow = SceneTextTextureLoader.makeDynamicTexture(
            for: dynamicShadowLayer, content: "I", pointSize: 64, colorRGB: [0, 1, 0],
            cacheDirectory: url.deletingLastPathComponent(), device: device) else {
            throw ProbeError.texture("axis-dynamic-pointsize")
        }
        let updatedImage = Image(updatedShadow.texture, logicalSize: updatedShadow.renderSizeWH)
        shadowGeometry["axis-dynamic-pointsize"] = ["fill": updatedImage.channelMask(1),
            "shadow": updatedImage.channelMask(0)]
        var worldAnchors: [String: Any] = [:]
        for alignment in ["left", "right", "top", "bottom"] {
            let baseName = "anchor-" + alignment + "-baseline"
            var entries: [String: Any] = [:]
            for suffix in ["baseline", "combined"] {
                let name = "anchor-" + alignment + "-" + suffix
                let image = images[name]!, control = images[baseName]!, style = layers[name]!.textStyle!
                let borderX = (image.logicalSize[0] - control.logicalSize[0]) / 2
                let borderY = (image.logicalSize[1] - control.logicalSize[1]) / 2
                // Measure the added border from the published logical extent.
                // The real pivot owns the mapping from authored alignment.
                let pivot = SceneTextLayerPivot.unitOffset(horizontal: style.horizontalAlignment,
                    vertical: style.verticalAlignment,
                    renderSize: SIMD2(image.logicalSize[0], image.logicalSize[1]), padding: style.padding + borderX)
                let fill = image.channelMask(1)["centroid"] as! [Double]
                entries[suffix] = ["glyph": [fill[0] + Double(pivot.x * image.logicalSize[0]),
                    fill[1] - Double(pivot.y * image.logicalSize[1])],
                    "publishedBorderSymmetryError": abs(borderX - borderY)]
            }
            worldAnchors[alignment] = entries
        }
        var scaling: [String: Any] = [:]
        for suffix in ["baseline", "combined"] {
            let cap = images["cap-" + suffix]!, scaled = images["scaled-" + suffix]!
            func metrics(_ image: Image) -> [String: Any] {
                let physical = image.physicalCoordinates()
                return ["logicalSize": image.logicalSize, "rasterSize": image.size,
                    "rasterScale": image.scale,
                    "channels": (0..<3).map { physical.channelMask($0) }]
            }
            scaling[suffix] = ["cap": metrics(cap), "scaled": metrics(scaled),
                "fillGeometry": scaled.physicalCoordinates().outlineGeometry(to: cap.physicalCoordinates()),
                "identicalRaster": cap.size == scaled.size && cap.bytes == scaled.bytes]
        }
        let result: [String: Any] = ["cases": cases, "dynamic": dynamic,
            "outlineGeometry": outlineGeometry,
            "shadowGeometry": shadowGeometry, "worldAnchors": worldAnchors,
            "backgroundSourceOverError": backgroundError, "transparentBorderPixels": transparentBorderPixels,
            "scaling": scaling,
            "wrappedDecoration": images["wrapped-combined"]!.comparison(to: images["combined"]!),
            "loaded": images.count, "messages": loaded.messages]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
    enum ProbeError: Error { case descriptor, metal, texture(String) }
}
'''


class SceneTextDecorationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        evidence = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if evidence:
            Path(evidence).mkdir(parents=True, exist_ok=True)
            cls.temporary = None
            cls.root = Path(tempfile.mkdtemp(prefix="mwx-text-decoration-", dir=evidence))
        else:
            cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-text-decoration-")
            cls.root = Path(cls.temporary.name)
        fixture = cls.root / "scene.json"
        fixture.write_text(json.dumps(fixture_scene(), sort_keys=True, indent=2) + "\n", encoding="utf-8")
        harness = cls.root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = cls.root / "probe"
        command = ["xcrun", "--sdk", "macosx", "swiftc", *(str(path) for path in SWIFT_SOURCES),
            str(harness), "-framework", "Metal", "-framework", "CoreText", "-o", str(binary)]
        identity_sources = [Path(__file__).resolve(), Path(__file__).with_name("test_scene_text_row_limit.py"),
            *SWIFT_SOURCES, fixture, harness]
        identity = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in identity_sources}
        (cls.root / "prerun.json").write_text(json.dumps({"compileCommand": command,
            "runCommand": [str(binary), str(fixture)], "sourceSHA256": identity}, indent=2), encoding="utf-8")
        compiled = subprocess.run(command, capture_output=True, text=True, timeout=120)
        (cls.root / "compile.log").write_text(compiled.stdout + compiled.stderr, encoding="utf-8")
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        completed = subprocess.run([str(binary), str(fixture)], capture_output=True, text=True, timeout=60)
        (cls.root / "run.log").write_text(completed.stdout + completed.stderr, encoding="utf-8")
        if completed.returncode:
            raise RuntimeError(completed.stderr)
        cls.result = json.loads(completed.stdout)
        (cls.root / "result.json").write_text(json.dumps(cls.result, indent=2), encoding="utf-8")
        after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in identity_sources}
        if after != identity:
            raise RuntimeError("text decoration input or production source changed during native run")
        print(f"text decoration evidence: {cls.root}", flush=True)

    @classmethod
    def tearDownClass(cls) -> None:
        if not os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
            cls.temporary.cleanup()

    def assert_fill_and_alpha(self, case: dict) -> None:
        pixels, control = case["pixels"], case["control"]
        self.assertGreater(pixels["ink"], 0)
        self.assertEqual(pixels["premultipliedViolations"], 0)
        self.assertEqual(pixels["transparentColor"], 0)
        self.assertTrue(control["validLogicalExtent"])
        self.assertGreater(control["glyphCore"], 100)
        self.assertEqual(control["preservedGlyphCore"], control["glyphCore"])

    def assert_decoration(self, name: str, case: dict) -> None:
        self.assert_fill_and_alpha(case)
        self.assertGreater(case["control"]["changed"], 0)
        if name in ("outline", "combined", "msdf-combined", "wrapped-combined", "tight-combined"):
            self.assertGreater(case["pixels"]["red"], 0)
        if name in ("shadow", "combined", "msdf-combined", "wrapped-combined", "tight-combined"):
            self.assertGreater(case["pixels"]["blue"], 0)

    def test_static_outline_shadow_and_both_keep_glyph_fill_and_premultiplied_alpha(self) -> None:
        baseline = self.result["cases"]["baseline"]["pixels"]
        self.assertGreater(baseline["green"], 500)
        self.assertEqual(baseline["red"], 0)
        self.assertEqual(baseline["blue"], 0)
        control = self.result["cases"]["color-control"]["pixels"]
        self.assertGreater(control["cyan"], 500)
        self.assertEqual(control["green"], 0)
        self.assertTrue(self.result["wrappedDecoration"]["identical"])
        for name in ["outline", "shadow", "combined", "msdf-combined", "wrapped-combined"]:
            with self.subTest(case=name):
                self.assert_decoration(name, self.result["cases"][name])
                self.assertGreater(self.result["cases"][name]["pixels"]["partialAlpha"], 0)

    def test_disabled_and_zero_styles_keep_exact_original_pixels_and_geometry(self) -> None:
        for name in ["outline-disabled", "outline-zero", "shadow-disabled", "shadow-zero-opacity"]:
            with self.subTest(case=name):
                self.assertTrue(self.result["cases"][name]["control"]["identical"])

    def test_bad_style_values_disable_only_decoration_and_keep_valid_text(self) -> None:
        for name in ["outline-negative", "outline-nan", "outline-infinite", "outline-float-overflow",
            "outline-nan-color", "shadow-negative-size", "shadow-nan-size", "shadow-nan-color",
            "shadow-infinite-offset", "shadow-nan-opacity", "shadow-float-overflow",
            "large-finite-shadow-size", "large-finite-shadow-offset"]:
            with self.subTest(case=name):
                case = self.result["cases"][name]
                self.assertTrue(case["styleEncodesFiniteJSON"])
                self.assertTrue(case["control"]["identical"])
        finite_outline = self.result["cases"]["large-finite-outline"]
        self.assertTrue(finite_outline["styleEncodesFiniteJSON"])
        self.assert_fill_and_alpha(finite_outline)
        for name, remaining in [("combined-bad-outline", "blue"), ("combined-bad-shadow", "red")]:
            with self.subTest(case=name):
                case = self.result["cases"][name]
                self.assertTrue(case["control"]["identical"])
                self.assertGreater(case["pixels"][remaining], 0)

    def test_same_content_static_and_dynamic_raster_are_identical(self) -> None:
        for name, case in self.result["dynamic"]["same"].items():
            with self.subTest(case=name):
                self.assertTrue(case["sameAsStatic"])
                self.assertTrue(all(value > 0 for value in case["logicalSize"]))

    def test_dynamic_content_font_point_size_and_color_keep_authored_decorations(self) -> None:
        for variant in ["content", "font", "pointSize", "color"]:
            for name in ["outline", "shadow", "combined", "msdf-combined"]:
                with self.subTest(variant=variant, case=name):
                    case = self.result["dynamic"][variant][name]
                    self.assert_decoration(name, case)
                    self.assertFalse(case["sameAsStatic"])
                    self.assertTrue(all(value > 0 for value in case["logicalSize"]))

    def test_shadow_opacity_and_background_apply_to_glyph_decoration(self) -> None:
        case = self.result["cases"]["shadow-quarter-opacity"]
        self.assert_fill_and_alpha(case)
        self.assertGreater(case["pixels"]["blue"], 0)
        self.assertLessEqual(case["pixels"]["maxBlueAlpha"], 65)
        self.assertLessEqual(self.result["backgroundSourceOverError"], 2)
        self.assertGreater(self.result["transparentBorderPixels"], 0)
        self.assert_decoration("shadow", self.result["cases"]["shadow-zero-size"])

    def test_shadow_offset_axes_and_outline_caster_follow_authored_geometry(self) -> None:
        geometry = self.result["shadowGeometry"]
        first = geometry["axis-first-line-marker"]["fill"]["centroid"][1]
        last = geometry["axis-last-line-marker"]["fill"]["centroid"][1]
        self.assertGreater(abs(first - last), 20)
        # Two authored lines exchange the heavy I and light dot marker. Their
        # weighted centroids calibrate screen-down from paragraph line order;
        # the intrinsic content box has no spare vertical alignment space.
        down = 1 if last > first else -1
        baseline = geometry["axis-baseline"]["fill"]["centroid"]
        for name, x, y in [("axis-positive", 25, 25), ("axis-negative", -96, -48)]:
            with self.subTest(case=name):
                shadow = geometry[name]["shadow"]
                self.assertGreater(shadow["mass"], 0)
                centroid = shadow["centroid"]
                self.assertAlmostEqual(centroid[0] - baseline[0], x, delta=1.5)
                self.assertAlmostEqual(centroid[1] - baseline[1], down * y, delta=1.5)
                self.assert_fill_and_alpha(self.result["cases"][name])
        plain = geometry["axis-horizontal"]["shadow"]["halfIntensityBounds"]
        outlined = geometry["axis-combined"]["shadow"]["halfIntensityBounds"]
        self.assertGreater(geometry["axis-combined"]["shadow"]["mass"], 0)
        for index, sign in [(0, -1), (1, -1), (2, 1), (3, 1)]:
            with self.subTest(edge=index):
                self.assertAlmostEqual(sign * (outlined[index] - plain[index]), 8, delta=2)

    def test_positive_shadow_ceiling_tracks_live_font_before_raster_scaling(self) -> None:
        # Independent official input observations: 32pt saturates near 25 scene
        # units and 64pt near 50, on each positive axis. Negative large offsets
        # have different official artifacts; their existing project behavior
        # is protected separately, not labelled symmetric official parity.
        geometry = self.result["shadowGeometry"]
        down = 1 if (geometry["axis-last-line-marker"]["fill"]["centroid"][1]
            > geometry["axis-first-line-marker"]["fill"]["centroid"][1]) else -1
        self.assertLess(geometry["axis-positive-downsampled"]["rasterScale"], 1)
        for name, expected in [("axis-low-positive", (16, 12)),
            ("axis-mixed-sign", (25, -48)),
            ("axis-positive-small-font", (0.8, 0.8)),
            ("axis-positive-large-font", (50, 50)),
            ("axis-positive-downsampled", (50, 50)),
            ("axis-dynamic-pointsize", (50, 48))]:
            with self.subTest(case=name):
                entry = geometry[name]
                self.assertGreater(entry["shadow"]["mass"], 0)
                for axis, sign in [(0, 1), (1, down)]:
                    observed = entry["shadow"]["centroid"][axis] - entry["fill"]["centroid"][axis]
                    self.assertAlmostEqual(observed, sign * expected[axis], delta=2)

    def test_outline_expands_outward_by_scene_pixels_and_narrows_the_glyph_hole(self) -> None:
        for name, logical_radius in [("radius-four", 4), ("radius-eight", 8),
            ("radius-large-four", 4), ("radius-large-eight", 8), ("radius-scaled-four", 4)]:
            with self.subTest(case=name):
                geometry = self.result["outlineGeometry"][name]
                self.assertGreater(geometry["redPixels"], 0)
                radius = logical_radius * geometry["referenceRasterScale"]
                if name == "radius-scaled-four":
                    self.assertTrue(geometry["sameRasterGrid"])
                    # This operating scale separates logical radius 4 from a
                    # wrong radius of 4 physical pixels even with quantization.
                    self.assertLess(radius + 1.25, logical_radius)
                # One pixel of contour quantization plus a quarter pixel for
                # antialiased 8-bit thresholding. The logical radius remains
                # font-independent; the readback metric is in physical pixels.
                self.assertAlmostEqual(geometry["maximumDistance"], radius, delta=1.25)
                self.assertAlmostEqual(geometry["baselineHole"] - geometry["decoratedHole"], 2 * radius, delta=2)
                # A thin scaled O need not contain any fully opaque 5x5 core.
                # Its green 50% fill mask directly measures the retained fill.
                self.assertGreater(geometry["baselineFillMaskPixels"], 0)
                self.assertLessEqual(geometry["maximumFillMaskMismatchDistance"], 1.25)
                pixels = self.result["cases"][name]["pixels"]
                self.assertEqual(pixels["premultipliedViolations"], 0)
                self.assertEqual(pixels["transparentColor"], 0)
                if name == "radius-scaled-four":
                    self.assertGreater(max(pixels["logicalSize"]), 2048)
                    self.assertEqual(max(pixels["size"]), 2048)
                    self.assertLess(geometry["referenceRasterScale"], 1)

    def test_tight_frame_and_max_texture_scaling_preserve_fill_and_style_geometry(self) -> None:
        self.assert_decoration("tight-combined", self.result["cases"]["tight-combined"])
        # Real long text reaches the cap. Doubling font, per-edge padding and
        # decorations keeps physical geometry after downsampling, with measured
        # extent rounding and one pixel of contour quantization allowed.
        for suffix, pair in self.result["scaling"].items():
            with self.subTest(style=suffix):
                cap, scaled = pair["cap"], pair["scaled"]
                for item in [cap, scaled]:
                    self.assertGreater(max(item["logicalSize"]), 2048)
                    self.assertEqual(max(item["rasterSize"]), 2048)
                    self.assertLess(item["rasterScale"], 1)
                for actual, expected in zip(scaled["logicalSize"], cap["logicalSize"]):
                    self.assertAlmostEqual(actual, expected * 2, delta=2)
                # Independently rounded/scaled authored sizes can shift the
                # contour one pixel per axis (Euclidean diagonal sqrt(2)), even
                # when final raster sizes coincide. Same authored font/extent
                # outline comparisons retain their 1.25-pixel contract.
                self.assertLessEqual(pair["fillGeometry"]["maximumFillMaskMismatchDistance"], 2 ** 0.5)
                self.assertGreater(pair["fillGeometry"]["baselineFillMaskPixels"], 0)
                for channel in ([1] if suffix == "baseline" else [0, 1, 2]):
                    actual, expected = scaled["channels"][channel], cap["channels"][channel]
                    self.assertGreater(expected["mass"], 0)
                    self.assertAlmostEqual(actual["mass"], expected["mass"], delta=expected["mass"] * 0.02)
                    for actual_edge, expected_edge in zip(actual["halfIntensityBounds"], expected["halfIntensityBounds"]):
                        self.assertAlmostEqual(actual_edge, expected_edge, delta=1.25)

    def test_outline_sharp_glyph_corners_have_bounded_extension_and_keep_fill(self) -> None:
        baseline = self.result["cases"]["corner-baseline"]["pixels"]["logicalBounds"]
        for name, radius in [("corner-four", 4), ("corner-eight", 8)]:
            with self.subTest(case=name):
                case = self.result["cases"][name]
                self.assert_fill_and_alpha(case)
                self.assertGreater(case["pixels"]["red"], 0)
                geometry = self.result["outlineGeometry"][name]
                self.assertGreater(geometry["baselineFillMaskPixels"], 0)
                self.assertLessEqual(geometry["maximumFillMaskMismatchDistance"], 1.25)
                bounds = case["pixels"]["logicalBounds"]
                for edge, sign in [(0, -1), (1, -1), (2, 1), (3, 1)]:
                    extension = sign * (bounds[edge] - baseline[edge])
                    self.assertGreaterEqual(extension, 0)
                    self.assertLessEqual(extension, (3 * radius if edge == 2 else radius) + 2)
                    if edge == 2:
                        self.assertGreater(extension, radius)

    def test_tight_text_keeps_complete_decorations_against_the_same_style_in_a_large_canvas(self) -> None:
        for text in ["o", "long"]:
            for style in ["outline4", "outline8", "positive-shadow", "negative-shadow",
                "positive-combined", "negative-combined"]:
                with self.subTest(text=text, style=style):
                    tight = self.result["cases"][f"clip-{text}-tight-{style}"]["pixels"]
                    wide = self.result["cases"][f"clip-{text}-wide-{style}"]["pixels"]
                    self.assertFalse(any(tight["edgeTouches"]))
                    self.assertEqual(tight["premultipliedViolations"], 0)
                    self.assertEqual(tight["transparentColor"], 0)
                    self.assertGreater(tight["red"] if "outline" in style or "combined" in style else tight["blue"], 0)
                    for actual, expected in zip(tight["channelMass"], wide["channelMass"]):
                        self.assertAlmostEqual(actual, expected, delta=max(1, expected * 0.02))
                    tight_control = self.result["cases"][f"clip-{text}-tight-baseline"]["pixels"]["logicalBounds"]
                    wide_control = self.result["cases"][f"clip-{text}-wide-baseline"]["pixels"]["logicalBounds"]
                    for edge in range(4):
                        # Compare coverage relative to the unchanged glyph,
                        # allowing one pixel of raster placement quantization.
                        self.assertAlmostEqual(tight["logicalBounds"][edge] - tight_control[edge],
                            wide["logicalBounds"][edge] - wide_control[edge], delta=1.25)

    def test_published_extent_and_real_pivot_keep_world_glyph_anchors(self) -> None:
        for alignment, entries in self.result["worldAnchors"].items():
            with self.subTest(alignment=alignment):
                self.assertLessEqual(entries["combined"]["publishedBorderSymmetryError"], 0.001)
                for actual, expected in zip(entries["combined"]["glyph"], entries["baseline"]["glyph"]):
                    self.assertAlmostEqual(actual, expected, delta=1)


if __name__ == "__main__":
    unittest.main()
