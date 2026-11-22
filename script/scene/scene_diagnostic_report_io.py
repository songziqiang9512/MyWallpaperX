"""Read diagnostic reports and spatial-oracle registrations with typed errors."""

from __future__ import annotations

import json
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from scene_capability_census_io import is_sample_directory_name


class DiagnosticReportError(ValueError):
    """Raised when an input is not a benchmark report shape."""


PREVIEW_ORACLE_REGISTRY_PATH = (
    Path(__file__).resolve().parent / "scene_sample_preview_oracle_registry.json"
)


def load_preview_oracle_registry(
    path: Path | None = None,
) -> dict[str, str]:
    """Load sample_id -> reason_code for samples whose flat authored preview
    cannot serve as a spatial-similarity oracle (time-dependent content and
    similar). Malformed registries fail closed with a typed error; an absent
    file means no registration."""
    registry_path = path or PREVIEW_ORACLE_REGISTRY_PATH
    if not registry_path.is_file():
        return {}
    payload = json.loads(registry_path.read_text(encoding="utf-8"))
    if not isinstance(payload, Mapping):
        raise DiagnosticReportError(
            "preview oracle registry root is not an object"
        )
    uncontrolled = payload.get("uncontrolled")
    if not isinstance(uncontrolled, dict):
        raise DiagnosticReportError(
            "preview oracle registry uncontrolled is not an object"
        )
    reasons: dict[str, str] = {}
    for sample_id, entry in sorted(uncontrolled.items()):
        if not isinstance(sample_id, str) or not is_sample_directory_name(sample_id):
            raise DiagnosticReportError(
                "preview oracle registry has an invalid sample id: "
                + repr(sample_id)
            )
        if not isinstance(entry, dict) or not isinstance(
            entry.get("reason_code"), str
        ) or not entry["reason_code"]:
            raise DiagnosticReportError(
                "preview oracle registry entry needs a reason_code string: "
                + sample_id
            )
        reasons[sample_id] = entry["reason_code"]
    return reasons


def load_report(path: Path) -> Mapping[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise DiagnosticReportError(f"cannot read {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise DiagnosticReportError(f"invalid JSON in {path}: {error}") from error
    if not isinstance(payload, Mapping):
        raise DiagnosticReportError(f"{path} does not contain a JSON object")
    return payload
