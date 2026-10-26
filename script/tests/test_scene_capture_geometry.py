#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneMatrix.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneCaptureGeometry.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerCursorGeometry.swift",
]
LOCAL_SOURCE_FIXTURE = Path(__file__).with_name("fixtures") / "SceneCompositionLocalSourceChecks.swift"

HARNESS_SOURCE = r'''
import CoreGraphics
import Foundation
import simd

struct SceneTextureUVTransform {
    let origin: SIMD2<Float>
    let xAxis: SIMD2<Float>
    let yAxis: SIMD2<Float>
    nonisolated static let identity = SceneTextureUVTransform(
        origin: .zero, xAxis: SIMD2(1, 0), yAxis: SIMD2(0, 1)
    )
}

@main
enum Harness {
    static func main() throws {
        let viewport = CGSize(width: 1000, height: 800)
        let localMVP = SceneMatrix.translation(SIMD3<Float>(0.5, -0.25, 0))
            * SceneMatrix.scale(SIMD3<Float>(1, 0.5, 1))
        let local = SceneCaptureGeometryResolver.resolve(
            kind: .composition, layerMVP: localMVP, viewportSize: viewport
        )!
        let fullscreen = SceneCaptureGeometryResolver.resolve(
            kind: .fullscreen, layerMVP: localMVP, viewportSize: viewport,
            compositionSourceMemberLayerIDs: [], authoredRenderSizeWH: [2000, 2000]
        )!
        let singularLayerMVP = SceneMatrix.scale(SIMD3<Float>(0, 0, 1))
        let fullscreenFromSingularLayer = SceneCaptureGeometryResolver.resolve(
            kind: .fullscreen,
            layerMVP: singularLayerMVP,
            viewportSize: viewport
        )!
        let compositionFromSingularLayer = SceneCaptureGeometryResolver.resolve(
            kind: .composition,
            layerMVP: singularLayerMVP,
            viewportSize: viewport
        )!
        let project = SceneCaptureGeometryResolver.resolve(
            kind: .project, layerMVP: localMVP, viewportSize: viewport
        )!
        let memberGroup = SceneCaptureGeometryResolver.resolve(
            kind: .composition, layerMVP: localMVP, viewportSize: viewport,
            compositionSourceMemberLayerIDs: [777]
        )!
        let projectWithMemberFlag = SceneCaptureGeometryResolver.resolve(
            kind: .project, layerMVP: localMVP, viewportSize: viewport,
            compositionSourceMemberLayerIDs: [777], authoredRenderSizeWH: [2000, 2000]
        )!
        // Exact quarter-turn matrix avoids a ceil-boundary oracle depending
        // on trigonometric rounding; scales/translation remain binary-exact.
        let turn = simd_float4x4(SIMD4(0, 1, 0, 0), SIMD4(-1, 0, 0, 0),
                                SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1))
        let parent = SceneMatrix.translation(SIMD3<Float>(0.25, -0.125, 0))
            * turn * SceneMatrix.scale(SIMD3<Float>(1.5, 0.5, 1))
        let child = SceneMatrix.translation(SIMD3<Float>(0.125, 0.25, 0))
            * SceneMatrix.scale(SIMD3<Float>(0.5, 0.25, 1))
        let parentMVP = parent * child
        let nonSquare = CGSize(width: 640, height: 360)
        let parentEmpty = SceneCaptureGeometryResolver.resolve(
            kind: .composition, layerMVP: parentMVP, viewportSize: nonSquare,
            compositionSourceMemberLayerIDs: []
        )!
        let parentMembers = SceneCaptureGeometryResolver.resolve(
            kind: .composition, layerMVP: parentMVP, viewportSize: nonSquare,
            compositionSourceMemberLayerIDs: [777], authoredRenderSizeWH: [2000, 2000]
        )!
        let authoredParent = SceneCaptureGeometryResolver.resolve(
            kind: .composition, layerMVP: parentMVP, viewportSize: nonSquare,
            compositionSourceMemberLayerIDs: [], authoredRenderSizeWH: [2000, 2000]
        )!
        let nilSourceWithAuthoredSize = SceneCaptureGeometryResolver.resolve(
            kind: .composition, layerMVP: parentMVP, viewportSize: nonSquare,
            compositionSourceMemberLayerIDs: nil, authoredRenderSizeWH: [2000, 2000]
        )!
        let invalidTransparentSizes: [String: [Float]] = [
            "zero": [0, 2000], "negative": [2000, -1], "nan": [.nan, 2000],
            "infinity": [2000, .infinity], "empty": [], "oneAxis": [2000],
            "threeAxes": [2000, 2000, 1],
            "finiteIntOverflow": [1e20, 2000],
            "greatestFinite": [2000, .greatestFiniteMagnitude],
            "roundedIntOverflow": [Float(Int.max), 2000],
        ]
        let invalid = SceneCaptureGeometryResolver.resolve(
            kind: .composition,
            layerMVP: localMVP,
            viewportSize: CGSize(width: 0, height: 800)
        )
        // Independent projective output: w varies across the card. Its
        // fourth corner is not reconstructible from an affine capture UV.
        let outputMVP = simd_float4x4(
            SIMD4(1, 0, 0, 0.6), SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(0.1, -0.2, 0.4, 1)
        )
        let replay = SceneCaptureGeometryResolver.resolve(
            kind: .composition, layerMVP: outputMVP,
            viewportSize: viewport, captureMVP: localMVP
        )!
        let authoredSquare = SceneCaptureGeometryResolver.resolve(
            kind: .composition, layerMVP: outputMVP, viewportSize: nonSquare,
            captureMVP: localMVP, compositionSourceMemberLayerIDs: [],
            authoredRenderSizeWH: [2000, 2000]
        )!
        let materialSource = SceneCaptureGeometryResolver.resolve(
            kind: .composition, layerMVP: outputMVP, viewportSize: nonSquare,
            captureMVP: localMVP, compositionSourceMemberLayerIDs: [],
            authoredRenderSizeWH: [665, 151], usesMaterialSource: true
        )!
        let localPoints: [SIMD2<Float>] = [SIMD2(-0.3, 0.2), .zero, SIMD2(0.4, -0.1)]
        let cursorPoints = localPoints.map { point -> [Float] in
            let clip = replay.outputMVP * SIMD4(point.x, point.y, 0, 1)
            let recovered = SceneLayerCursorGeometry.layerPoint(
                mouseNormalized: SIMD2(clip.x, clip.y) / clip.w,
                modelViewProjection: replay.outputMVP
            )!
            return [recovered.x, recovered.y]
        }
        let replayCorners = [SIMD2<Float>(-0.5, 0.5), SIMD2(0.5, 0.5),
                             SIMD2(0.5, -0.5), SIMD2(-0.5, -0.5)].map { point -> [Float] in
            let clip = replay.outputMVP * SIMD4(point.x, point.y, 0, 1)
            return [clip.x / clip.w, clip.y / clip.w]
        }
        let projected = SceneCaptureGeometryResolver.projectedPixelSize(
            layerMVP: SceneMatrix.scale(SIMD3<Float>(1.5, 0.25, 1)),
            viewportSize: viewport
        )
        let fullCoverage = SceneCaptureGeometryResolver
            .isAxisAlignedFullViewportCoverage(
                layerMVP: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                viewportSize: viewport
            )
        let sparseCoverage = SceneCaptureGeometryResolver
            .isAxisAlignedFullViewportCoverage(
                layerMVP: SceneMatrix.scale(SIMD3<Float>(1, 1, 1)),
                viewportSize: viewport
            )
        let rotatedCoverage = SceneCaptureGeometryResolver
            .isAxisAlignedFullViewportCoverage(
                layerMVP: SceneMatrix.rotationZ(.pi / 4)
                    * SceneMatrix.scale(SIMD3<Float>(3, 3, 1)),
                viewportSize: viewport
            )
        let authoredExtent = SceneLayerEffectSourceExtent.resolve(
            publishedRenderSizeWH: nil,
            authoredRenderSizeWH: [1920, 1080],
            candidateMappedSize: CGSize(width: 2048, height: 2048)
        )
        let publishedExtent = SceneLayerEffectSourceExtent.resolve(
            publishedRenderSizeWH: [861, 1366],
            authoredRenderSizeWH: [1920, 1080],
            candidateMappedSize: CGSize(width: 1024, height: 2048)
        )
        let mappedExtent = SceneLayerEffectSourceExtent.resolve(
            publishedRenderSizeWH: nil,
            authoredRenderSizeWH: nil,
            candidateMappedSize: CGSize(width: 1415, height: 2047)
        )
        let invalidAuthoredExtent = SceneLayerEffectSourceExtent.resolve(
            publishedRenderSizeWH: nil,
            authoredRenderSizeWH: [0, 1080],
            candidateMappedSize: CGSize(width: 2048, height: 2048)
        )
        let solidSizes: [[Float]] = [
            [64, 0], [0, 64], [0, 0], [64, 1], [64, 4],
            [32.25, 4.01], [0.001, 0.5],
        ]
        let invalidSolidSizes: [String: [Float]] = [
            "empty": [], "oneAxis": [64], "threeAxes": [64, 1, 2],
            "negativeWidth": [-1, 64], "negativeHeight": [64, -1],
            "nanWidth": [.nan, 64], "nanHeight": [64, .nan],
            "infiniteWidth": [.infinity, 64], "infiniteHeight": [64, .infinity],
            "negativeInfiniteWidth": [-.infinity, 64],
            "negativeInfiniteHeight": [64, -.infinity],
            "overflowWidth": [.greatestFiniteMagnitude, 1],
            "overflowHeight": [1, .greatestFiniteMagnitude],
            "roundedIntOverflow": [Float(Int.max), 1],
        ]
        let result: [String: Any] = [
            "compositionLocalSource": SceneCompositionLocalSourceChecks.run(),
            "backgroundCopyAxes": backgroundCopyAxes(),
            "samePixelSource": samePixelSource(),
            "collapsedProjectedSize": {
                let size = SceneCaptureGeometryResolver.projectedPixelSize(
                    layerMVP: SceneMatrix.scale(SIMD3<Float>(0, 0, 0)),
                    viewportSize: viewport)!
                let extent = SceneLayerEffectSourceExtent(pixelSize: size)!
                return [extent.pixelSize.width, extent.pixelSize.height]
            }(),
            "localOrigin": vector(local.sourceUV.origin),
            "localXAxis": vector(local.sourceUV.xAxis),
            "localYAxis": vector(local.sourceUV.yAxis),
            "localSize": [local.pixelSize.width, local.pixelSize.height],
            "localOutput": matrix(local.outputMVP),
            "memberGroup": geometry(memberGroup),
            "projectWithMemberFlag": geometry(projectWithMemberFlag),
            "parentEmpty": geometry(parentEmpty),
            "parentMembers": geometry(parentMembers),
            "authoredParent": geometry(authoredParent),
            "authoredSquare": geometry(authoredSquare),
            "materialSource": geometry(materialSource),
            "localWorldCard": matrix(SceneCaptureGeometryResolver.resolve(
                kind: .composition, layerMVP: outputMVP, viewportSize: nonSquare,
                captureMVP: localMVP, compositionSourceMemberLayerIDs: [],
                authoredRenderSizeWH: [665, 151], usesMaterialSource: true,
                outputUnitModelMatrix: parentMVP
            )!.outputUnitModelMatrix!),
            "localGroupWorldCard": matrix(SceneCaptureGeometryResolver.resolve(
                kind: .composition, layerMVP: outputMVP, viewportSize: nonSquare,
                compositionSourceMemberLayerIDs: [777],
                localCompositionSourceExtent: CGSize(width: 665, height: 151),
                outputUnitModelMatrix: parentMVP
            )!.outputUnitModelMatrix!),
            "expectedWorldCard": matrix(parentMVP),
            "fullscreenWorldUnknown": SceneCaptureGeometryResolver.resolve(
                kind: .fullscreen, layerMVP: outputMVP, viewportSize: nonSquare,
                outputUnitModelMatrix: parentMVP
            )!.outputUnitModelMatrix == nil,
            "legacyGroupWorldUnknown": SceneCaptureGeometryResolver.resolve(
                kind: .composition, layerMVP: outputMVP, viewportSize: nonSquare,
                compositionSourceMemberLayerIDs: [777],
                outputUnitModelMatrix: parentMVP
            )!.outputUnitModelMatrix == nil,
            "materialSourceProjectRejected": SceneCaptureGeometryResolver.resolve(
                kind: .project, layerMVP: outputMVP, viewportSize: nonSquare,
                authoredRenderSizeWH: [665, 151], usesMaterialSource: true
            ) == nil,
            "materialSourceMemberRejected": SceneCaptureGeometryResolver.resolve(
                kind: .composition, layerMVP: outputMVP, viewportSize: nonSquare,
                compositionSourceMemberLayerIDs: [777],
                authoredRenderSizeWH: [665, 151], usesMaterialSource: true
            ) == nil,
            "materialSourceMissingExtentRejected": SceneCaptureGeometryResolver.resolve(
                kind: .composition, layerMVP: outputMVP, viewportSize: nonSquare,
                usesMaterialSource: true
            ) == nil,
            "materialSourceInvalidExtentsRejected": invalidTransparentSizes.mapValues {
                SceneCaptureGeometryResolver.resolve(
                    kind: .composition, layerMVP: outputMVP, viewportSize: nonSquare,
                    authoredRenderSizeWH: $0, usesMaterialSource: true
                ) == nil
            },
            "nilSourceWithAuthoredSize": geometry(nilSourceWithAuthoredSize),
            "invalidTransparentSizesRejected": invalidTransparentSizes.mapValues {
                SceneCaptureGeometryResolver.resolve(
                    kind: .composition, layerMVP: parentMVP, viewportSize: nonSquare,
                    compositionSourceMemberLayerIDs: [], authoredRenderSizeWH: $0
                ) == nil
            },
            "replaySource": [vector(replay.sourceUV.origin),
                             vector(replay.sourceUV.xAxis), vector(replay.sourceUV.yAxis)],
            "replaySize": [replay.pixelSize.width, replay.pixelSize.height],
            "replayCorners": replayCorners,
            "replayCursorPoints": cursorPoints,
            "fullscreenOrigin": vector(fullscreen.sourceUV.origin),
            "fullscreenAxes": [
                fullscreen.sourceUV.xAxis.x, fullscreen.sourceUV.xAxis.y,
                fullscreen.sourceUV.yAxis.x, fullscreen.sourceUV.yAxis.y,
            ],
            "fullscreenSize": [fullscreen.pixelSize.width, fullscreen.pixelSize.height],
            "fullscreenOutput": matrix(fullscreen.outputMVP),
            "fullscreenCanonicalProjectionInvertible":
                SceneLayerCursorGeometry.effectTextureProjectionInverse(
                    inverseModelViewProjection: SceneLayerCursorGeometry.preciseInverseModelViewProjection(
                        fullscreenFromSingularLayer.outputMVP),
                    required: true
                ) != nil,
            "singularCompositionProjectionRejected":
                SceneLayerCursorGeometry.effectTextureProjectionInverse(
                    inverseModelViewProjection: SceneLayerCursorGeometry.preciseInverseModelViewProjection(
                        compositionFromSingularLayer.outputMVP),
                    required: true
                ) == nil,
            "projectOrigin": vector(project.sourceUV.origin),
            "projectXAxis": vector(project.sourceUV.xAxis),
            "projectYAxis": vector(project.sourceUV.yAxis),
            "projectSize": [project.pixelSize.width, project.pixelSize.height],
            "projectOutput": matrix(project.outputMVP),
            "invalidIsNil": invalid == nil,
            "projectedSize": projected.map { [$0.width, $0.height] } ?? [],
            "fullCoverage": fullCoverage,
            "sparseCoverage": sparseCoverage,
            "rotatedCoverage": rotatedCoverage,
            "authoredExtent": authoredExtent.map {
                [$0.pixelSize.width, $0.pixelSize.height]
            } ?? [],
            "publishedExtent": publishedExtent.map {
                [$0.pixelSize.width, $0.pixelSize.height]
            } ?? [],
            "mappedExtent": mappedExtent.map {
                [$0.pixelSize.width, $0.pixelSize.height]
            } ?? [],
            "invalidAuthoredExtentIsNil": invalidAuthoredExtent == nil,
            "solidAuthoredExtents": solidSizes.map { size in
                SceneLayerEffectSourceExtent.resolveSolid(authoredRenderSizeWH: size)
                    .map { [$0.pixelSize.width, $0.pixelSize.height] } ?? []
            },
            "invalidSolidSizesRejected": invalidSolidSizes.mapValues {
                SceneLayerEffectSourceExtent.resolveSolid(authoredRenderSizeWH: $0) == nil
            },
            "absentSolidSizeIsNil": SceneLayerEffectSourceExtent.resolveSolid(
                authoredRenderSizeWH: nil
            ) == nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func samePixelSource() -> [String: [String: Bool]] {
        let viewport = CGSize(width: 1024, height: 512)
        let full = SceneMatrix.scale(SIMD3<Float>(2, 2, 1))
        let quarterTurn = simd_float4x4(SIMD4(0, 1, 0, 0), SIMD4(-1, 0, 0, 0),
                                      SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1))
        let offscreen = SceneMatrix.translation(SIMD3<Float>(65536, -32768, 0)) * full
        func capture(_ source: simd_float4x4, output: simd_float4x4? = nil) -> SceneCaptureGeometry {
            SceneCaptureGeometryResolver.resolve(kind: .composition,
                layerMVP: output ?? source, viewportSize: viewport, captureMVP: source)!
        }
        func matches(_ geometry: SceneCaptureGeometry, _ output: simd_float4x4,
                     size: CGSize = viewport) -> Bool {
            geometry.sourceMatchesOutputPixels(rasterOutputMVP: output, viewportSize: size)
        }
        var constantW = quarterTurn * SceneMatrix.scale(SIMD3<Float>(1.5, 0.25, 1))
        constantW.columns.3.w = 2
        var negativeW = constantW
        negativeW.columns.3.w = -2
        let rotated = SceneMatrix.translation(SIMD3<Float>(0.125, -0.25, 0))
            * SceneMatrix.rotationZ(.pi / 5) * SceneMatrix.scale(SIMD3<Float>(-3, 0.5, 1))
        let accepted = [
            "identity": matches(capture(full), full),
            "quarterTurnNonuniform": matches(capture(constantW), constantW),
            "negativeConstantW": matches(capture(negativeW), negativeW),
            "rotationMirroring": matches(capture(rotated), rotated),
            "offscreen": matches(capture(offscreen), offscreen),
            "collapsedAffine": matches(capture(SceneMatrix.scale(SIMD3<Float>(0, 0, 1))),
                                       SceneMatrix.scale(SIMD3<Float>(0, 0, 1))),
        ]
        var projective = full
        projective.columns.0.w = 0.25
        var tinyProjective = full
        tinyProjective.columns.1.w = Float.leastNormalMagnitude
        var shiftedOffscreen = offscreen
        shiftedOffscreen.columns.3.x += 0.25
        // All three basis points differ by <=3/64 pixel. Their fourth corner
        // differs by3/32 pixel, so a three-point tolerance alone is insufficient.
        let delta: Float = 3 / 65536
        var fourthCorner = full
        fourthCorner.columns.0.x += 2 * delta
        fourthCorner.columns.1.x = -2 * delta
        fourthCorner.columns.3.x = 2 * delta
        let mismatches = [
            "zoom": !matches(capture(full), SceneMatrix.scale(SIMD3<Float>(2.25, 2, 1))),
            "translation": !matches(capture(full), SceneMatrix.translation(SIMD3<Float>(0.25, 0, 0)) * full),
            "flatCapturePerspectiveOutput": !matches(capture(full, output: projective), projective),
            "projectiveEvenAtTinyWVariation": !matches(capture(full), tinyProjective),
            "largeOffscreenPixelDisagreement": !matches(capture(offscreen), shiftedOffscreen),
            "fourthCorner": !matches(capture(full), fourthCorner),
        ]
        // The same normalized displacement is1/32 pixel here and1/8 pixel
        // on the larger target. Its tolerance cannot follow object magnitude.
        var subpixel = full
        subpixel.columns.3.x = 1 / 16384
        let pixelLimits = [
            "withinFixedPixelError": matches(capture(full), subpixel),
            "largerTargetRejectsSameUVError": !matches(capture(full), subpixel,
                size: CGSize(width: 4096, height: 2048)),
        ]
        let rootMVP = SceneMatrix.translation(SIMD3<Float>(0.25, -0.125, 0))
            * quarterTurn * SceneMatrix.scale(SIMD3<Float>(0.5, 0.25, 1))
        let enclosing = SceneCompositionSourceGeometry(authoredRenderSizeWH: [80, 40],
                                                       worldMVP: rootMVP)!
        let raster = enclosing.rasterModelViewProjection(rootMVP)
        let enclosedCapture = capture(raster, output: rootMVP)
        let enclosingChecks = [
            "actualRasterMatches": matches(enclosedCapture, raster, size: enclosing.pixelSize),
            "rawWorldMatrixRejected": !matches(enclosedCapture, rootMVP, size: enclosing.pixelSize),
        ]
        var zeroW = full
        zeroW.columns.3.w = 0
        var nan = full
        nan.columns.2.z = .nan
        var infinite = full
        infinite.columns.0.x = .infinity
        var overflow = full
        overflow.columns.0.x = .greatestFiniteMagnitude
        overflow.columns.3.x = .greatestFiniteMagnitude
        var divisionOverflow = full
        divisionOverflow.columns.3.x = 16
        divisionOverflow.columns.3.w = Float.leastNormalMagnitude
        let invalidUV = SceneCaptureGeometry(sourceUV: .init(origin: SIMD2(.nan, 0),
            xAxis: SIMD2(1, 0), yAxis: SIMD2(0, 1)), outputMVP: full, pixelSize: viewport)
        let overflowingUV = SceneCaptureGeometry(sourceUV: .init(
            origin: SIMD2(Float.greatestFiniteMagnitude, 0),
            xAxis: SIMD2(Float.greatestFiniteMagnitude, 0), yAxis: SIMD2(0, 1)),
            outputMVP: full, pixelSize: viewport)
        let invalid = [
            "zeroW": !matches(capture(full), zeroW),
            "nanMatrix": !matches(capture(full), nan),
            "infiniteMatrix": !matches(capture(full), infinite),
            "floatClipOverflow": !matches(capture(full), overflow),
            "floatDivisionOverflow": !matches(capture(full), divisionOverflow),
            "nanSourceUV": !matches(invalidUV, full),
            "sourceUVCornerOverflow": !matches(overflowingUV, full),
            "zeroViewport": !matches(capture(full), full, size: CGSize(width: 0, height: 512)),
            "negativeViewport": !matches(capture(full), full, size: CGSize(width: 1024, height: -1)),
            "nanViewport": !matches(capture(full), full, size: CGSize(width: CGFloat.nan, height: 512)),
            "infiniteViewport": !matches(capture(full), full, size: CGSize(width: 1024, height: CGFloat.infinity)),
            "pixelErrorOverflow": !matches(capture(full), SceneMatrix.translation(SIMD3<Float>(8, 0, 0)) * full,
                size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 512)),
        ]
        return ["accepted": accepted, "mismatches": mismatches,
                "pixelLimits": pixelLimits, "enclosing": enclosingChecks, "invalid": invalid]
    }

    static func backgroundCopyAxes() -> [String: Any] {
        let viewport = CGSize(width: 800, height: 800)
        let turn = simd_float4x4(SIMD4(0, 1, 0, 0), SIMD4(-1, 0, 0, 0),
                                SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1))
        let flat = SceneMatrix.scale(SIMD3<Float>(1, 0.25, 1))
        let rotated = turn * flat
        let renamedUtility = SceneUtilityLayer.parse(
            imagePath: "MODELS/UTIL/COMPOSELAYER.JSON",
            object: ["id": 9012, "name": "Renamed composition input", "copybackground": true])!
        let arbitrary = simd_float4x4(
            SIMD4(0.375, 0.5, 0, 0), SIMD4(-0.125, 0.09375, 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(0.125, -0.25, 0, 1))
        let parent = SceneMatrix.translation(SIMD3<Float>(0.125, -0.25, 0))
            * SceneMatrix.scale(SIMD3<Float>(-1.5, 0.5, 1))
        let child = simd_float4x4(
            SIMD4(0.1875, 0.25, 0, 0), SIMD4(-0.125, 0.09375, 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(0.25, 0.125, 0, 1))
        var constantW = rotated
        constantW.columns.3.w = 2
        var negativeW = rotated
        negativeW.columns.3.w = -2
        let projective = simd_float4x4(
            SIMD4(1, 0, 0, 0.6), SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(0.1, -0.2, 0.4, 1))
        var tinyProjective = rotated
        tinyProjective.columns.0.w = 0.00001
        func resolve(_ mvp: simd_float4x4, kind: SceneUtilityLayer.Kind = .composition,
                     size: CGSize = viewport, capture: simd_float4x4? = nil,
                     members: [Int]? = nil, authored: [Float]? = nil,
                     material: Bool = false) -> SceneCaptureGeometry? {
            SceneCaptureGeometryResolver.resolve(
                kind: kind, layerMVP: mvp, viewportSize: size, captureMVP: capture,
                compositionSourceMemberLayerIDs: members, authoredRenderSizeWH: authored,
                usesMaterialSource: material)
        }
        var nonfinite = flat
        nonfinite.columns.0.x = .nan
        var zeroW = flat
        zeroW.columns.3.w = 0
        let invalid: [String: Bool] = [
            "nonfiniteAxis": resolve(nonfinite) == nil,
            "zeroW": resolve(zeroW) == nil,
            "finiteIntOverflow": resolve(SceneMatrix.scale(SIMD3<Float>(1e20, 1, 1))) == nil,
            "viewportProductOverflow": resolve(flat,
                size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 800)) == nil,
            "zeroViewport": resolve(flat, size: CGSize(width: 800, height: 0)) == nil,
            "nonfiniteViewport": resolve(flat, size: CGSize(width: CGFloat.nan, height: 800)) == nil,
        ]
        return [
            "quarterTurn": geometry(resolve(rotated)!),
            "renamedInput": geometry(resolve(rotated, kind: renamedUtility.kind,
                members: renamedUtility.copyBackground ? nil : [])!),
            "reverseTurn": geometry(resolve(turn.transpose * flat)!),
            "arbitraryAngle": geometry(resolve(arbitrary)!),
            "nonSquareViewport": geometry(resolve(arbitrary,
                size: CGSize(width: 1024, height: 512))!),
            "mirroredParent": geometry(resolve(parent * child)!),
            "constantW": geometry(resolve(constantW)!),
            "negativeConstantW": geometry(resolve(negativeW)!),
            "flatCaptureProjectiveOutput": geometry(resolve(projective, capture: rotated)!),
            "projective": geometry(resolve(projective)!),
            "tinyProjective": geometry(resolve(tinyProjective)!),
            "project": geometry(resolve(rotated, kind: .project)!),
            "fullscreen": geometry(resolve(rotated, kind: .fullscreen)!),
            "members": geometry(resolve(rotated, members: [9001])!),
            "emptyAuthored": geometry(resolve(rotated, members: [], authored: [665, 151])!),
            "emptyNoAuthored": geometry(resolve(rotated, members: [])!),
            "materialSource": geometry(resolve(rotated, authored: [665, 151], material: true)!),
            "collapsedAxis": geometry(resolve(SceneMatrix.scale(SIMD3<Float>(0, 0.25, 1)))!),
            "invalid": invalid,
        ]
    }

    static func vector(_ value: SIMD2<Float>) -> [Float] { [value.x, value.y] }

    static func geometry(_ value: SceneCaptureGeometry) -> [String: Any] {
        ["sourceUV": [vector(value.sourceUV.origin), vector(value.sourceUV.xAxis),
                      vector(value.sourceUV.yAxis)],
         "outputMVP": matrix(value.outputMVP),
         "pixelSize": [value.pixelSize.width, value.pixelSize.height]]
    }

    static func matrix(_ value: simd_float4x4) -> [Float] {
        [value.columns.0, value.columns.1, value.columns.2, value.columns.3]
            .flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }
}
'''


