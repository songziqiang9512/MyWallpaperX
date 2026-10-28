"""Assemble real Catalog/provider sources with the shared controlled service leaves.

Filesystem facts and projection methods remain production bodies. Optional
instrumentation observes the existing detached batch, never substitutes results.
"""
import hashlib
from pathlib import Path
import re

from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


def assemble_catalog_fixture(main_fixture=None):
    read_inputs = {"script/tests/library_catalog_fixture.py": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    def source(path):
        data = (ROOT / path).read_bytes()
        read_inputs[path] = hashlib.sha256(data).hexdigest()
        return data.decode()
    fixture = source("script/tests/fixtures/WallpaperLibraryCatalogHarness.swift")
    if main_fixture is not None:
        fixture = fixture.split("@main struct WallpaperLibraryCatalogHarness {", 1)[0] + source(main_fixture)
    replacements = {
        "// STATIC_IMAGE_MODEL": declaration(source("MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift"), "struct SILWallpaper:"),
        "// CONTENT_RATING_SUPPORT": declaration(source("MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopAgeRatingSupport.swift"), "nonisolated enum SteamWorkshopContentRatingSupport"),
        "// CATALOG_VALUE": declaration(source("MyWallpaperX/Core/LibraryCollections/WallpaperLibraryQuery.swift"), "nonisolated struct WallpaperLibraryCatalog:"),
        "// JOB_STATE": declaration(source("MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopJobStore.swift"), "enum SteamDownloadJobState:"),
        "// HISTORY_OUTCOME": declaration(source("MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopJobStore.swift"), "enum SteamDownloadHistoryOutcome:"),
        "// HISTORY_VALUE": declaration(source("MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopJobStore.swift"), "struct SteamDownloadHistoryEntry:"),
        "// DOWNLOAD_EXCLUSION_FACTS": declaration(source("MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadFiltering.swift"), "    func excludedDownloadReferences("),
        "// DOWNLOAD_FAILURE_HISTORY": declaration(source("MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadFiltering.swift"), "    func hasFailedDownloadHistory("),
        "// DOWNLOAD_ACCOUNT": declaration(source("MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadFiltering.swift"), "    var currentSteamDownloadAccount:"),
        "// JOB_VALUE": declaration(source("MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopJobStore.swift"), "struct SteamDownloadJob:"),
        "// WEB_PROJECT_GENERAL": declaration(source("MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopAPIModels.swift"), "nonisolated struct SteamWorkshopProjectGeneral:"),
        "// WEB_PROJECT": declaration(source("MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopAPIModels.swift"), "nonisolated struct SteamWorkshopProject:"),
        "// WEB_ENTRY_VALIDATION": declaration(source("MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebValidation.swift"), "    nonisolated func webLaunchEntryIsValid("),
        "// DECLARED_WEB_ENTRY": declaration(source("MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebProjectSupport.swift"), "    nonisolated static func declaredWebEntryRelativePath("),
        "// LOAD_WEB_PROJECT": declaration(source("MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+LibraryRecords.swift"), "    nonisolated static func loadWorkshopProject("),
        "// STEAM_LAUNCH_ADMISSION": declaration(source("MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadAccessors.swift"), "    func canLaunchDownloadRecord("),
    }
    for marker, value in replacements.items():
        fixture = fixture.replace(marker, value)
    paths = [
        "MyWallpaperX/Models/VideoWallpaper.swift", "MyWallpaperX/Models/WallpaperReference.swift",
        "MyWallpaperX/Models/WallpaperContent.swift",
        "MyWallpaperX/Core/OnlineImages/OnlineImageModels.swift",
        "MyWallpaperX/Core/OnlineImages/OnlineImageContentProjection.swift",
        "script/tests/fixtures/OnlineImageLibraryAppStub.swift",
        "MyWallpaperX/Modules/Pixabay/Core/PixabayModels.swift",
        "MyWallpaperX/Modules/Pixabay/Core/PixabayDownloadedContent.swift",
        "MyWallpaperX/Modules/Pixabay/Core/PixabayLibraryContentProjection.swift",
        "MyWallpaperX/Modules/VideoLibrary/Core/VideoLibraryContentProjection.swift",
        "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+LibraryContent.swift",
        "MyWallpaperX/Modules/StaticImageLibrary/Core/StaticImageLibraryContentProjection.swift",
        "MyWallpaperX/Modules/StaticImageLibrary/Core/SILService+LibraryContent.swift",
        "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopModels.swift",
        "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopDownloadProgress.swift",
        "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopDownloadRecord+Launchability.swift",
        "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopWebValidationModels.swift",
        "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopDownloadRecord+Web.swift",
        "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLibraryContentProjection.swift",
        "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+LibraryContent.swift",
    ]
    controller_path = "MyWallpaperX/App/WallpaperLibraryCatalogController.swift"
    controller = re.sub(r"\bprivate\s+", "", source(controller_path))
    inputs = dict(read_inputs)
    inputs.update({p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths + [controller_path]})
    return fixture, controller, paths, inputs


def write_catalog_sources(work, paths):
    compiled = []
    for path in paths:
        if path.endswith(("WallpaperManager+LibraryContent.swift", "SILService+LibraryContent.swift")):
            original = (ROOT / path).read_text()
            marker = "            var facts: [WallpaperReference: WallpaperContentLocalFacts] = [:]"
            if original.count(marker) != 1:
                raise AssertionError("Provider worker instrumentation is no longer exact: " + path)
            instrumented = original.replace(marker, "            let observed = CatalogFileProbe.shared.begin()\n            defer { CatalogFileProbe.shared.end(observed) }\n" + marker)
            copy = work / Path(path).name
            copy.write_text(instrumented)
            compiled.append(str(copy))
        else:
            compiled.append(str(ROOT / path))
    return compiled
