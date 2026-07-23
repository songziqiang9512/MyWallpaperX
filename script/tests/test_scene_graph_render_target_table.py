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
    SOURCE_ROOT / "SceneJSONValue.swift",
    SOURCE_ROOT / "SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "SceneGraphRenderTargetTable.swift",
    SOURCE_ROOT / "SceneGraphCommandRuntime.swift",
]


HARNESS = r'''
import Foundation
import Metal

struct SceneAuthoredEffectExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias TargetPlan = SceneGraphRenderTargetPlan
    typealias TargetTable = SceneGraphRenderTargetTable

    static func identity(
        _ kind: Graph.TextureKind,
        layerID: Int = 10,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func logicalTarget(
        _ identity: Graph.TextureIdentity,
        width: Int,
        height: Int,
        format: TargetPlan.TextureFormat = .rgbaBackbuffer,
        firstWrite: Int,
        lastWrite: Int,
        firstRead: Int?,
        lastRead: Int?
    ) -> TargetPlan.LogicalTarget {
        .init(
            identity: identity,
            extent: .init(width: width, height: height),
            format: format,
            lifetime: .init(
                firstWriteNodeIndex: firstWrite,
                lastWriteNodeIndex: lastWrite,
                firstReadNodeIndex: firstRead,
                lastReadNodeIndex: lastRead
            )
        )
    }

    static func failure(
        _ result: Result<TargetTable, TargetTable.Failure>
    ) -> String {
        switch result {
        case .success:
            return "success"
        case .failure(let reason):
            return reason.rawValue
        }
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalUnavailable\":true}")
            return
        }

        let effect = Graph.EffectKey(
            layerID: 10,
            effectIndex: 2,
            descriptorID: "10#effect#2"
        )
        let input = identity(.layerSource)
        let output = identity(.effectOutput, effect: effect)
        let quarterA = identity(.framebuffer, effect: effect, name: "quarterA")
        let quarterB = identity(.framebuffer, effect: effect, name: "quarterB")
        let plan = TargetPlan(
            layerID: 10,
            input: input,
            output: output,
            inputExtent: .init(width: 9, height: 7),
            logicalTargets: [
                logicalTarget(
                    quarterA, width: 2, height: 1,
                    format: .rgba8888,
                    firstWrite: 0, lastWrite: 2, firstRead: 1, lastRead: 3
                ),
                logicalTarget(
                    quarterB, width: 2, height: 1,
                    format: .rgba8888,
                    firstWrite: 1, lastWrite: 1, firstRead: 2, lastRead: 2
                ),
            ]
        )

        let exactBudget = 520
        guard case .success(let table) = TargetTable.make(
            plan: plan,
            device: device,
            byteBudget: exactBudget
        ), case .success(let secondTable) = TargetTable.make(
            plan: plan,
            device: device,
            byteBudget: exactBudget
        ), let quarterATexture = table.texture(for: quarterA),
        let quarterBTexture = table.texture(for: quarterB) else {
            fatalError("valid table allocation failed")
        }

        let textures = [
            table.inputTexture,
            quarterATexture,
            quarterBTexture,
            table.outputTexture,
        ]
        let objectIDs = Set(textures.map(ObjectIdentifier.init))
        let secondObjectIDs = Set([
            secondTable.inputTexture,
            secondTable.texture(for: quarterA)!,
            secondTable.texture(for: quarterB)!,
            secondTable.outputTexture,
        ].map(ObjectIdentifier.init))
        let otherEffect = Graph.EffectKey(
            layerID: 10,
            effectIndex: 3,
            descriptorID: "10#effect#3"
        )
        let unknown = identity(.framebuffer, effect: otherEffect, name: "quarterA")
        let copyPlan = TargetPlan(
            layerID: plan.layerID,
            input: input,
            output: output,
            inputExtent: .init(width: 2, height: 2),
            logicalTargets: [
                logicalTarget(
                    quarterA, width: 2, height: 2,
                    firstWrite: 0, lastWrite: 0, firstRead: 2, lastRead: 2
                ),
                logicalTarget(
                    quarterB, width: 2, height: 2,
                    firstWrite: 1, lastWrite: 2, firstRead: nil, lastRead: nil
                ),
            ],
            commands: [
                .init(nodeIndex: 2, kind: .copy, source: quarterA, target: quarterB),
            ]
        )
        guard case .success(let copyTable) = TargetTable.make(
            plan: copyPlan,
            device: device,
            byteBudget: 128
        ), var copyRuntime = copyTable.makeCommandRuntime(),
        let queue = device.makeCommandQueue(),
        let upload = device.makeBuffer(length: 16, options: .storageModeShared),
        let readback = device.makeBuffer(length: 16, options: .storageModeShared),
        let copyCommandBuffer = queue.makeCommandBuffer(),
        let uploadEncoder = copyCommandBuffer.makeBlitCommandEncoder(),
        let copySource = copyRuntime.texture(for: quarterA),
        let copyTarget = copyRuntime.texture(for: quarterB) else {
            fatalError("command runtime setup failed")
        }
        let pattern = Array(0..<16).map(UInt8.init)
        pattern.withUnsafeBytes { bytes in
            memcpy(upload.contents(), bytes.baseAddress!, bytes.count)
        }
        uploadEncoder.copy(
            from: upload,
            sourceOffset: 0,
            sourceBytesPerRow: 8,
            sourceBytesPerImage: 16,
            sourceSize: .init(width: 2, height: 2, depth: 1),
            to: copySource,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        uploadEncoder.endEncoding()
        let wrongOrderFailure: String
        switch copyRuntime.encodeCommand(at: 99, commandBuffer: copyCommandBuffer) {
        case .success:
            wrongOrderFailure = "success"
        case .failure(let reason):
            wrongOrderFailure = reason.rawValue
        }
        let copyResult = copyRuntime.encodeCommand(
            at: 2,
            commandBuffer: copyCommandBuffer
        )
        guard case .success = copyResult,
              let readbackEncoder = copyCommandBuffer.makeBlitCommandEncoder() else {
            fatalError("copy command failed")
        }
        readbackEncoder.copy(
            from: copyTarget,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: 2, height: 2, depth: 1),
            to: readback,
            destinationOffset: 0,
            destinationBytesPerRow: 8,
            destinationBytesPerImage: 16
        )
        readbackEncoder.endEncoding()
        copyCommandBuffer.commit()
        copyCommandBuffer.waitUntilCompleted()
        let copiedBytes = Array(
            UnsafeBufferPointer(
                start: readback.contents().assumingMemoryBound(to: UInt8.self),
                count: 16
            )
        )

        let swapPlan = TargetPlan(
            layerID: copyPlan.layerID,
            input: copyPlan.input,
            output: copyPlan.output,
            inputExtent: copyPlan.inputExtent,
            logicalTargets: copyPlan.logicalTargets,
            commands: [
                .init(nodeIndex: 3, kind: .swap, source: quarterA, target: quarterB),
            ]
        )
        guard case .success(let swapTable) = TargetTable.make(
            plan: swapPlan,
            device: device,
            byteBudget: 128
        ), var swapRuntime = swapTable.makeCommandRuntime(),
        let swapSourceBefore = swapRuntime.texture(for: quarterA),
        let swapTargetBefore = swapRuntime.texture(for: quarterB),
        let swapCommandBuffer = queue.makeCommandBuffer() else {
            fatalError("swap command setup failed")
        }
        let swapResult = swapRuntime.encodeCommand(
            at: 3,
            commandBuffer: swapCommandBuffer
        )
        guard case .success = swapResult else {
            fatalError("swap command failed")
        }
        let swapBindingsExchanged =
            swapRuntime.texture(for: quarterA) === swapTargetBefore
                && swapRuntime.texture(for: quarterB) === swapSourceBefore

        let incompatiblePlan = TargetPlan(
            layerID: copyPlan.layerID,
            input: copyPlan.input,
            output: copyPlan.output,
            inputExtent: copyPlan.inputExtent,
            logicalTargets: [
                copyPlan.logicalTargets[0],
                logicalTarget(
                    quarterB, width: 2, height: 2,
                    format: .rgba8888,
                    firstWrite: 1, lastWrite: 2, firstRead: nil, lastRead: nil
                ),
            ],
            commands: copyPlan.commands
        )
        guard case .success(let incompatibleTable) = TargetTable.make(
            plan: incompatiblePlan,
            device: device,
            byteBudget: 128
        ), var incompatibleRuntime = incompatibleTable.makeCommandRuntime(),
        let incompatibleCommandBuffer = queue.makeCommandBuffer() else {
            fatalError("incompatible command setup failed")
        }
        let incompatibleFailure: String
        switch incompatibleRuntime.encodeCommand(
            at: 2,
            commandBuffer: incompatibleCommandBuffer
        ) {
        case .success:
            incompatibleFailure = "success"
        case .failure(let reason):
            incompatibleFailure = reason.rawValue
        }

        let duplicatePlan = TargetPlan(
            layerID: plan.layerID,
            input: input,
            output: output,
            inputExtent: plan.inputExtent,
            logicalTargets: [
                plan.logicalTargets[0],
                plan.logicalTargets[0],
            ]
        )
        let overflowPlan = TargetPlan(
            layerID: plan.layerID,
            input: input,
            output: output,
            inputExtent: .init(width: Int.max, height: 2),
            logicalTargets: []
        )
        let wrongEffect = Graph.EffectKey(
            layerID: 11,
            effectIndex: 2,
            descriptorID: "11#effect#2"
        )
        let invalidIdentityPlan = TargetPlan(
            layerID: plan.layerID,
            input: input,
            output: output,
            inputExtent: plan.inputExtent,
            logicalTargets: [
                logicalTarget(
                    identity(.framebuffer, effect: wrongEffect, name: "foreign"),
                    width: 2, height: 1,
                    firstWrite: 0, lastWrite: 0, firstRead: nil, lastRead: nil
                ),
            ]
        )
        let whitespaceNamePlan = TargetPlan(
            layerID: plan.layerID,
            input: input,
            output: output,
            inputExtent: plan.inputExtent,
            logicalTargets: [
                logicalTarget(
                    identity(.framebuffer, effect: effect, name: "  \t"),
                    width: 2, height: 1,
                    firstWrite: 0, lastWrite: 0, firstRead: nil, lastRead: nil
                ),
            ]
        )

        let result: [String: Any] = [
            "metalUnavailable": false,
            "residentCount": table.residentTextureCount,
            "residentBytes": table.residentByteCost,
            "inputSize": [table.inputTexture.width, table.inputTexture.height],
            "outputSize": [table.outputTexture.width, table.outputTexture.height],
            "quarterASize": [quarterATexture.width, quarterATexture.height],
            "quarterBSize": [quarterBTexture.width, quarterBTexture.height],
            "identityMappingComplete": table.texture(for: input) === table.inputTexture
                && table.texture(for: output) === table.outputTexture,
            "unknownIdentityIsNil": table.texture(for: unknown) == nil,
            "allResourcesDistinct": objectIDs.count == textures.count,
            "separateAllocationsDistinct": objectIDs.isDisjoint(with: secondObjectIDs),
            "inputOutputFormat": table.inputTexture.pixelFormat == .bgra8Unorm
                && table.outputTexture.pixelFormat == .bgra8Unorm,
            "framebufferFormats": quarterATexture.pixelFormat == .rgba8Unorm
                && quarterBTexture.pixelFormat == .rgba8Unorm,
            "textureContract": textures.allSatisfy {
                $0.storageMode == .private
                    && $0.usage.contains(.renderTarget)
                    && $0.usage.contains(.shaderRead)
            },
            "copyBytesMatch": copiedBytes == pattern,
            "copyRuntimeComplete": copyRuntime.isComplete
                && copyRuntime.remainingCommandCount == 0,
            "wrongOrderFailure": wrongOrderFailure,
            "swapBindingsExchanged": swapBindingsExchanged,
            "swapRuntimeComplete": swapRuntime.isComplete,
            "incompatibleCommandFailure": incompatibleFailure,
            "budgetFailure": failure(TargetTable.make(
                plan: plan, device: device, byteBudget: exactBudget - 1
            )),
            "negativeBudgetFailure": failure(TargetTable.make(
                plan: plan, device: device, byteBudget: -1
            )),
            "duplicateFailure": failure(TargetTable.make(
                plan: duplicatePlan, device: device, byteBudget: exactBudget
            )),
            "overflowFailure": failure(TargetTable.make(
                plan: overflowPlan, device: device, byteBudget: Int.max
            )),
            "invalidIdentityFailure": failure(TargetTable.make(
                plan: invalidIdentityPlan, device: device, byteBudget: exactBudget
            )),
            "whitespaceNameFailure": failure(TargetTable.make(
                plan: whitespaceNamePlan, device: device, byteBudget: exactBudget
            )),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneGraphRenderTargetTableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-rt-table-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-rt-table"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework",
                "Metal",
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_allocates_every_logical_identity_without_aliasing(self) -> None:
        self.assertEqual(self.result["residentCount"], 4)
        self.assertTrue(self.result["identityMappingComplete"])
        self.assertTrue(self.result["unknownIdentityIsNil"])
        self.assertTrue(self.result["allResourcesDistinct"])
        self.assertTrue(self.result["separateAllocationsDistinct"])

    def test_preserves_input_output_and_scaled_target_extents(self) -> None:
        self.assertEqual(self.result["inputSize"], [9, 7])
        self.assertEqual(self.result["outputSize"], [9, 7])
        self.assertEqual(self.result["quarterASize"], [2, 1])
        self.assertEqual(self.result["quarterBSize"], [2, 1])

    def test_reports_exact_resident_cost_and_texture_contract(self) -> None:
        self.assertEqual(self.result["residentBytes"], 520)
        self.assertTrue(self.result["inputOutputFormat"])
        self.assertTrue(self.result["framebufferFormats"])
        self.assertTrue(self.result["textureContract"])

    def test_copy_blits_bytes_and_swap_exchanges_logical_bindings(self) -> None:
        self.assertTrue(self.result["copyBytesMatch"])
        self.assertTrue(self.result["copyRuntimeComplete"])
        self.assertEqual(self.result["wrongOrderFailure"], "commandOrderMismatch")
        self.assertTrue(self.result["swapBindingsExchanged"])
        self.assertTrue(self.result["swapRuntimeComplete"])
        self.assertEqual(
            self.result["incompatibleCommandFailure"],
            "incompatibleTextures",
        )

    def test_refuses_the_whole_allocation_before_exceeding_budget(self) -> None:
        self.assertEqual(self.result["budgetFailure"], "byteBudgetExceeded")
        self.assertEqual(self.result["negativeBudgetFailure"], "invalidByteBudget")

    def test_rejects_invalid_or_overflowing_resource_sets(self) -> None:
        self.assertEqual(self.result["duplicateFailure"], "invalidPlan")
        self.assertEqual(self.result["overflowFailure"], "byteCostOverflow")
        self.assertEqual(self.result["invalidIdentityFailure"], "invalidPlan")
        self.assertEqual(self.result["whitespaceNameFailure"], "invalidPlan")


if __name__ == "__main__":
    unittest.main()
