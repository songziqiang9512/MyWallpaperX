import Foundation

// Leaf fixture for tests that intentionally do not execute user resolution.
// Startup scalar resolution is exercised with the real owner in the PBR test.
enum SceneUserPropertyPathComponent: Hashable {
    case key(String), index(Int)
}
struct SceneUserPropertyPath: Hashable {
    let components: [SceneUserPropertyPathComponent]
}
struct SceneUserPropertyResolution {
    let root: [String: Any]
    var startupValuePaths: Set<SceneUserPropertyPath> = []
}
