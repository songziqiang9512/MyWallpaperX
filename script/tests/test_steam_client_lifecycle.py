"""Compile the real client with a network-free transport and exercise lifecycle boundaries."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class SteamClientLifecycleTests(unittest.TestCase):
    def test_real_client_with_fake_transport(self):
        sources = [
            "MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift",
            "MyWallpaperX/Core/DaemonKit/DaemonProcessTransport.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamServiceProtocol.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamServiceClient.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamAccountSession.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopQueryClient.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamAuthRoute.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopTokenStore.swift",
            "script/tests/fixtures/SteamServiceClientLifecycleHarness.swift",
        ]
        with tempfile.TemporaryDirectory(prefix="mwx-steam-client-") as directory:
            executable = pathlib.Path(directory) / "client-tests"
            subprocess.run(["xcrun", "swiftc", "-parse-as-library", *[str(ROOT / s) for s in sources],
                            "-o", str(executable)], check=True, timeout=120)
            subprocess.run([str(executable)], check=True, timeout=15)


if __name__ == "__main__":
    unittest.main()
