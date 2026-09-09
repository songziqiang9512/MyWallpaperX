import Foundation

/// Launch-stable Puppet bone identity exposed to script adapters.
///
/// The MDLS reader owns the authored order and hierarchy.  This value keeps
/// that dense, zero-based order immutable and builds one name index for
/// lookups. Unnamed bones retain numeric identity; duplicate nonempty names
/// and malformed parents are rejected rather than selecting another bone.
struct ScenePuppetBoneCatalog: Equatable {
    struct Entry: Equatable {
        let index: Int
        let name: String
        let parentIndex: Int
    }

    enum ConstructionError: Error, Equatable, CustomStringConvertible {
        case duplicateName(String)
        case invalidParent(index: Int, parentIndex: Int)

        var description: String {
            switch self {
            case let .duplicateName(name):
                return "puppet bone name is duplicated: \(name)"
            case let .invalidParent(index, parentIndex):
                return "puppet bone \(index) has invalid parent \(parentIndex)"
            }
        }
    }

    let entries: [Entry]
    private let indicesByName: [String: Int]

    var boneCount: Int { entries.count }

    init(rig: SceneMdlPuppetRig) throws {
        var entries: [Entry] = []
        entries.reserveCapacity(rig.bones.count)
        var indicesByName: [String: Int] = [:]
        for (index, bone) in rig.bones.enumerated() {
            guard bone.parentIndex >= -1, bone.parentIndex < index else {
                throw ConstructionError.invalidParent(
                    index: index,
                    parentIndex: bone.parentIndex
                )
            }
            if !bone.name.isEmpty {
                guard indicesByName[bone.name] == nil else {
                    throw ConstructionError.duplicateName(bone.name)
                }
                indicesByName[bone.name] = index
            }
            entries.append(
                Entry(
                    index: index,
                    name: bone.name,
                    parentIndex: bone.parentIndex
                )
            )
        }
        self.entries = entries
        self.indicesByName = indicesByName
    }

    /// Returns the authored dense index, or nil for unknown/ambiguous input.
    func index(forName name: String) -> Int? {
        guard name.isEmpty == false else { return nil }
        return indicesByName[name]
    }

    func entry(at index: Int) -> Entry? {
        guard entries.indices.contains(index) else { return nil }
        return entries[index]
    }

    func name(at index: Int) -> String? {
        entry(at: index)?.name
    }

    func parentIndex(of index: Int) -> Int? {
        entry(at: index)?.parentIndex
    }

    static func makeIfValid(rig: SceneMdlPuppetRig) -> ScenePuppetBoneCatalog? {
        try? Self(rig: rig)
    }
}

extension SceneMdlPuppetRig {
    /// The single validated name/parent/index view for script-facing Puppet
    /// identity.  Invalid authored identity fails closed and remains visible
    /// to diagnostics through the throwing initializer above.
    var boneCatalog: ScenePuppetBoneCatalog? {
        ScenePuppetBoneCatalog.makeIfValid(rig: self)
    }
}
