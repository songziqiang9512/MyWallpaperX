"""Keep the Graph harness JSON packet separate from retained Debug diagnostics."""

import json
import subprocess


DIAGNOSTIC_PREFIXES = (
    "MWX resolved material envelope rejection:",
    "MWX resolved material template rejection:",
    "MWX resolved material frontend rejection:",
    "MWX resolved material sampler reachability rejection:",
    "MWX resolved material resource demand rejection:",
    "MWX preserved-channel graph rejection:",
)


def separate_graph_debug_output(result: subprocess.CompletedProcess[str]) -> subprocess.CompletedProcess[str]:
    if result.returncode:
        return result
    remaining = result.stdout.lstrip()
    diagnostics = []
    while remaining.startswith(DIAGNOSTIC_PREFIXES):
        line, separator, remaining = remaining.partition("\n")
        if not separator:
            raise ValueError("Graph harness emitted diagnostics without a JSON packet")
        diagnostics.append(line)
        remaining = remaining.lstrip()
    payload, end = json.JSONDecoder().raw_decode(remaining)
    if not isinstance(payload, dict):
        raise ValueError("Graph harness JSON packet must be an object")
    for line in remaining[end:].strip().splitlines():
        if not line.startswith(DIAGNOSTIC_PREFIXES):
            raise ValueError(f"Unexpected output after Graph harness JSON: {line[:160]}")
        diagnostics.append(line)
    return subprocess.CompletedProcess(
        result.args, result.returncode, json.dumps(payload),
        result.stderr + ("\n" + "\n".join(diagnostics) if diagnostics else ""),
    )
