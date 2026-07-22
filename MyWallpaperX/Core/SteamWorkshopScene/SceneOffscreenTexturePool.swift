import Metal

final class SceneOffscreenTexturePool {
    struct Pair {
        let primary: MTLTexture
        let secondary: MTLTexture
        let tertiary: MTLTexture
    }

    struct StandardBlurTargets {
        let previousFull: MTLTexture
        let outputFull: MTLTexture
        let quarterA: MTLTexture
        let quarterB: MTLTexture
    }

    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private enum Allocation {
        case pair(Pair)
        case standardBlur(StandardBlurTargets)
    }

    private struct Entry {
        let allocation: Allocation
        let byteCost: Int
        var lastAccess: UInt64
    }

    private let maxDimension: Int
    private let byteBudget: Int
    private var cachedAllocations: [String: Entry] = [:]
    private var cachedByteCost = 0
    private var accessCounter: UInt64 = 0

    init(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        maxDimension: Int = 2048,
        byteBudget: Int = 96 * 1_024 * 1_024
    ) {
        self.device = device
        self.pixelFormat = pixelFormat
        self.maxDimension = maxDimension
        self.byteBudget = max(byteBudget, 1)
    }

    func textures(for sourceTexture: MTLTexture) -> Pair? {
        textures(width: sourceTexture.width, height: sourceTexture.height)
    }

    func textures(width requestedWidth: Int, height requestedHeight: Int) -> Pair? {
        let (width, height) = limitedDimensions(width: requestedWidth, height: requestedHeight)
        let key = "pair:\(width)x\(height)"
        accessCounter &+= 1
        if var cached = cachedAllocations[key], case .pair(let pair) = cached.allocation {
            cached.lastAccess = accessCounter
            cachedAllocations[key] = cached
            return pair
        }

        let byteCost = width * height * 4 * 3
        evictUntilAffordable(byteCost)

        guard let primary = makeTexture(width: width, height: height, label: "SceneOffscreenA \(key)"),
              let secondary = makeTexture(width: width, height: height, label: "SceneOffscreenB \(key)"),
              let tertiary = makeTexture(width: width, height: height, label: "SceneOffscreenC \(key)") else {
            return nil
        }

        let pair = Pair(primary: primary, secondary: secondary, tertiary: tertiary)
        cachedAllocations[key] = Entry(
            allocation: .pair(pair), byteCost: byteCost, lastAccess: accessCounter
        )
        cachedByteCost += byteCost
        return pair
    }

    func standardBlurTargets(
        width requestedWidth: Int,
        height requestedHeight: Int,
        scale: Int
    ) -> StandardBlurTargets? {
        guard scale > 0 else { return nil }
        let (width, height) = limitedDimensions(width: requestedWidth, height: requestedHeight)
        let quarterWidth = max(1, width / scale)
        let quarterHeight = max(1, height / scale)
        let key = "standard-blur:\(width)x\(height):\(quarterWidth)x\(quarterHeight)"
        accessCounter &+= 1
        if var cached = cachedAllocations[key],
           case .standardBlur(let targets) = cached.allocation {
            cached.lastAccess = accessCounter
            cachedAllocations[key] = cached
            return targets
        }

        let byteCost = ((width * height * 2) + (quarterWidth * quarterHeight * 2)) * 4
        guard byteCost <= byteBudget else { return nil }
        evictUntilAffordable(byteCost)
        guard let previous = makeTexture(
            width: width, height: height, label: "SceneStandardBlurPrevious \(key)"
        ), let output = makeTexture(
            width: width, height: height, label: "SceneStandardBlurOutput \(key)"
        ), let quarterA = makeTexture(
            width: quarterWidth, height: quarterHeight, label: "SceneStandardBlurQuarterA \(key)"
        ), let quarterB = makeTexture(
            width: quarterWidth, height: quarterHeight, label: "SceneStandardBlurQuarterB \(key)"
        ) else {
            return nil
        }
        let targets = StandardBlurTargets(
            previousFull: previous,
            outputFull: output,
            quarterA: quarterA,
            quarterB: quarterB
        )
        cachedAllocations[key] = Entry(
            allocation: .standardBlur(targets), byteCost: byteCost, lastAccess: accessCounter
        )
        cachedByteCost += byteCost
        return targets
    }

    private func limitedDimensions(width requestedWidth: Int, height requestedHeight: Int) -> (Int, Int) {
        let sourceWidth = max(1, requestedWidth)
        let sourceHeight = max(1, requestedHeight)
        let longestEdge = max(sourceWidth, sourceHeight)
        let scale = longestEdge > maxDimension ? Double(maxDimension) / Double(longestEdge) : 1
        return (
            max(1, Int((Double(sourceWidth) * scale).rounded())),
            max(1, Int((Double(sourceHeight) * scale).rounded()))
        )
    }

    private func evictUntilAffordable(_ incomingByteCost: Int) {
        while !cachedAllocations.isEmpty,
              cachedByteCost + incomingByteCost > byteBudget,
              let oldest = cachedAllocations.min(by: {
                  $0.value.lastAccess < $1.value.lastAccess
              }) {
            cachedByteCost -= oldest.value.byteCost
            cachedAllocations.removeValue(forKey: oldest.key)
        }
    }

    private func makeTexture(width: Int, height: Int, label: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }
}
