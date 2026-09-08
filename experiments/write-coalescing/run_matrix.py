#!/usr/bin/env python3
"""Run randomized, paired write trials. Uses only the Python standard library."""

import argparse
import datetime
import json
import pathlib
import random
import math
import hashlib
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--plan", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--data-root", default="/data")
    parser.add_argument("--binary-dir", type=pathlib.Path)
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        parser.error("output already exists; choose a new file to preserve prior trials")

    order_rng = random.Random(plan.get("order_seed", 20260906))
    groups = [(rep, case) for rep in range(plan["repetitions"]) for case in plan["cases"]]
    order_rng.shuffle(groups)
    sequence = 0
    variants = plan.get("variants", {s: s for s in ("vectored", "coalesce", "pool")})
    variants = {label: ({"strategy": spec} if isinstance(spec, str) else spec)
                for label, spec in variants.items()}
    if not variants or any(spec["strategy"] not in ("vectored", "coalesce", "pool") for spec in variants.values()):
        parser.error("variants must map labels to known strategies")
    for spec in variants.values():
        spec["path"] = str(args.binary_dir / spec["binary"]) if "binary" in spec else args.binary
        spec["sha256"] = hashlib.sha256(pathlib.Path(spec["path"]).read_bytes()).hexdigest()
    total = len(groups) * len(variants)
    with args.output.open("x") as output:
        for rep, case in groups:
            labels = list(variants)
            order_rng.shuffle(labels)
            for label in labels:
                strategy = variants[label]["strategy"]
                sequence += 1
                config = {**plan.get("defaults", {}), **case}
                case_id = config.pop("id")
                command = [variants[label]["path"], "--root", args.data_root, "--strategy", strategy]
                command += ["--seed", str(plan.get("data_seed", 42) + rep)]
                for key, value in config.items():
                    flag = "--" + key.replace("_", "-")
                    if isinstance(value, bool):
                        if value:
                            command.append(flag)
                    else:
                        command.extend([flag, str(value)])
                time.sleep(plan.get("settle_seconds", 0))
                started = time.monotonic()
                completed = subprocess.run(command, text=True, capture_output=True,
                                           timeout=plan.get("trial_timeout_seconds", 180))
                if completed.returncode:
                    raise RuntimeError(f"trial failed: {command!r}\n{completed.stdout}\n{completed.stderr}")
                lines = [line for line in completed.stdout.splitlines() if line.startswith("{")]
                if len(lines) != 1:
                    raise RuntimeError(f"expected one JSON result: {completed.stdout}")
                result = json.loads(lines[0])
                for metric in ("ops", "wall_seconds", "cpu_ns_per_op", "mib_per_second", "verified_bytes"):
                    if not math.isfinite(result[metric]) or result[metric] <= 0:
                        raise ValueError(f"invalid metric {metric}: {result}")
                if result["strategy"] != strategy:
                    raise ValueError(f"wrong strategy returned: {result}")
                result.update({
                    "variant": label,
                    "binary_sha256": variants[label]["sha256"],
                    "phase": plan["name"], "case": case_id, "repetition": rep,
                    "sequence": sequence, "command": command,
                    "completed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    "trial_seconds": time.monotonic() - started,
                })
                output.write(json.dumps(result, sort_keys=True) + "\n")
                output.flush()
                print(f"{sequence}/{total} {case_id} r{rep + 1} {label}: "
                      f"{result['mib_per_second']:.0f} MiB/s, "
                      f"{result['cpu_ns_per_op']:.0f} CPU ns/op", flush=True)


if __name__ == "__main__":
    main()
