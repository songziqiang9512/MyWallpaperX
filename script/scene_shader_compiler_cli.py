#!/usr/bin/env python3
"""Command-line contract for the bounded Scene shader compiler harness."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_args(description: str | None, default_manifest: Path) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--glslang", required=True)
    parser.add_argument("--spirv-cross", required=True)
    parser.add_argument("--metal", required=True)
    parser.add_argument("--dependency-manifest", type=Path, default=default_manifest)
    parser.add_argument("--artifact-output", type=Path)
    return parser.parse_args()
