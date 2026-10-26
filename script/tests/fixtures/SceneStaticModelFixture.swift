import simd

/// Synthetic, valid geometry for rendering tests whose input is not an MDL.
/// Reader-to-upload coverage uses actual bytes through SceneMdlStaticModelReader.
enum SceneStaticModelFixture {
    static func model(
        vertices: [SceneMdlStaticModel.Vertex], indices: [UInt32]
    ) -> SceneMdlStaticModel {
        SceneMdlStaticModel(
            version: "MDLV0023", headerFormat: 15, vertexFormat: 15,
            vertexStride: 48, indexElementSize: 4,
            materialPath: "materials/fixture/model.json",
            bounds: .init(minimum: [-1_000_000, -1_000_000, -1_000_000],
                          maximum: [1_000_000, 1_000_000, 1_000_000]),
            vertices: vertices, indices: indices
        )
    }
}
