import simd

/// Projects MDAT bone-local attachment transforms through the exact animated
/// bone worlds used by skinning. Puppet model coordinates use the opposite Y
/// axis from Scene layer coordinates, so the same basis conjugation as the
/// static bind-frame reader is applied after composition.
nonisolated enum ScenePuppetAttachmentPoseProjection {
    nonisolated static func frames(
        attachments: [SceneMdlPuppetAttachment],
        boneWorldMatrices: [simd_float4x4]
    ) -> [String: simd_float4x4]? {
        var result: [String: simd_float4x4] = [:]
        result.reserveCapacity(attachments.count)
        for attachment in attachments {
            guard boneWorldMatrices.indices.contains(attachment.boneIndex),
                  attachment.modelLocalFrameColumnMajor.count == 16 else {
                return nil
            }
            let local = matrix(
                columnMajor: attachment.modelLocalFrameColumnMajor
            )
            let modelFrame = boneWorldMatrices[attachment.boneIndex] * local
            let sceneFrame = sceneFrame(fromModelFrame: modelFrame)
            guard isFinite(sceneFrame),
                  result.updateValue(sceneFrame, forKey: attachment.name) == nil else {
                return nil
            }
        }
        return result
    }

    private nonisolated static func matrix(
        columnMajor values: [Float]
    ) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(values[0], values[1], values[2], values[3]),
            SIMD4(values[4], values[5], values[6], values[7]),
            SIMD4(values[8], values[9], values[10], values[11]),
            SIMD4(values[12], values[13], values[14], values[15])
        ))
    }

    private nonisolated static func sceneFrame(
        fromModelFrame modelFrame: simd_float4x4
    ) -> simd_float4x4 {
        let yAxis = simd_float4x4(diagonal: SIMD4<Float>(1, -1, 1, 1))
        return yAxis * modelFrame * yAxis
    }

    private nonisolated static func isFinite(_ matrix: simd_float4x4) -> Bool {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
            .allSatisfy { column in
                column.x.isFinite && column.y.isFinite
                    && column.z.isFinite && column.w.isFinite
            }
    }
}
