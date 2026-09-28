import Foundation

extension SceneScriptValueOwner {
    /// String-specific UTF-8 ABI conversion. Ownership, callbacks, mutation
    /// validation and commit/rollback belong to the shared typed value owner.
    func callString(
        _ input: String, initializing: Bool, expectedGeneration: UInt64,
        frame: inout MWXSceneQuickJSFrameInput,
        scriptPropertiesJSON: String, userPropertiesJSON: String,
        didInitialize: inout UInt32, diagnostic: inout [CChar]
    ) -> (MWXSceneQuickJSResult, SceneDynamicValue) {
        var output = [CChar](repeating: 0, count: 65_537)
        var length = 0
        let result = input.withCString { inputPointer in
            scriptPropertiesJSON.withCString { properties in
                userPropertiesJSON.withCString { userProperties in
                    if initializing {
                        mwx_scene_quickjs_owner_initialize_string(
                            handle, expectedGeneration, inputPointer, input.utf8.count,
                            &frame, properties, scriptPropertiesJSON.utf8.count,
                            userProperties, userPropertiesJSON.utf8.count,
                            &output, output.count, &length, &didInitialize,
                            &diagnostic, diagnostic.count
                        )
                    } else {
                        mwx_scene_quickjs_owner_update_string(
                            handle, expectedGeneration, inputPointer, input.utf8.count,
                            &frame, properties, scriptPropertiesJSON.utf8.count,
                            userProperties, userPropertiesJSON.utf8.count,
                            &output, output.count, &length,
                            &diagnostic, diagnostic.count
                        )
                    }
                }
            }
        }
        guard result == MWX_SCENE_QUICKJS_OK else { return (result, .string("")) }
        guard length <= 65_536 else { return (MWX_SCENE_QUICKJS_BAD_RETURN, .string("")) }
        return (result, .string(String(decoding: output.prefix(length).map {
            UInt8(bitPattern: $0)
        }, as: UTF8.self)))
    }
}
