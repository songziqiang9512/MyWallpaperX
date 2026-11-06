#!/usr/bin/env python3

from __future__ import annotations

from script.tests.source_family import read_source_family
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayer.swift"
RUNTIME_PLAN_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayerRuntimePlan.swift"
SOURCE_ROUTE_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayerSourceRoute.swift"
UTILITY_RENDERER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayerRenderer.swift"
METAL_RENDERER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift"
METAL_RENDERER_INITIALIZATION_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+Initialization.swift"
)
UTILITY_FRAME_RENDERER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityPlanFrameRenderer.swift"
)
DEPENDENCY_RUNTIME_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyFrameRuntime.swift"
)
DEPENDENCY_GEOMETRY_SOURCE = DEPENDENCY_RUNTIME_SOURCE.with_name(
    "SceneDependencyFrameRuntime+Geometry.swift"
)
AUTHORED_CATALOG_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectAdmissionCatalog.swift"
)
HOST_LAUNCH_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift"
)
IMAGE_COMPOSITOR_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerCompositor.swift"
)
FRAME_PREFLIGHT_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneResolvedMaterialFramePreflight.swift"
)
SUBMISSION_COORDINATOR_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator.swift"
)
EFFECT_EXECUTION_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+EffectExecution.swift"
)
COMPOSITION_SOURCE_FALLBACK = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+CompositionSourceFallback.swift"
)
CAPABILITY_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability.swift"
)
CAPTURED_MAIN_SOURCE_CONSERVATION = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapabilityVariant+CapturedMainSourceConservation.swift"
)

