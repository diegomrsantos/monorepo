#!/usr/bin/env python3
"""Paired geometric mean ratios and a percentile bootstrap over whole blocks."""

import argparse
import json
import math
import pathlib
import random
import statistics


def estimate(ratios, seed=20260906):
    logs = [math.log(x) for x in ratios]
    point = math.exp(statistics.mean(logs))
    if len(logs) < 5:
        return {"ratio": point, "ci95": None, "n": len(logs), "pairs": ratios}
    rng = random.Random(seed)
    samples = sorted(math.exp(statistics.mean(rng.choices(logs, k=len(logs)))) for _ in range(10000))
    return {"ratio": point, "ci95": [samples[250], samples[9749]], "n": len(logs), "pairs": ratios}


def analyze(rows, baseline="vectored"):
    groups = {}
    for row in rows:
        key = (row["phase"], row["case"])
        label = row.get("variant", row["strategy"])
        trial = (row["repetition"], label)
        group = groups.setdefault(key, {})
        if trial in group:
            raise ValueError(f"duplicate trial: {key}, {trial}")
        group[trial] = row
    summaries = []
    for (phase, case), trials in sorted(groups.items()):
        reps = sorted({rep for rep, _ in trials})
        labels = sorted({label for _, label in trials})
        if baseline not in labels or any((rep, label) not in trials for rep in reps for label in labels):
            raise ValueError(f"incomplete comparison: {phase}, {case}")
        for label in labels:
            if label == baseline:
                continue
            paired = [(trials[rep, baseline], trials[rep, label]) for rep in reps]
            for a, b in paired:
                for key in ("seed", "layer", "pages", "writers", "durable", "file_bytes",
                            "bytes_per_write", "source_count"):
                    if a[key] != b[key]:
                        raise ValueError(f"unequal workload {key}: {phase}, {case}, {label}")
                for key in ("fragments", "layout", "independent_segments", "platform", "architecture"):
                    if a.get(key) != b.get(key):
                        raise ValueError(f"unequal workload {key}: {phase}, {case}, {label}")
                if a["layer"] == "paged" and a["ops"] != b["ops"]:
                    raise ValueError("fixed work differs")
            summaries.append({"phase": phase, "case": case, "variant": label,
                "baseline_mib_per_second": statistics.median(a["mib_per_second"] for a, _ in paired),
                "candidate_mib_per_second": statistics.median(b["mib_per_second"] for _, b in paired),
                "throughput": estimate([b["mib_per_second"] / a["mib_per_second"] for a, b in paired]),
                "cpu_cost": estimate([b["cpu_ns_per_op"] / a["cpu_ns_per_op"] for a, b in paired])})
    return summaries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=pathlib.Path)
    parser.add_argument("--baseline", default="vectored")
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    rows = [json.loads(line) for path in args.inputs for line in path.read_text().splitlines()]
    result = analyze(rows, args.baseline)
    args.output.write_text(json.dumps({"method": "paired geometric mean; 10000 whole-block bootstrap resamples; percentile 95% interval",
                                       "scope": "process repetitions on one machine; conditional on this workload and build",
                                       "comparisons": result}, indent=2) + "\n")
    for row in result:
        print(f"{row['case']} {row['variant']}: throughput {row['throughput']}; CPU {row['cpu_cost']}")


if __name__ == "__main__":
    main()
