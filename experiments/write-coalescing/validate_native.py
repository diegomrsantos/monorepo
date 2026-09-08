#!/usr/bin/env python3
"""Audit a complete uniform matrix against its frozen plan and build manifest."""

import argparse
import datetime
import hashlib
import json
import math
import pathlib
import random


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(rows, plan, manifest, repo=None):
    rng = random.Random(plan["order_seed"])
    blocks = [(rep, case) for rep in range(plan["repetitions"]) for case in plan["cases"]]
    rng.shuffle(blocks)
    expected = []
    for rep, case in blocks:
        labels = list(plan["variants"])
        rng.shuffle(labels)
        expected.extend((rep, case, label) for label in labels)
    require(len(rows) == len(expected), f"expected {len(expected)} trials, got {len(rows)}")
    require(len({row["platform"] for row in rows}) == 1, "mixed platforms")
    require(len({row["architecture"] for row in rows}) == 1, "mixed architectures")
    roots = set()
    previous = None
    for sequence, (row, (rep, case, label)) in enumerate(zip(rows, expected), 1):
        prefix = f"trial {sequence}: "
        config = {**plan["defaults"], **case}
        spec = plan["variants"][label]
        size, fragments = config["write_bytes"], config["segments"]
        require(config["writers"] == 1, "this audit expects the frozen single writer plan")
        slots = config["file_mib"] * 1024**2 // size
        sources = max(1, math.ceil(config["source_mib"] * 1024**2 / size))
        fields = {
            "phase": plan["name"], "sequence": sequence, "repetition": rep,
            "case": case["id"], "variant": label, "seed": plan["data_seed"] + rep,
            "strategy": spec["strategy"], "layer": config["layer"], "writers": 1,
            "bytes_per_write": size, "fragments": fragments, "pages": None,
            "layout": "uniform", "durable": config.get("durable", False),
            "independent_segments": config.get("independent_segments", False),
            "file_bytes": slots * size, "source_count": sources,
            "source_bytes_per_writer": sources * size,
            "warmup_ms": config["warmup_ms"], "requested_duration_ms": config["duration_ms"],
            "binary_sha256": manifest["variants"][spec["binary"]]["binary_sha256"],
            "verification": "all_final_written_slots_bytes_and_exact_length",
            "verified_pages": 0,
        }
        for key, value in fields.items():
            require(row[key] == value, prefix + f"unexpected {key}: {row[key]!r} != {value!r}")
        for metric in ("ops", "wall_seconds", "cpu_seconds", "cpu_ns_per_op", "mib_per_second"):
            require(math.isfinite(row[metric]) and row[metric] > 0, prefix + f"invalid {metric}")
        require(isinstance(row["ops"], int) and row["ops"] % 8 == 0, prefix + "invalid completed work")
        require(row["wall_seconds"] >= config["duration_ms"] / 1000, prefix + "short measured interval")
        require(row["verified_bytes"] == min(row["ops"], slots) * size, prefix + "incomplete readback")
        rates = {
            "ops_per_second": row["ops"] / row["wall_seconds"],
            "mib_per_second": row["ops"] * size / 1024**2 / row["wall_seconds"],
            "cpu_ns_per_op": row["cpu_seconds"] * 1e9 / row["ops"],
        }
        for key, value in rates.items():
            require(math.isclose(row[key], value, rel_tol=1e-9), prefix + f"inconsistent {key}")
        require(row["pool_size_eligible"] == (size <= row["pool_max_size"]), prefix + "pool metadata differs")
        command = row["command"]
        require(pathlib.Path(command[0]).name == spec["binary"], prefix + "wrong executable")
        require(command[1] == "--root", prefix + "missing data root")
        roots.add(command[2])
        expected_command = command[:3] + ["--strategy", spec["strategy"], "--seed", str(plan["data_seed"] + rep)]
        for key, value in config.items():
            if key == "id":
                continue
            flag = "--" + key.replace("_", "-")
            if isinstance(value, bool):
                if value:
                    expected_command.append(flag)
            else:
                expected_command.extend([flag, str(value)])
        require(command == expected_command, prefix + "command differs from plan")
        completed = datetime.datetime.fromisoformat(row["completed_at"])
        require(previous is None or completed > previous, prefix + "completion order differs")
        previous = completed
    require(len(roots) == 1, "data roots differ")
    if repo is not None:
        hashes = {**manifest["benchmark_sources"], "Cargo.lock": manifest["cargo_lock_sha256"],
                  "runtime/src/storage/tokio/blob.rs": manifest["backend_source_sha256"]}
        if "runtime_manifest_sha256" in manifest:
            hashes["runtime/Cargo.toml"] = manifest["runtime_manifest_sha256"]
        for path, expected_hash in hashes.items():
            actual = hashlib.sha256((repo / path).read_bytes()).hexdigest()
            require(actual == expected_hash, f"source differs from build: {path}")
    return {"status": "pass", "phase": plan["name"], "trials": len(rows),
            "cases": len(plan["cases"]), "variants": list(plan["variants"]),
            "repetitions": plan["repetitions"], "platform": rows[0]["platform"],
            "first_completed_at": rows[0]["completed_at"], "last_completed_at": rows[-1]["completed_at"],
            "verified_bytes_total": sum(row["verified_bytes"] for row in rows),
            "checks": "exact plan and randomized order; paired inputs; recorded binary identities; metric arithmetic; all final written slots; source hashes when a repository is supplied"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=pathlib.Path)
    parser.add_argument("--plan", required=True, type=pathlib.Path)
    parser.add_argument("--manifest", required=True, type=pathlib.Path)
    parser.add_argument("--repo", type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    rows = [json.loads(line) for line in args.input.read_text().splitlines()]
    result = validate(rows, json.loads(args.plan.read_text()), json.loads(args.manifest.read_text()), args.repo)
    for name, path in (("input", args.input), ("plan", args.plan), ("manifest", args.manifest)):
        result[name + "_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
