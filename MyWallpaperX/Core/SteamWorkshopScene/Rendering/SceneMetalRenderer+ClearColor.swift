import Metal

extension SceneMetalRenderer {
    var sceneClearColor: MTLClearColor {
        let color = renderDescriptor.camera.clearColor
        let red = Double(color.count > 0 ? color[0] : 0.7)
        let green = Double(color.count > 1 ? color[1] : 0.7)
        let blue = Double(color.count > 2 ? color[2] : 0.7)
        return MTLClearColorMake(red, green, blue, 1)
    }
}