HARNESS_SOURCE = r'''
import Foundation

struct SceneLayerDisplayScriptOwnership {
    let visible: Bool
    let alpha: Bool
    var isEmpty: Bool { !visible && !alpha }
    var fields: [String] { [] }
}
struct SceneRenderDescriptor {
    struct Camera { var authoredOrthographicProjectionActive: Bool? = nil }
    struct EffectDescriptor {
        var id: Int = 0
        var file: String = "effects/original/effect.json"
        var visible: Bool? = true
    }
    struct Layer {
        let id: Int
        var visible: Bool? = true
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
        var dependencyLayerIDs: [Int] = []
        var contentKind = "image"
        var utilityLayer: SceneUtilityLayer? = nil
        var authoredDependencies: [SceneObjectDependency] = []
        var colorBlendMode: Int? = nil
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
        var usesPerspective: Bool? = nil
        var effects: [EffectDescriptor] = []
    }
    struct MaterialPass { let combos: [String: Int] }
    let layers: [Layer]
    var materialPasses: [MaterialPass] = []
    var renderOrderOverride: [Int]? = nil
    var camera = Camera()
    var renderOrderLayerIDs: [Int] { renderOrderOverride ?? layers.map(\.id) }
}
struct SceneDependencyRenderPlan {
    var requiredProviderLayerIDs: Set<Int> = []
}

@main
enum Harness {
    static func backgroundLocalSourceRoutes() -> [String: [String: Any]] {
        func probe(_ name: String, ids: [Int] = [20, 21], copy: Bool? = nil,
                   rootEffects: [SceneRenderDescriptor.EffectDescriptor] = [],
                   childEffects: [SceneRenderDescriptor.EffectDescriptor] = [],
                   ortho: Bool = true, rootPerspective: Bool = false,
                   childPerspective: Bool = false, passthrough: Bool = false,
                   childKind: String = "solid", dependencies: [Int] = [],
                   reverseMembers: Bool = false,
                   transformParents: [Int] = [], reverseStorage: Bool = true,
                   nestedBackground: Bool = false,
                   utilityPath: String = "models/util/composelayer.json") -> [String: Any] {
            var object: [String: Any] = ["config": ["passthrough": passthrough]]
            if let copy { object["copybackground"] = copy }
            let utility = SceneUtilityLayer.parse(imagePath: utilityPath,
                object: object)!
            let memberIDs = Array(ids.dropFirst())
            var root = SceneRenderDescriptor.Layer(id: ids[0], childLayerIDs: memberIDs,
                dependencyLayerIDs: dependencies, contentKind: utility.kind.rawValue, utilityLayer: utility,
                usesPerspective: rootPerspective, effects: rootEffects)
            var children = memberIDs.map { id in
                SceneRenderDescriptor.Layer(id: id, parentID: ids[0],
                    contentKind: childKind, usesPerspective: childPerspective, effects: childEffects)
            }
            var order = reverseMembers ? Array(memberIDs.reversed()) : memberIDs
            if let first = transformParents.first, let last = transformParents.last {
                root.childLayerIDs = [first]
                for index in children.indices { children[index].parentID = last }
                for (index, id) in transformParents.enumerated() {
                    children.append(.init(id: id,
                        parentID: index == 0 ? root.id : transformParents[index - 1],
                        childLayerIDs: index + 1 == transformParents.count
                            ? memberIDs : [transformParents[index + 1]], contentKind: "container"))
                }
                order = transformParents + order
            }
            if nestedBackground {
                children[0].contentKind = utility.kind.rawValue
                children[0].utilityLayer = SceneUtilityLayer.parse(
                    imagePath: utilityPath, object: [:])!
                children[0].childLayerIDs = [ids[0] + 1000]
                children.append(.init(id: ids[0] + 1000, parentID: memberIDs[0],
                    contentKind: "solid"))
                order.append(ids[0] + 1000)
            }
            var descriptor = SceneRenderDescriptor(layers: reverseStorage
                ? Array(children.reversed()) + [root] : [root] + children,
                renderOrderOverride: [ids[0]] + order)
            descriptor.camera.authoredOrthographicProjectionActive = ortho
            switch SceneUtilityLayerSourceRoute.resolve(layer: root, descriptor: descriptor) {
            case let .failure(failure): return ["failure": failure.rawValue]
            case let .success(route): return [
                "root": route.triggerLayerID, "members": route.orderedCompositionSubtreeLayerIDs,
                "isolated": route.usesIsolatedGroupTarget, "local": route.usesAuthoredLocalSource,
                "copyBackground": utility.copyBackground,
                "authoredCopyOmitted": utility.authoredCopyBackground == nil,
            ]
            }
        }
        return [
            "omitted": probe("omitted"),
            "true": probe("true", copy: true),
            "transparent": probe("transparent", copy: false),
            "renamed": probe("renamed", ids: [709, 218], copy: true),
            "hidden-authored-effect": probe("hidden", rootEffects: [.init(visible: false)]),
            "visible-authored-effect": probe("visible", rootEffects: [.init(visible: true)]),
            "renamed-hidden-effect": probe("renamed-hidden", ids: [73, 81, 218], copy: true,
                rootEffects: [.init(id: 91, file: "effects/renamed/mask.json", visible: false)],
                reverseMembers: true),
            "renamed-visible-effect": probe("renamed-visible", ids: [73, 81, 218], copy: true,
                rootEffects: [.init(id: 630, file: "effects/other/renamed.json", visible: true)],
                reverseMembers: true),
            "child-effect": probe("child-effect", childEffects: [.init(visible: true)]),
            "transform-chain": probe("transform-chain", copy: true, childKind: "image",
                transformParents: [42, 43]),
            "transform-chain-storage": probe("transform-chain-storage", copy: true,
                childKind: "image", transformParents: [42, 43], reverseStorage: false),
            "renamed-transform-chain": probe("renamed-transform-chain", ids: [901, 218, 307],
                copy: true, childKind: "text", reverseMembers: true,
                transformParents: [403, 402], reverseStorage: false),
            "empty-container": probe("empty-container", childKind: "container"),
            "sound-member": probe("sound", childKind: "sound"),
            "point-light-member": probe("point-light", childKind: "pointLight"),
            "directional-light-member": probe("directional-light", childKind: "directionalLight"),
            "quad-member": probe("quad", childKind: "quad"),
            "not-orthographic": probe("native", ortho: false),
            "root-perspective": probe("perspective", rootPerspective: true),
            "child-perspective": probe("child-perspective", childPerspective: true),
            "passthrough": probe("passthrough", passthrough: true),
            "model-member": probe("model", childKind: "model", transformParents: [42]),
            "particle-member": probe("particle", childKind: "particle", transformParents: [42, 43]),
            "renamed-particle-hidden-effect": probe("particle-hidden", ids: [901, 218, 307],
                rootEffects: [.init(id: 91, file: "effects/renamed/mask.json", visible: false)],
                childKind: "particle", reverseMembers: true, transformParents: [403, 402]),
            "renamed-particle-visible-effect": probe("particle-visible", ids: [901, 218, 307],
                rootEffects: [.init(id: 630, file: "effects/other/filter.json", visible: true)],
                childKind: "particle", reverseMembers: true, transformParents: [403, 402]),
            "spot-light-member": probe("spot-light", childKind: "spotLight"),
            "external-dependency": probe("dependent", dependencies: [901]),
            "nested-background": probe("nested", rootEffects: [.init(visible: false)],
                nestedBackground: true),
            "project-omitted": probe("project", utilityPath: "models/util/projectlayer.json"),
            "project-transparent": probe("project-transparent", copy: false,
                utilityPath: "models/util/projectlayer.json"),
            "project-hidden-effect": probe("project-hidden", rootEffects: [.init(visible: false)],
                utilityPath: "models/util/projectlayer.json"),
            "project-visible-effect": probe("project-visible", rootEffects: [.init(visible: true)],
                utilityPath: "models/util/projectlayer.json"),
            "project-renamed-transform-chain": probe("project-renamed", ids: [901, 218, 307],
                rootEffects: [.init(id: 630, file: "effects/other/filter.json")], childKind: "text",
                reverseMembers: true, transformParents: [403, 402], reverseStorage: false,
                utilityPath: "models/util/projectlayer.json"),
            "project-nested-background": probe("project-nested", nestedBackground: true,
                utilityPath: "models/util/projectlayer.json"),
            "project-model-member": probe("project-model", childKind: "model", transformParents: [42],
                utilityPath: "models/util/projectlayer.json"),
            "project-spot-light-member": probe("project-spot-light", childKind: "spotLight",
                utilityPath: "models/util/projectlayer.json"),
        ]
    }

    static func sourceRoutes() -> [String: [String: Any]] {
        func utility(_ path: String = "models/util/composelayer.json",
                     copy: Bool = false, passthrough: Bool = false) -> SceneUtilityLayer {
            SceneUtilityLayer.parse(imagePath: path,
                object: ["copybackground": copy, "config": ["passthrough": passthrough]])!
        }
        func route(_ root: SceneRenderDescriptor.Layer,
                   peers: [SceneRenderDescriptor.Layer] = [],
                   order: [Int]? = nil) -> [String: Any] {
            let descriptor = SceneRenderDescriptor(layers: [root] + peers,
                renderOrderOverride: order)
            switch SceneUtilityLayerSourceRoute.resolve(layer: root, descriptor: descriptor) {
            case let .failure(failure): return ["failure": failure.rawValue]
            case let .success(value): return [
                "trigger": value.triggerLayerID,
                "isolated": value.usesIsolatedGroupTarget,
                "capturesSubtree": value.capturesCompositionSubtree,
                "members": value.orderedCompositionSubtreeLayerIDs,
            ]
            }
        }
        let plain = SceneRenderDescriptor.Layer(id: 20, contentKind: "composition",
                                                utilityLayer: utility())
        let provider = SceneRenderDescriptor.Layer(id: 30, visible: false, contentKind: "text")
        var flat = plain; flat.dependencyLayerIDs = [provider.id]
        var authored = plain
        authored.authoredDependencies = SceneObjectDependencies(rawValue: [
            ["id": provider.id, "type": "texture", "index": 1],
        ]).authored
        var both = flat; both.authoredDependencies = authored.authoredDependencies
        var result = ["empty": route(plain), "flat": route(flat, peers: [provider]),
                      "authored": route(authored, peers: [provider]),
                      "both": route(both, peers: [provider])]
        var hidden = both; hidden.visible = false
        let consumer = SceneRenderDescriptor.Layer(id: 40, dependencyLayerIDs: [hidden.id],
            contentKind: "composition", utilityLayer: utility())
        result["hidden-provider"] = route(hidden, peers: [provider, consumer])
        // Resource spelling is parsed by the real named-reference owner;
        // SourceRoute receives identities, never sampler-path heuristics.
        for (ownerID, providerID, suffix) in [(901, 709, "_a"), (73, 218, "_b")] {
            let reference = SceneNamedTextureReference.parse(
                "_rt_imageLayerComposite_\(providerID)\(suffix)")!
            var renamed = SceneRenderDescriptor.Layer(id: ownerID,
                dependencyLayerIDs: [reference.providerLayerID], contentKind: "composition",
                utilityLayer: utility())
            renamed.authoredDependencies = [.init(layerID: providerID, index: 1, type: "texture")]
            result["renamed-\(ownerID)"] = route(renamed,
                peers: [.init(id: providerID, visible: false, contentKind: "image")],
                order: [providerID, ownerID])
            renamed.utilityLayer = utility(passthrough: true)
            result["renamed-passthrough-\(ownerID)"] = route(renamed,
                peers: [.init(id: providerID, visible: false, contentKind: "image")],
                order: [providerID, ownerID])
        }
        var background = both; background.utilityLayer = utility(copy: true)
        var passthrough = both; passthrough.utilityLayer = utility(passthrough: true)
        var backgroundPass = both; backgroundPass.utilityLayer = utility(copy: true, passthrough: true)
        var defaultPass = both
        defaultPass.utilityLayer = SceneUtilityLayer.parse(imagePath: "models/util/composelayer.json",
            object: ["config": ["passthrough": true]])!
        result["background"] = route(background, peers: [provider])
        result["passthrough"] = route(passthrough, peers: [provider])
        result["background-passthrough"] = route(backgroundPass, peers: [provider])
        result["default-passthrough"] = route(defaultPass, peers: [provider])
        for kind in ["project", "fullscreen"] {
            var other = both; other.contentKind = kind
            other.utilityLayer = utility("models/util/\(kind)layer.json")
            result[kind] = route(other, peers: [provider])
        }
        let child = SceneRenderDescriptor.Layer(id: 21, parentID: plain.id, contentKind: "solid")
        var group = plain; group.childLayerIDs = [child.id]
        result["children"] = route(group, peers: [child, provider], order: [30, 21, 20])
        var transformParent = child
        transformParent.contentKind = "container"; transformParent.childLayerIDs = [22]
        let descendant = SceneRenderDescriptor.Layer(id: 22, parentID: child.id, contentKind: "image")
        result["transform-parent"] = route(group, peers: [descendant, provider, transformParent],
            order: [30, 22, 20, 21])
        var wrongDescendant = descendant; wrongDescendant.parentID = group.id
        result["wrong-descendant-parent"] = route(group,
            peers: [wrongDescendant, transformParent, provider])
        for copy in [false, true] {
            var passingGroup = group; passingGroup.utilityLayer = utility(copy: copy, passthrough: true)
            result["passthrough-children-\(copy)"] = route(passingGroup, peers: [child])
        }
        for (name, flatIDs, authoredValues) in [
            ("child-flat", [provider.id], [SceneObjectDependency]()),
            ("child-authored", [], authored.authoredDependencies),
            ("child-both", [provider.id], authored.authoredDependencies),
        ] {
            var external = group; external.dependencyLayerIDs = flatIDs
            external.authoredDependencies = authoredValues
            result[name] = route(external, peers: [child, provider])
        }
        result["duplicate-id"] = route(both, peers: [provider, provider])
        result["duplicate-order"] = route(both, peers: [provider], order: [20, 20])
        result["passthrough-duplicate-id"] = route(passthrough, peers: [provider, provider])
        result["passthrough-duplicate-order"] = route(passthrough, peers: [provider], order: [20, 20])
        result["unlisted-child"] = route(both, peers: [child, provider])
        var missing = plain; missing.childLayerIDs = [99]
        result["missing-child"] = route(missing)
        var repeated = group; repeated.childLayerIDs = [child.id, child.id]
        result["duplicate-child"] = route(repeated, peers: [child])
        var wrongParent = child; wrongParent.parentID = provider.id
        result["wrong-parent"] = route(group, peers: [wrongParent, provider])
        var cycle = group; cycle.parentID = child.id
        var back = child; back.childLayerIDs = [group.id]
        result["cycle"] = route(cycle, peers: [back])
        var mismatch = plain; mismatch.contentKind = "project"
        result["utility-kind"] = route(mismatch)
        for kind in ["project", "fullscreen"] {
            var typedGroup = group
            typedGroup.contentKind = kind
            typedGroup.utilityLayer = SceneUtilityLayer.parse(
                imagePath: "models/util/\(kind)layer.json", object: [:])!
            let middle = SceneRenderDescriptor.Layer(id: 31, contentKind: "solid")
            let suffix = SceneRenderDescriptor.Layer(id: 40, contentKind: "solid")
            result["\(kind)-children"] = route(typedGroup,
                peers: [child, provider, middle, suffix], order: [30, 20, 31, 21, 40])
            result["\(kind)-wrong-parent"] = route(typedGroup, peers: [wrongParent, provider])
            result["\(kind)-wrong-descendant-parent"] = route(typedGroup,
                peers: [wrongDescendant, transformParent, provider])
        }
        let renamedProject = SceneRenderDescriptor.Layer(id: 901, childLayerIDs: [218],
            contentKind: "project", utilityLayer: SceneUtilityLayer.parse(
                imagePath: "models/util/projectlayer.json", object: [:])!)
        result["project-child-before-root"] = route(renamedProject,
            peers: [.init(id: 218, parentID: 901, contentKind: "solid"),
                    .init(id: 709, contentKind: "solid")], order: [709, 218, 901])
        return result
    }

    static func main() throws {
        let fixtures: [(String?, [String: Any])] = [
            ("models/util/composelayer.json", ["config": ["passthrough": true]]),
            (" MODELS\\UTIL\\PROJECTLAYER.JSON ", ["copybackground": true]),
            ("models/util/fullscreenlayer.json", [:]),
            ("models/user/composelayer.json", [:]),
            (nil, [:]),
            ("models/util/composelayer.json", ["copybackground": false]),
            ("models/util/composelayer.json", ["copybackground": ["value": true]]),
            ("models/util/projectlayer.json", [:]),
            ("models/util/projectlayer.json", ["copybackground": false]),
            ("models/util/projectlayer.json", ["copybackground": ["value": false]]),
            ("models/util/projectlayer.json", ["copybackground": ["value": true]]),
            ("models/user/projectlayer.json", [:]),
        ]
        let parsed = fixtures.map { SceneUtilityLayer.parse(imagePath: $0.0, object: $0.1) }
        func readable(_ layers: [SceneRenderDescriptor.Layer]) -> Bool {
            SceneRenderDescriptor(layers: layers).requiresReadableFramebuffer(
                sceneBackgroundLayerIDs: [], utilityCaptureLayerIDs: [],
                dependencyPlan: .init())
        }
        let maximum = SceneBlendModeShaderSource.maximumMode
        var hiddenBlend: [String: Bool] = [:]
        for kind in ["image", "solid", "text"] {
            hiddenBlend[kind] = readable([
                .init(id: 1, visible: false, contentKind: kind, colorBlendMode: 1)])
        }
        let result: [String: Any] = [
            "sourceRoutes": sourceRoutes(),
            "backgroundLocalSourceRoutes": backgroundLocalSourceRoutes(),
            "kinds": parsed.map { $0?.kind.rawValue ?? "none" },
            "copyBackground": parsed.map { $0?.copyBackground ?? false },
            "authoredCopyBackground": parsed.map {
                ($0?.authoredCopyBackground).map { String($0) } ?? "omitted" },
            "passthrough": parsed.map { $0?.passthrough ?? false },
            "hiddenAdvancedBlend": hiddenBlend,
            "parentHiddenAdvancedBlend": readable([
                .init(id: 10, visible: false, contentKind: "composition"),
                .init(id: 11, parentID: 10, colorBlendMode: maximum)]),
            "ordinaryBlend": readable([.init(id: 1, visible: false, colorBlendMode: 0)]),
            "absentBlend": readable([.init(id: 1, visible: false)]),
            "invalidBlend": readable([.init(id: 1, colorBlendMode: maximum + 1)]),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneUtilityLayerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-utility-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        # Compile the unchanged production extension. Its other renderer
        # owners require Metal; this CPU gate exercises only drawable usage.
        source_path = Path(os.environ.get(
            "MWX_SCENE_UTILITY_READABLE_SOURCE", str(RUNTIME_PLAN_SOURCE)))
        runtime_source = source_path.read_text(encoding="utf-8")
        readable = directory / "ReadableFramebuffer.swift"
        readable.write_text(
            "import Foundation\n" + runtime_source[runtime_source.rindex("extension SceneRenderDescriptor {"):],
            encoding="utf-8")
        cls.binary = directory / "scene-utility-layers"
        subprocess.run(
            ["xcrun", "--sdk", "macosx", "swiftc", str(SOURCE),
             str(SOURCE_ROUTE_SOURCE),
             str(SOURCE_ROOT / "Format/SceneObjectDependency.swift"),
             str(SOURCE_ROOT / "Resources/Textures/SceneNamedTextureReference.swift"),
             str(SOURCE_ROOT / "Systems/Properties/SceneDynamicSnapshot.swift"),
             str(SOURCE_ROOT / "Rendering/Geometry/SceneLayerVisibility.swift"),
             str(SOURCE_ROOT / "Rendering/Composition/SceneBlendModeShaderSource.swift"),
             str(readable), str(harness), "-o", str(cls.binary)],
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

    def test_canonical_paths_are_typed_without_matching_user_models(self) -> None:
        self.assertEqual(
            self.result["kinds"],
            ["composition", "project", "fullscreen", "none", "none", "composition", "composition",
             "project", "project", "project", "project", "none"],
        )

    def test_composition_and_project_background_default_and_explicit_flags(self) -> None:
        self.assertEqual(self.result["copyBackground"],
                         [True, True, False, False, False, False, True, True, False, False, True, False])
        self.assertEqual(self.result["authoredCopyBackground"],
                         ["omitted", "true", "omitted", "omitted", "omitted", "false", "true",
                          "omitted", "false", "false", "true", "omitted"])
        self.assertEqual(self.result["passthrough"],
                         [True, False, False, False, False, False, False, False, False, False, False, False])

    def test_background_groups_keep_local_sources_across_root_effect_states(self) -> None:
        routes = self.result["backgroundLocalSourceRoutes"]
        for name, root, members, copies, omitted in (
            ("omitted", 20, [21], True, True),
            ("true", 20, [21], True, False),
            ("transparent", 20, [21], False, False),
            ("renamed", 709, [218], True, False),
            ("hidden-authored-effect", 20, [21], True, True),
            ("visible-authored-effect", 20, [21], True, True),
            ("renamed-hidden-effect", 73, [218, 81], True, False),
            ("renamed-visible-effect", 73, [218, 81], True, False),
            ("child-effect", 20, [21], True, True),
            ("transform-chain", 20, [42, 43, 21], True, False),
            ("transform-chain-storage", 20, [42, 43, 21], True, False),
            ("renamed-transform-chain", 901, [403, 402, 307, 218], True, False),
            ("empty-container", 20, [21], True, True),
            ("sound-member", 20, [21], True, True),
            ("point-light-member", 20, [21], True, True),
            ("directional-light-member", 20, [21], True, True),
            ("quad-member", 20, [21], True, True),
            ("passthrough", 20, [21], True, True),
            ("particle-member", 20, [42, 43, 21], True, True),
            ("renamed-particle-hidden-effect", 901, [403, 402, 307, 218], True, True),
            ("renamed-particle-visible-effect", 901, [403, 402, 307, 218], True, True),
            ("external-dependency", 20, [21], True, True),
            ("project-omitted", 20, [21], True, True),
            ("project-transparent", 20, [21], False, False),
            ("project-hidden-effect", 20, [21], True, True),
            ("project-visible-effect", 20, [21], True, True),
            ("project-renamed-transform-chain", 901, [403, 402, 307, 218], True, True),
        ):
            with self.subTest(route=name):
                self.assertEqual(routes[name], {
                    "root": root, "members": members, "isolated": True, "local": True,
                    "copyBackground": copies, "authoredCopyOmitted": omitted})

    def test_projection_and_members_keep_existing_background_source_boundaries(self) -> None:
        routes = self.result["backgroundLocalSourceRoutes"]
        for name in ("not-orthographic", "root-perspective", "child-perspective"):
            with self.subTest(route=name):
                self.assertEqual(routes[name], {
                    "root": 20, "members": [21], "isolated": True, "local": False,
                    "copyBackground": True, "authoredCopyOmitted": True})
        self.assertEqual(routes["nested-background"], {
            "root": 20, "members": [21, 1020], "isolated": True, "local": False,
            "copyBackground": True, "authoredCopyOmitted": True})
        self.assertEqual(routes["project-nested-background"], {
            "root": 20, "members": [21, 1020], "isolated": True, "local": False,
            "copyBackground": True, "authoredCopyOmitted": True})
        for name in ("model-member", "spot-light-member", "project-model-member", "project-spot-light-member"):
            with self.subTest(route=name):
                self.assertEqual(routes[name], {"failure": "utility-composition-subtree-shape"})

    def test_named_sampler_dependencies_do_not_become_composition_main_source(self) -> None:
        routes = self.result["sourceRoutes"]
        for name, owner in (("empty", 20), ("flat", 20), ("authored", 20), ("both", 20),
                            ("hidden-provider", 20), ("passthrough", 20),
                            ("renamed-901", 901), ("renamed-73", 73),
                            ("renamed-passthrough-901", 901), ("renamed-passthrough-73", 73)):
            with self.subTest(route=name):
                self.assertEqual(routes[name], {"trigger": owner, "isolated": True,
                                                "capturesSubtree": False, "members": []})

    def test_background_choice_precedes_childless_passthrough(self) -> None:
        routes = self.result["sourceRoutes"]
        for name in ("empty", "passthrough"):
            with self.subTest(route=name):
                self.assertEqual(routes[name], {"trigger": 20, "isolated": True,
                                                "capturesSubtree": False, "members": []})
        for name in ("background", "background-passthrough", "default-passthrough", "project", "fullscreen"):
            with self.subTest(route=name):
                self.assertEqual(self.result["sourceRoutes"][name], {
                    "trigger": 20, "isolated": False, "capturesSubtree": False, "members": []})

    def test_isolated_source_keeps_membership_and_rejects_broken_parent_closure(self) -> None:
        routes = self.result["sourceRoutes"]
        self.assertEqual(routes["children"], {"trigger": 20, "isolated": True,
                                               "capturesSubtree": True, "members": [21]})
        self.assertEqual(routes["transform-parent"], {"trigger": 20, "isolated": True,
                                                    "capturesSubtree": True, "members": [22, 21]})
        for name in ("child-flat", "child-authored", "child-both", "project-children"):
            with self.subTest(route=name):
                self.assertEqual(routes[name], {"trigger": 20, "isolated": True,
                                                "capturesSubtree": True, "members": [21]})
        self.assertEqual(routes["project-child-before-root"], {"trigger": 901, "isolated": True,
                                                               "capturesSubtree": True, "members": [218]})
        for name in ("duplicate-id",
                     "duplicate-order", "unlisted-child", "missing-child",
                     "duplicate-child", "wrong-parent", "wrong-descendant-parent", "cycle",
                     "passthrough-children-false", "passthrough-children-true",
                     "passthrough-duplicate-id", "passthrough-duplicate-order",
                     "project-wrong-parent", "project-wrong-descendant-parent",
                     "fullscreen-children", "fullscreen-wrong-parent", "fullscreen-wrong-descendant-parent"):
            with self.subTest(route=name):
                self.assertEqual(routes[name], {"failure": "utility-composition-subtree-shape"})
        self.assertEqual(routes["utility-kind"], {"failure": "utility-shape"})

    def test_hidden_advanced_blend_reserves_readable_drawable_usage(self) -> None:
        self.assertEqual(self.result["hiddenAdvancedBlend"],
                         {"image": True, "solid": True, "text": True})
        self.assertTrue(self.result["parentHiddenAdvancedBlend"])

    def test_ordinary_or_unsupported_blend_does_not_request_readable_drawable(self) -> None:
        for key in ("ordinaryBlend", "absentBlend", "invalidBlend"):
            self.assertFalse(self.result[key], key)

    def test_document_and_descriptor_preserve_generic_dependencies(self) -> None:
        document = (SOURCE_ROOT / "Format/SceneDocument.swift").read_text(encoding="utf-8")
        descriptor = (REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRenderDescriptor.swift").read_text(encoding="utf-8")
        self.assertIn('SceneObjectDependencies(rawValue: root["dependencies"])', document)
        self.assertIn("dependencyLayerIDs: object.dependencyLayerIDs", descriptor)
        self.assertIn("authoredDependencies: object.authoredDependencies", descriptor)
        self.assertIn("if let utilityLayer = object.utilityLayer", descriptor)

    def test_utility_report_preserves_typed_dependency_issues(self) -> None:
        runtime_plan = RUNTIME_PLAN_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            '"utilityDependencyIssueCount: \\(dependencyPlan.issues.count)"',
            runtime_plan,
        )
        self.assertIn(
            '"utilityDependencyIssue: kind=\\(issue.kind.rawValue) "',
            runtime_plan,
        )
        self.assertIn('"layer=\\(issue.layerID) provider=\\(provider)"', runtime_plan)

    def test_utility_capture_requires_unified_layer_ownership(self) -> None:
        runtime_plan = RUNTIME_PLAN_SOURCE.read_text(encoding="utf-8")
        self.assertIn("resolvedMaterialLayerIDs.contains(layer.id)", runtime_plan)
        self.assertIn("disposition = .capture", runtime_plan)
        self.assertNotIn("supportsCompleteAuthoredCapture", runtime_plan)
        self.assertNotIn("partialEffects", runtime_plan)
        capability = CAPABILITY_SOURCE.read_text(encoding="utf-8")
        self.assertNotIn("case dedicated", capability)
        self.assertNotIn("SceneEffectStageExecutionPlan", capability)

    def test_planned_utility_chain_loads_and_receives_effect_resources(self) -> None:
        launch = HOST_LAUNCH_SOURCE.read_text(encoding="utf-8")
        metal_renderer = read_source_family(METAL_RENDERER_SOURCE) \
            + UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "resolvedMaterialCatalog.userPropertyDemands",
            launch,
            "shared MaterialProgram demands must drive resource loading",
        )
        self.assertIn(
            ".union(baseMaterialProviderBindings.userPropertyDemands)",
            launch,
            "both MaterialProgram demand owners must feed resource loading",
        )
        self.assertIn(
            "requestedIdentities: userTextureDemands",
            launch,
            "aggregated demands must reach the user texture loader request",
        )
        self.assertIn(
            "masks: .empty",
            metal_renderer,
            "utility capture must use the shared Program texture bindings",
        )

    def test_utility_capture_receives_the_frame_audio_snapshot(self) -> None:
        utility_renderer = UTILITY_RENDERER_SOURCE.read_text(encoding="utf-8")
        metal_renderer = (
            read_source_family(METAL_RENDERER_SOURCE)
            + METAL_RENDERER_INITIALIZATION_SOURCE.read_text(encoding="utf-8")
            + UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")
        )
        self.assertIn("audioSpectrum: SceneAudioSpectrumSnapshot", utility_renderer)
        self.assertIn("audioSpectrum: audioSpectrum", utility_renderer)
        self.assertIn("audioSpectrum: frameContext.audioSpectrum", metal_renderer)

    def test_utility_has_no_legacy_authored_route_or_telemetry(self) -> None:
        utility_renderer = UTILITY_RENDERER_SOURCE.read_text(encoding="utf-8")
        frame_renderer = UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")

        combined = utility_renderer + frame_renderer
        self.assertNotIn("onLegacyAuthoredRouteSelected", combined)
        self.assertNotIn("selectedLegacyAuthoredRoute", combined)
        self.assertNotIn("authoredEffectTelemetry", combined)
        self.assertNotIn("legacyAuthoredFrameTables", combined)
        self.assertIn("utilityCaptureTelemetry.record(", frame_renderer)

    def test_composition_source_fallback_is_neutral_and_structure_bounded(
        self,
    ) -> None:
        fallback = COMPOSITION_SOURCE_FALLBACK.read_text(encoding="utf-8")
        compact = "".join(fallback.split())
        self.assertIn(
            "SceneImageLayerBlendDependencyContract.declaration(",
            compact,
        )
        self.assertIn("declaration.blendMode==0", compact)
        self.assertIn("!declaration.requiresResolvedMaterialProgram", compact)
        self.assertIn("provider.visible==false", compact)
        self.assertIn(
            "SceneBaseImageTextureCandidateResolver.sample(", compact
        )
        self.assertIn("SceneImageLayerMainPassRenderer.draw(", compact)
        self.assertNotIn("2959875782", fallback)
        self.assertNotIn("ranger_wed", fallback)

    def test_hidden_solid_provider_uses_source_texture_capture(self) -> None:
        dependency_runtime = (
            DEPENDENCY_RUNTIME_SOURCE.read_text(encoding="utf-8")
            + "\n"
            + DEPENDENCY_GEOMETRY_SOURCE.read_text(encoding="utf-8")
        )
        self.assertNotIn(
            "case .resolvedMaterial, .solidLayer:",
            dependency_runtime,
        )
        self.assertGreaterEqual(
            dependency_runtime.count("case .solidLayer:"),
            2,
        )
        solid_branch = dependency_runtime[
            dependency_runtime.index("case .solidLayer:"):]
        self.assertIn("guard let sourceTexture else", solid_branch)
        self.assertIn("uniforms.tint = SIMD4", solid_branch)
        self.assertIn("providerTexture.width", solid_branch)
        self.assertIn(
            'failureReason = "solid-provider-texture-missing"',
            solid_branch,
        )
        self.assertIn('failureReason = "reservation-mismatch"', dependency_runtime)
        self.assertIn('failureReason = "frame-epoch-invalid"', dependency_runtime)

    def test_rejected_graph_suppression_does_not_retire_typed_dependencies(
        self,
    ) -> None:
        catalog = AUTHORED_CATALOG_SOURCE.read_text(encoding="utf-8")
        dependency_runtime = DEPENDENCY_RUNTIME_SOURCE.read_text(encoding="utf-8")
        image_renderer = read_source_family(METAL_RENDERER_SOURCE)
        utility_renderer = UTILITY_FRAME_RENDERER_SOURCE.read_text(
            encoding="utf-8"
        )
        compositor = IMAGE_COMPOSITOR_SOURCE.read_text(encoding="utf-8")

        self.assertNotIn("FallbackSuppressedLayerIDs", catalog)
        self.assertNotIn("suppressedConsumerLayerIDs", dependency_runtime)
        self.assertNotIn("suppressedConsumerLayerIDs", image_renderer)
        self.assertIn(
            "descriptor.layers.flatMap(\\.dependencyLayerIDs)",
            RUNTIME_PLAN_SOURCE.read_text(encoding="utf-8"),
        )
        self.assertNotIn(
            "descriptor.layers.filter {",
            RUNTIME_PLAN_SOURCE.read_text(encoding="utf-8"),
        )
        self.assertNotIn("suppressesUnclaimedEffectFallback", image_renderer)
        self.assertNotIn("authoredEffectCatalog", utility_renderer)

        self.assertIn(
            "let dependencyEffect = request.dependencyEffects.first",
            compositor,
        )
        self.assertIn("dependencyTexture: dependencyEffect?.texture", compositor)


if __name__ == "__main__":
    unittest.main()
