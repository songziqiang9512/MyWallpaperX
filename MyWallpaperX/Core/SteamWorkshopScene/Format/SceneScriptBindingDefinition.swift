import Foundation

/// 作者挂在 layer 顶层属性上的 SceneScript 声明。
///
/// 解析阶段只保留原始脚本及其输入，不判断脚本语义，也不执行未知脚本。
nonisolated struct SceneScriptBindingDefinition: Codable, Equatable, Sendable {
    let host: String
    let source: String
    let properties: [String: SceneJSONValue]
    let authoredValue: SceneJSONValue?

    nonisolated static func parseLayerProperties(
        in root: [String: Any]
    ) -> [SceneScriptBindingDefinition] {
        root.keys.sorted().compactMap { host in
            guard let wrapper = root[host] as? [String: Any],
                  let source = wrapper["script"] as? String,
                  let properties = parseProperties(wrapper["scriptproperties"]) else {
                return nil
            }
            return SceneScriptBindingDefinition(
                host: host,
                source: source,
                properties: properties,
                authoredValue: wrapper["value"].flatMap(SceneJSONValue.init(jsonObject:))
            )
        }
    }

    nonisolated private static func parseProperties(
        _ rawValue: Any?
    ) -> [String: SceneJSONValue]? {
        guard let rawValue else { return [:] }
        guard let object = rawValue as? [String: Any] else { return nil }

        var properties: [String: SceneJSONValue] = [:]
        for (key, value) in object {
            guard let parsed = SceneJSONValue(jsonObject: value) else { return nil }
            properties[key] = parsed
        }
        return properties
    }
}
