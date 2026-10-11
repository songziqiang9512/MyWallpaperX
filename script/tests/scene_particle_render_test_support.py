from __future__ import annotations

import json
import subprocess
import tempfile
from functools import lru_cache
from pathlib import Path


@lru_cache(maxsize=1)
def run_particle_harness(
    swift_sources: tuple[Path, ...], harness_source: str
) -> dict[str, object]:
    """Compile one shared particle fixture, read its results, then remove its binaries."""
    with tempfile.TemporaryDirectory(prefix="mwx-particle-render-") as temporary_directory:
        directory = Path(temporary_directory)
        harness = directory / "Harness.swift"
        harness.write_text(harness_source, encoding="utf-8")
        binary = directory / "scene-particle-render"
        subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in swift_sources), str(harness),
                "-framework", "Metal", "-o", str(binary),
            ],
            check=True, capture_output=True, text=True,
        )
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        return json.loads(completed.stdout)