class SceneCaptureGeometryTests(unittest.TestCase):
    def test_same_pixel_source_accepts_affine_rotation_nonuniform_and_offscreen_maps(self) -> None:
        self.assertEqual(self.result["samePixelSource"]["accepted"], dict.fromkeys([
            "identity", "quarterTurnNonuniform", "negativeConstantW", "rotationMirroring",
            "offscreen", "collapsedAffine"], True))

    def test_same_pixel_source_rejects_divergent_projection_and_fourth_corner(self) -> None:
        self.assertEqual(self.result["samePixelSource"]["mismatches"], dict.fromkeys([
            "zoom", "translation", "flatCapturePerspectiveOutput", "projectiveEvenAtTinyWVariation",
            "largeOffscreenPixelDisagreement", "fourthCorner"], True))

    def test_same_pixel_source_uses_target_pixels_and_actual_enclosing_raster(self) -> None:
        self.assertEqual(self.result["samePixelSource"]["pixelLimits"], {
            "withinFixedPixelError": True, "largerTargetRejectsSameUVError": True})
        self.assertEqual(self.result["samePixelSource"]["enclosing"], {
            "actualRasterMatches": True, "rawWorldMatrixRejected": True})

    def test_same_pixel_source_rejects_nonfinite_or_overflowing_inputs(self) -> None:
        self.assertEqual(self.result["samePixelSource"]["invalid"], dict.fromkeys([
            "zeroW", "nanMatrix", "infiniteMatrix", "floatClipOverflow", "floatDivisionOverflow",
            "nanSourceUV", "sourceUVCornerOverflow", "zeroViewport", "negativeViewport",
            "nanViewport", "infiniteViewport", "pixelErrorOverflow"], True))

    def test_collapsed_quad_projection_keeps_minimum_pixel_allocation(self) -> None:
        self.assertEqual(self.result["collapsedProjectedSize"], [1, 1])

    def test_solid_authored_local_extent_rounds_up_with_one_pixel_zero_axes(self) -> None:
        self.assertEqual(
            self.result["solidAuthoredExtents"],
            [[64, 1], [1, 64], [1, 1], [64, 1], [64, 4], [33, 5], [1, 1]],
        )

    def test_solid_invalid_explicit_dimensions_are_rejected(self) -> None:
        self.assertEqual(
            self.result["invalidSolidSizesRejected"],
            dict.fromkeys([
                "empty", "oneAxis", "threeAxes", "negativeWidth", "negativeHeight",
                "nanWidth", "nanHeight", "infiniteWidth", "infiniteHeight",
                "negativeInfiniteWidth", "negativeInfiniteHeight",
                "overflowWidth", "overflowHeight", "roundedIntOverflow",
            ], True),
        )

    def test_solid_absent_authored_dimensions_leave_fallback_to_caller(self) -> None:
        self.assertTrue(self.result["absentSolidSizeIsNil"])

    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-capture-geometry-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-capture-geometry"
        subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(LOCAL_SOURCE_FIXTURE),
                str(harness), "-o", str(cls.binary),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_composition_captures_its_projected_source_region(self) -> None:
        self.assertEqual(self.result["localOrigin"], [0.5, 0.5])
        self.assertEqual(self.result["localXAxis"], [0.5, 0])
        self.assertEqual(self.result["localYAxis"], [0, 0.25])
        self.assertEqual(self.result["localSize"], [500, 200])

    def test_composition_preserves_authored_output_transform(self) -> None:
        self.assertEqual(
            self.result["localOutput"],
            [1, 0, 0, 0, 0, 0.5, 0, 0, 0, 0, 1, 0, 0.5, -0.25, 0, 1],
        )

    def test_legacy_composition_member_source_uses_viewport_geometry(self) -> None:
        full = [2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        self.assertEqual(self.result["memberGroup"], {
            "sourceUV": [[0, 0], [1, 0], [0, 1]],
            "outputMVP": full, "pixelSize": [1000, 800]})
        self.assertEqual(self.result["projectWithMemberFlag"], {
            "sourceUV": [[0.5, 0.5], [0.5, 0], [0, 0.25]],
            "outputMVP": self.result["localOutput"], "pixelSize": [500, 200]})

    def test_empty_composition_keeps_parent_transform_on_non_square_viewport(self) -> None:
        self.assertEqual(self.result["parentEmpty"], {
            "sourceUV": [[0.53125, 0.65625], [0, -0.375], [0.0625, 0]],
            "outputMVP": [0, 0.75, 0, 0, -0.125, 0, 0, 0,
                          0, 0, 1, 0, 0.125, 0.0625, 0, 1],
            "pixelSize": [40, 135]})
        self.assertEqual(self.result["parentMembers"], {
            "sourceUV": [[0, 0], [1, 0], [0, 1]],
            "outputMVP": [2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
            "pixelSize": [640, 360]})

    def test_empty_transparent_source_uses_authored_extent_without_changing_projection(self) -> None:
        parent = self.result["parentEmpty"]
        self.assertEqual(self.result["authoredParent"], dict(parent, pixelSize=[2000, 2000]))
        # nil is the readable/copy-background route; it must not take an
        # empty transparent source's authored-size privilege.
        self.assertEqual(self.result["nilSourceWithAuthoredSize"],
                         dict(parent, pixelSize=[135, 40]))
        tilted = self.result["authoredSquare"]
        self.assertEqual(tilted["pixelSize"], [2000, 2000])
        self.assertEqual(tilted["sourceUV"], self.result["replaySource"])
        expected = [1, 0, 0, 0.6, 0, 1, 0, 0, 0, 0, 1, 0, 0.1, -0.2, 0.4, 1]
        for actual, wanted in zip(tilted["outputMVP"], expected, strict=True):
            self.assertAlmostEqual(actual, wanted, places=6)

    def test_invalid_explicit_transparent_extent_is_not_replaced_by_projected_size(self) -> None:
        self.assertEqual(self.result["invalidTransparentSizesRejected"],
                         dict.fromkeys(["zero", "negative", "nan", "infinity",
                                        "empty", "oneAxis", "threeAxes", "finiteIntOverflow",
                                        "greatestFinite", "roundedIntOverflow"], True))

    def test_material_source_preserves_authored_extent_and_projective_world_output(self) -> None:
        result = self.result["materialSource"]
        self.assertEqual(result["pixelSize"], [665, 151])
        self.assertEqual(result["sourceUV"], [[0, 0], [1, 0], [0, 1]])
        self.assertEqual(result["outputMVP"], self.result["authoredSquare"]["outputMVP"])
        self.assertNotEqual(result["sourceUV"], self.result["replaySource"])

    def test_only_authored_local_output_retains_its_world_card(self) -> None:
        self.assertEqual(self.result["localWorldCard"], self.result["expectedWorldCard"])
        self.assertEqual(self.result["localGroupWorldCard"], self.result["expectedWorldCard"])
        self.assertTrue(self.result["fullscreenWorldUnknown"])
        self.assertTrue(self.result["legacyGroupWorldUnknown"])

    def test_material_source_rejects_project_members_and_invalid_explicit_extent(self) -> None:
        for key in ("materialSourceProjectRejected", "materialSourceMemberRejected",
                    "materialSourceMissingExtentRejected"):
            self.assertTrue(self.result[key], key)
        self.assertEqual(self.result["materialSourceInvalidExtentsRejected"],
                         self.result["invalidTransparentSizesRejected"])

    def test_perspective_replay_preserves_flat_source_and_extent(self) -> None:
        self.assertEqual(self.result["replaySource"], [[0.5, 0.5], [0.5, 0], [0, 0.25]])
        self.assertEqual(self.result["replaySize"], [500, 200])

    def test_all_four_output_corners_retain_projective_division(self) -> None:
        expected = [[-0.4 / 0.7, 0.3 / 0.7], [0.6 / 1.3, 0.3 / 1.3],
                    [0.6 / 1.3, -0.7 / 1.3], [-0.4 / 0.7, -0.7 / 0.7]]
        for actual, target in zip(self.result["replayCorners"], expected, strict=True):
            for value, wanted in zip(actual, target, strict=True):
                self.assertAlmostEqual(value, wanted, places=6)
        corners = self.result["replayCorners"]
        self.assertGreater(abs(corners[0][1] + corners[2][1] - corners[1][1] - corners[3][1]), 0.5)

    def test_cursor_inverts_output_instead_of_flat_capture(self) -> None:
        for actual, expected in zip(self.result["replayCursorPoints"],
                                    [[-0.3, 0.2], [0, 0], [0.4, -0.1]], strict=True):
            for value, wanted in zip(actual, expected, strict=True):
                self.assertAlmostEqual(value, wanted, places=6)

    def test_fullscreen_uses_identity_viewport_geometry(self) -> None:
        self.assertEqual(self.result["fullscreenOrigin"], [0, 0])
        self.assertEqual(self.result["fullscreenAxes"], [1, 0, 0, 1])
        self.assertEqual(self.result["fullscreenSize"], [1000, 800])
        full_target = [2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        self.assertEqual(self.result["fullscreenOutput"], full_target)

    def test_fullscreen_effect_projection_uses_canonical_output_geometry(self) -> None:
        self.assertTrue(self.result["fullscreenCanonicalProjectionInvertible"])

    def test_singular_composition_effect_projection_remains_rejected(self) -> None:
        self.assertTrue(self.result["singularCompositionProjectionRejected"])

    def test_project_uses_wallpaper_aligned_projected_geometry(self) -> None:
        self.assertEqual(self.result["projectOrigin"], [0.5, 0.5])
        self.assertEqual(self.result["projectXAxis"], [0.5, 0])
        self.assertEqual(self.result["projectYAxis"], [0, 0.25])
        self.assertEqual(self.result["projectSize"], [500, 200])
        self.assertEqual(self.result["projectOutput"], self.result["localOutput"])

    def test_background_copy_keeps_local_axes_under_positive_and_negative_quarter_turns(self) -> None:
        cases = self.result["backgroundCopyAxes"]
        self.assertEqual(cases["quarterTurn"]["pixelSize"], [400, 100])
        self.assertEqual(cases["renamedInput"], cases["quarterTurn"])
        self.assertEqual(cases["reverseTurn"]["pixelSize"], [400, 100])
        self.assertEqual(cases["quarterTurn"]["sourceUV"],
                         [[0.4375, 0.75], [0, -0.5], [0.125, 0]])
        self.assertEqual(cases["reverseTurn"]["sourceUV"],
                         [[0.5625, 0.25], [0, 0.5], [-0.125, 0]])

    def test_background_copy_measures_arbitrary_angle_and_non_square_viewport_vectors(self) -> None:
        cases = self.result["backgroundCopyAxes"]
        self.assertEqual(cases["arbitraryAngle"]["pixelSize"], [250, 63])
        self.assertEqual(cases["nonSquareViewport"]["pixelSize"], [231, 69])
        self.assertEqual(cases["arbitraryAngle"]["sourceUV"],
                         cases["nonSquareViewport"]["sourceUV"])
        self.assertEqual(cases["arbitraryAngle"]["outputMVP"],
                         cases["nonSquareViewport"]["outputMVP"])

    def test_background_copy_preserves_mirrored_nonuniform_parent_axis_lengths(self) -> None:
        result = self.result["backgroundCopyAxes"]["mirroredParent"]
        self.assertEqual(result["pixelSize"], [124, 78])
        self.assertEqual(result["sourceUV"],
                         [[0.4921875, 0.61328125], [-0.140625, -0.0625],
                          [-0.09375, 0.0234375]])

    def test_background_copy_divides_by_constant_nonunit_homogeneous_w(self) -> None:
        cases = self.result["backgroundCopyAxes"]
        for name in ("constantW", "negativeConstantW"):
            self.assertEqual(cases[name]["pixelSize"], [200, 50], name)
        self.assertEqual(cases["constantW"]["outputMVP"][-1], 2)
        self.assertEqual(cases["negativeConstantW"]["outputMVP"][-1], -2)
        self.assertEqual(cases["flatCaptureProjectiveOutput"]["pixelSize"], [400, 100])
        self.assertEqual(cases["flatCaptureProjectiveOutput"]["sourceUV"],
                         cases["quarterTurn"]["sourceUV"])
        self.assertEqual(cases["flatCaptureProjectiveOutput"]["outputMVP"],
                         cases["projective"]["outputMVP"])

    def test_background_copy_does_not_change_projective_or_other_source_routes(self) -> None:
        cases = self.result["backgroundCopyAxes"]
        self.assertEqual(cases["projective"]["pixelSize"], [414, 572])
        # Float corner division may round the subpixel Y expansion away.
        self.assertIn(cases["tinyProjective"]["pixelSize"], ([101, 400], [101, 401]))
        self.assertEqual(cases["project"]["pixelSize"], [100, 400])
        for name in ("fullscreen", "members"):
            self.assertEqual(cases[name]["pixelSize"], [800, 800], name)
            self.assertEqual(cases[name]["sourceUV"], [[0, 0], [1, 0], [0, 1]], name)
        for name in ("emptyAuthored", "materialSource"):
            self.assertEqual(cases[name]["pixelSize"], [665, 151], name)
        self.assertEqual(cases["emptyNoAuthored"]["pixelSize"], [100, 400])

    def test_background_copy_rejects_invalid_and_overflowing_dimensions_locally(self) -> None:
        cases = self.result["backgroundCopyAxes"]
        self.assertEqual(cases["invalid"], dict.fromkeys([
            "nonfiniteAxis", "zeroW", "finiteIntOverflow", "viewportProductOverflow",
            "zeroViewport", "nonfiniteViewport"], True))
        self.assertEqual(cases["collapsedAxis"]["pixelSize"], [1, 100])

    def test_degenerate_viewport_is_rejected(self) -> None:
        self.assertTrue(self.result["invalidIsNil"])

    def test_projected_pixel_size_preserves_non_square_surface_extent(self) -> None:
        self.assertEqual(self.result["projectedSize"], [750, 100])

    def test_only_axis_aligned_full_viewport_quads_prove_coverage(self) -> None:
        self.assertTrue(self.result["fullCoverage"])
        self.assertFalse(self.result["sparseCoverage"])
        self.assertFalse(self.result["rotatedCoverage"])

    def test_layer_effect_source_extent_prefers_semantic_sizes(self) -> None:
        self.assertEqual(self.result["authoredExtent"], [1920, 1080])
        self.assertEqual(self.result["publishedExtent"], [861, 1366])
        self.assertEqual(self.result["mappedExtent"], [1415, 2047])

    def test_invalid_explicit_extent_does_not_fall_back_to_allocation_size(self) -> None:
        self.assertTrue(self.result["invalidAuthoredExtentIsNil"])

    def test_local_composition_uses_authored_extent_and_world_output_once(self) -> None:
        result = self.result["compositionLocalSource"]
        expected = {"pixelSize": [80, 40], "sourceUV": [[0, 0], [1, 0], [0, 1]],
                    "outputMVP": [0, 0.75, 0, 0, -0.125, 0, 0, 0,
                                  0, 0, 1, 0, 0.125, 0.0625, 0.375, 1]}
        self.assertEqual(result["local"], expected)
        self.assertEqual(result["otherViewport"], expected)
        self.assertEqual(result["fractionalExtent"], [80.25, 40.5])
        self.assert_float_tree(result["worldOutputOncePoints"],
                               [[[0.09375, -0.125], [0.0625, 0.0625], [0.125, -0.3125]]] * 3)

    def test_local_source_recovers_affine_and_projective_xyw(self) -> None:
        result = self.result["compositionLocalSource"]
        self.assert_float_tree(result["affineWorldToSourcePoints"],
                               [[0, 0, 0, 1], [1, 0, 0, 1], [0, 1, 0, 1],
                                [-0.5, 0.5, 0, 1], [0, 1.25, 0, 1], [1.5, 0, 0, 1]])
        expected = [[0, 0, 0, 1], [16 / 37, -8 / 37, 0, 32 / 37],
                    [-1.6, 1.6, 0, 1.6]]
        self.assert_float_tree(result["projectiveXYWPoints"], expected)
        self.assert_float_tree(result["negativeScalePoint"], [0.5, -0.5, 0, 1])

    def test_local_source_raster_keeps_xy_and_discards_unrelated_child_depth(self) -> None:
        result = self.result["compositionLocalSource"]
        self.assert_float_tree(result["childRasterMatrices"],
                               [[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, -0.5, 0.5, 0, 1]] * 3)
        expected = [[-1, 0, 0, 1], [0, 0, 0, 1], [0, 1, 0, 1], [-1, 1, 0, 1]]
        self.assert_float_tree(result["childRasterCorners"], [expected] * 3)
        self.assertTrue(result["singularDepthStillValidXYW"])

    def assert_float_tree(self, actual, expected) -> None:
        # Fixed Float inverse/projection tolerance, set before the first run.
        if isinstance(expected, list):
            self.assertEqual(len(actual), len(expected))
            for value, target in zip(actual, expected, strict=True):
                self.assert_float_tree(value, target)
        else:
            self.assertAlmostEqual(actual, expected, delta=1e-6)

    def test_local_source_rejects_missing_extent_invalid_extent_and_singular_xyw(self) -> None:
        result = self.result["compositionLocalSource"]
        self.assertTrue(result["absentExtentRejected"])
        self.assertEqual(result["invalidExtentsRejected"], dict.fromkeys([
            "empty", "oneAxis", "extraAxis", "zero", "negative", "nan", "infinity",
            "finiteIntOverflow", "greatestFinite", "roundedIntOverflow"], True))
        self.assertEqual(result["invalidMatricesRejected"], dict.fromkeys([
            "collapsedX", "dependentXY", "zeroHomogeneousRow", "nonfiniteXY", "nonfiniteW",
            "rasterScaleOverflow"], True))

    def test_local_source_checks_finiteness_after_raster_scale(self) -> None:
        result = self.result["compositionLocalSource"]
        self.assertTrue(result["invalidMatricesRejected"]["rasterScaleOverflow"])
        finite_neighbor = result["finiteSubnormalRasterScale"]
        self.assertGreater(finite_neighbor, 0)
        self.assertAlmostEqual(finite_neighbor / 2.5e38, 1, delta=1e-6)

    def test_local_source_extent_does_not_change_legacy_or_other_utility_routes(self) -> None:
        result = self.result["compositionLocalSource"]
        full = {"sourceUV": [[0, 0], [1, 0], [0, 1]],
                "outputMVP": [2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                "pixelSize": [640, 360]}
        self.assertEqual(result["legacyMembers"], full)
        self.assertEqual(result["fullscreen"], full)
        projected = {"sourceUV": [[0.53125, 0.65625], [0, -0.375], [0.0625, 0]],
                     "outputMVP": result["rootMVP"], "pixelSize": [40, 135]}
        self.assertEqual(result["nilMembers"], dict(projected, pixelSize=[135, 40]))
        self.assertEqual(result["project"], projected)
        self.assertEqual(result["empty"], dict(projected, pixelSize=[80, 40]))


if __name__ == "__main__":
    unittest.main()
