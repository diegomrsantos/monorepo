#!/usr/bin/env python3
"""Check complete output and injected I/O faults. These are not timing results."""

import argparse
import itertools
import json
import os
import pathlib
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--data-root", required=True)
    parser.add_argument("--io-check", help="Linux check_io.c shared library")
    parser.add_argument("--strategy", action="append", choices=("vectored", "coalesce", "pool"))
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    rows = []
    cases = itertools.product(args.strategy or ("vectored", "coalesce", "pool"), (1, 16, 513), (1, 2), (False, True))
    for strategy, pages, writers, durable in cases:
        modes = ("normal", "skip", "short", "eintr", "zero") if args.io_check else ("normal",)
        for mode in modes:
            command = [args.binary, "--root", args.data_root, "--strategy", strategy,
                       "--layer", "paged", "--file-mib", "6", "--pages", str(pages),
                       "--writers", str(writers), "--warmup-ops", "2", "--source-mib", "1"]
            if durable:
                command.append("--durable")
            env = os.environ.copy()
            env.pop("LD_PRELOAD", None)
            env.pop("COMMONWARE_IO_FAULT", None)
            if args.io_check:
                env["LD_PRELOAD"] = args.io_check
                if mode != "normal":
                    env["COMMONWARE_IO_FAULT"] = mode
            run = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
            metrics = [json.loads(line[9:]) for line in run.stderr.splitlines() if line.startswith("IO_CHECK ")]
            result = None
            if mode in ("skip", "zero"):
                assert run.returncode != 0 and not run.stdout.strip(), (command, mode, run)
                if mode == "skip":
                    assert metrics[0]["skipped"] == writers, metrics
                    assert ("readback differs" in run.stderr or
                            "unexpected physical length" in run.stderr), run.stderr
            else:
                assert run.returncode == 0, (command, mode, run.stdout, run.stderr)
                result = json.loads(run.stdout)
                expected_ops = (6 * 1024 * 1024 // writers // (pages * 4096)) * writers
                assert result["ops"] == expected_ops > 0, result
                assert result["verified_pages"] == expected_ops * pages, result
                assert result["file_bytes"] == result["verified_pages"] * 4096, result
                assert result["bytes_per_write"] == pages * (4096 - 12), result
                if args.io_check:
                    assert len(metrics) == 1 and metrics[0]["writes"] > 0, metrics
                    if durable:
                        assert metrics[0]["barriers"] >= expected_ops, (result, metrics)
                    if mode == "short":
                        assert metrics[0]["shortened"] == 1, metrics
                    if mode == "eintr":
                        assert metrics[0]["interrupted"] == 1, metrics
            rows.append({"strategy": strategy, "pages": pages, "writers": writers,
                         "durable": durable, "fault": mode, "passed": True,
                         "io": metrics, "verified_pages": result and result["verified_pages"]})
        print(f"passed: {strategy} pages={pages} writers={writers} durable={durable}", flush=True)
    args.output.write_text(json.dumps({"purpose": "correctness_only", "cases": rows}, indent=2) + "\n")
    print(f"{len(rows)} checks passed")


if __name__ == "__main__":
    main()
