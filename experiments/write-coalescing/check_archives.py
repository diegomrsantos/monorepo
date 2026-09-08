"""Audit archived evidence without collecting new timings."""
import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path
import sys

if not __debug__:
    raise SystemExit("Run without -O: the archive audit requires assertions.")

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("repo", type=Path, help="repository root with the measured sources")
parser.add_argument("output", type=Path, help="JSON audit output path")
args = parser.parse_args()
repo = args.repo.resolve()
output = args.output
experiment = repo / "experiments/write-coalescing"
sys.path.insert(0, str(experiment))
from validate_native import validate
from analyze_native import analyze

def read_json(path):
    return json.loads(path.read_text())

def equivalent(actual, expected, path="root"):
    if isinstance(expected, dict):
        assert actual.keys() == expected.keys(), path
        for key in expected:
            equivalent(actual[key], expected[key], path + "." + key)
    elif isinstance(expected, list):
        assert len(actual) == len(expected), path
        for index, (a, b) in enumerate(zip(actual, expected)):
            equivalent(a, b, path + "[" + str(index) + "]")
    elif isinstance(expected, float):
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (path, actual, expected)
    else:
        assert actual == expected, (path, actual, expected)

native = experiment / "results/native"
plans = {name: read_json(experiment / ("plans/backend-" + name + ".json"))
         for name in ("grid", "aa", "smoke")}
manifests = {
    "linux": [native / "linux/binaries/manifest.json"],
    "macos": [native / "macos/manifest.json", native / "macos/earlier-aa-build-manifest.json"],
}
patch_checks = []
for platform in ("linux", "macos"):
    manifest_path = manifests[platform][0]
    manifest = read_json(manifest_path)
    for variant in ("vectored", "coalesce", "pool"):
        patch_path = manifest_path.with_name(variant + ".patch")
        digest = hashlib.sha256(patch_path.read_bytes()).hexdigest()
        expected = manifest["variants"][variant]["patch_sha256"]
        assert digest == expected, ("experimental patch hash", str(patch_path), digest, expected)
        patch_checks.append({
            "patch": str(patch_path.relative_to(repo)),
            "manifest": str(manifest_path.relative_to(repo)),
            "variant": variant,
            "sha256": digest,
        })
print(str(len(patch_checks)) + " experimental patch hashes pass", flush=True)

datasets = [
    ("linux", "grid", "grid"), ("macos", "grid", "grid"),
    ("linux", "smoke", "smoke"), ("macos", "smoke", "smoke"),
    ("linux", "aa", "aa"), ("linux", "aa-isolated", "aa"),
    ("linux", "aa-same-cache", "aa"), ("macos", "aa", "aa"),
    ("macos", "earlier-aa", "aa"),
]
results = []
comparison_count = 0
for platform, name, plan_name in datasets:
    path = native / platform / (name + ".jsonl")
    raw = path.read_bytes()
    rows = [json.loads(line) for line in raw.splitlines()]
    plan = plans[plan_name]
    selected = None
    for manifest_path in manifests[platform]:
        manifest = read_json(manifest_path)
        if all(row["binary_sha256"] ==
               manifest["variants"][plan["variants"][row["variant"]]["binary"]]["binary_sha256"]
               for row in rows):
            selected = manifest_path, manifest
            break
    assert selected is not None, "no matching manifest: " + str(path)
    manifest_path, manifest = selected
    result = validate(rows, plan, manifest, repo if name == "grid" else None)
    result["dataset"] = str(path.relative_to(repo))
    result["manifest"] = str(manifest_path.relative_to(repo))
    if name == "grid":
        archived = read_json(native / platform / "validation.json")
        for key, artifact in (
            ("input", path),
            ("plan", experiment / "plans/backend-grid.json"),
            ("manifest", manifest_path),
        ):
            digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
            assert digest == archived[key + "_sha256"], (platform, key)
        print(platform + ": main dataset and recorded source hashes pass", flush=True)
    if name != "smoke":
        summary_name = "summary.json" if name == "grid" else name + "-summary.json"
        recorded = read_json(native / platform / summary_name)
        computed = analyze(rows)
        equivalent(computed, recorded["comparisons"])
        comparison_count += len(computed)
        result["comparisons_reproduced"] = len(computed)
    results.append(result)
    print(platform + "/" + name + ": " + str(len(rows)) + " trials pass", flush=True)

expected_cases = set(itertools.product((1, 16, 513), (1, 2), (False, True),
                                     ("normal", "skip", "short", "eintr", "zero")))
correctness_count = 0
for variant in ("vectored", "coalesce", "pool"):
    record = read_json(native / "linux" / (variant + "-correctness.json"))
    assert record["purpose"] == "correctness_only"
    cases = record["cases"]
    actual = {(case["pages"], case["writers"], case["durable"], case["fault"]) for case in cases}
    assert len(cases) == 60 and actual == expected_cases
    assert all(case["passed"] is True for case in cases)
    correctness_count += len(cases)
result = {
    "status": "pass",
    "datasets": results,
    "trials_audited": sum(row["trials"] for row in results),
    "paired_comparisons_reproduced": comparison_count,
    "archived_linux_correctness_records": correctness_count,
    "source_hashes_checked_for_main_grids": True,
    "experimental_patch_hashes_checked": len(patch_checks),
    "experimental_patches": patch_checks,
    "summary_numeric_relative_tolerance": 1e-12,
    "scope": "Archived data and source audit; no new Linux execution or performance measurements.",
}
output.write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({key: value for key, value in result.items() if key != "datasets"}), flush=True)
