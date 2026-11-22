#!/usr/bin/env python3
"""Load or compact Scene benchmark matrices without duplicating sample contracts.

Schema 1 is the historical expanded matrix format. Schema 2 is a suite view:
it selects samples from one schema-1 base matrix and stores only explicit
per-suite differences. The base digest makes changes fail closed until the
suite is regenerated and reviewed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _json_object(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"Scene matrix must be a JSON object: {path}")
    return payload


def _sample_map(
    samples: Any,
    *,
    source: Path,
) -> tuple[list[str], dict[str, dict[str, Any]]]:
    if not isinstance(samples, list):
        raise ValueError(f"Scene matrix samples must be an array: {source}")
    order: list[str] = []
    result: dict[str, dict[str, Any]] = {}
    for sample in samples:
        if not isinstance(sample, dict) or "id" not in sample:
            raise ValueError(f"Scene matrix sample is malformed: {source}")
        sample_id = str(sample["id"])
        if sample_id in result:
            raise ValueError(
                f"Scene matrix contains duplicate sample id {sample_id}: {source}"
            )
        order.append(sample_id)
        result[sample_id] = dict(sample)
    return order, result


def _resolved_base_path(suite_path: Path, raw_value: Any) -> Path:
    if not isinstance(raw_value, str) or not raw_value.strip():
        raise ValueError(f"Scene matrix suite has no base_matrix: {suite_path}")
    relative = Path(raw_value)
    if relative.is_absolute():
        raise ValueError("Scene matrix suite base_matrix must be relative")
    base_path = (suite_path.parent / relative).resolve()
    try:
        base_path.relative_to(suite_path.parent.resolve())
    except ValueError as error:
        raise ValueError("Scene matrix suite base_matrix escapes its directory") from error
    return base_path


def _expanded_matrix(path: Path, seen: tuple[Path, ...]) -> dict[str, Any]:
    resolved = path.expanduser().resolve()
    if resolved in seen:
        raise ValueError(f"Scene matrix suite cycle detected: {resolved}")
    payload = _json_object(resolved)
    schema_version = payload.get("schema_version")
    if schema_version == 1:
        _sample_map(payload.get("samples"), source=resolved)
        if not isinstance(payload.get("name"), str):
            raise ValueError(f"Scene matrix has no name: {resolved}")
        return payload
    if schema_version != 2:
        raise ValueError(f"unsupported Scene matrix schema: {schema_version!r}")

    name = payload.get("name")
    sample_ids = payload.get("sample_ids")
    overrides = payload.get("sample_overrides", {})
    if not isinstance(name, str) or not name:
        raise ValueError(f"Scene matrix suite has no name: {resolved}")
    if not isinstance(sample_ids, list) or any(
        not isinstance(value, str) or not value for value in sample_ids
    ):
        raise ValueError(f"Scene matrix suite sample_ids are malformed: {resolved}")
    if len(sample_ids) != len(set(sample_ids)):
        raise ValueError(f"Scene matrix suite contains duplicate sample ids: {resolved}")
    if not isinstance(overrides, dict):
        raise ValueError(f"Scene matrix suite overrides are malformed: {resolved}")

    base_path = _resolved_base_path(resolved, payload.get("base_matrix"))
    expected_digest = payload.get("base_matrix_sha256")
    if expected_digest != sha256(base_path):
        raise ValueError(
            "Scene matrix suite base digest changed; regenerate the suite before use"
        )
    base = _expanded_matrix(base_path, (*seen, resolved))
    _, base_samples = _sample_map(base["samples"], source=base_path)
    missing = sorted(set(sample_ids) - set(base_samples))
    unknown_overrides = sorted(set(overrides) - set(sample_ids))
    if missing:
        raise ValueError(
            "Scene matrix suite base is missing sample ids: " + ", ".join(missing)
        )
    if unknown_overrides:
        raise ValueError(
            "Scene matrix suite has overrides for unselected ids: "
            + ", ".join(unknown_overrides)
        )

    samples: list[dict[str, Any]] = []
    for sample_id in sample_ids:
        sample = dict(base_samples[sample_id])
        override = overrides.get(sample_id, {})
        if not isinstance(override, dict):
            raise ValueError(f"Scene matrix override is malformed for {sample_id}")
        set_values = override.get("set", {})
        remove_keys = override.get("remove", [])
        if not isinstance(set_values, dict) or not isinstance(remove_keys, list) or any(
            not isinstance(key, str) for key in remove_keys
        ):
            raise ValueError(f"Scene matrix override is malformed for {sample_id}")
        if len(remove_keys) != len(set(remove_keys)):
            raise ValueError(f"Scene matrix override repeats remove keys for {sample_id}")
        overlap = sorted(set(set_values).intersection(remove_keys))
        if overlap:
            raise ValueError(
                f"Scene matrix override both sets and removes keys for {sample_id}: "
                + ", ".join(overlap)
            )
        if "id" in remove_keys or (
            "id" in set_values and str(set_values["id"]) != sample_id
        ):
            raise ValueError(f"Scene matrix override changes sample id {sample_id}")
        for key in remove_keys:
            sample.pop(key, None)
        sample.update(set_values)
        samples.append(sample)

    return {"schema_version": 1, "name": name, "samples": samples}


def load_scene_matrix(path: Path) -> dict[str, Any]:
    """Return either matrix schema as the historical expanded schema-1 form."""
    return _expanded_matrix(path, ())


def compact_suite_payload(
    base_path: Path,
    derived: dict[str, Any],
    *,
    suite_path: Path,
) -> dict[str, Any]:
    """Describe ``derived`` as an exact, digest-pinned view of ``base_path``."""
    base_path = base_path.expanduser().resolve()
    suite_path = suite_path.expanduser().resolve()
    base = load_scene_matrix(base_path)
    _, base_samples = _sample_map(base["samples"], source=base_path)
    derived_order, derived_samples = _sample_map(
        derived.get("samples"),
        source=suite_path,
    )
    missing = sorted(set(derived_order) - set(base_samples))
    if missing:
        raise ValueError(
            "Scene matrix suite cannot select ids absent from its base: "
            + ", ".join(missing)
        )
    try:
        base_reference = base_path.relative_to(suite_path.parent).as_posix()
    except ValueError as error:
        raise ValueError("Scene matrix suite base must share the suite directory") from error

    overrides: dict[str, dict[str, Any]] = {}
    for sample_id in derived_order:
        base_sample = base_samples[sample_id]
        derived_sample = derived_samples[sample_id]
        set_values = {
            key: value
            for key, value in derived_sample.items()
            if key not in base_sample or base_sample[key] != value
        }
        remove_keys = sorted(set(base_sample) - set(derived_sample))
        override: dict[str, Any] = {}
        if set_values:
            override["set"] = set_values
        if remove_keys:
            override["remove"] = remove_keys
        if override:
            overrides[sample_id] = override

    payload: dict[str, Any] = {
        "schema_version": 2,
        "name": derived.get("name"),
        "base_matrix": base_reference,
        "base_matrix_sha256": sha256(base_path),
        "sample_ids": derived_order,
    }
    if overrides:
        payload["sample_overrides"] = overrides
    return payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    compact = subparsers.add_parser("compact")
    compact.add_argument("base_matrix", type=Path)
    compact.add_argument("derived_matrix", type=Path)
    compact.add_argument("output", type=Path)
    expand = subparsers.add_parser("expand")
    expand.add_argument("matrix", type=Path)
    expand.add_argument("output", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output = args.output.expanduser().resolve()
    if args.command == "compact":
        derived = load_scene_matrix(args.derived_matrix)
        payload = compact_suite_payload(
            args.base_matrix,
            derived,
            suite_path=output,
        )
    else:
        payload = load_scene_matrix(args.matrix)
    output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
