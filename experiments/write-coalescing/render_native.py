#!/usr/bin/env python3
"""Render the archived platform comparisons without rerunning any benchmarks."""

import argparse
import json
import math
import pathlib


def interval(metric):
    low, high = metric["ci95"]
    return f"{metric['ratio']:.3f} [{low:.3f}, {high:.3f}]"


def label(case):
    size = {4096: "4 KiB", 65536: "64 KiB", 1048576: "1 MiB"}[case["write_bytes"]]
    detail = "sync" if case.get("durable") else "buffered"
    if case.get("independent_segments"):
        detail += ", separate allocations"
    if case.get("source_mib"):
        detail += ", rotating 16 MiB"
    return f"{size}, {case['segments']} segments, {detail}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", type=pathlib.Path, default=pathlib.Path(__file__).parent / "results/native")
    args = parser.parse_args()
    root = pathlib.Path(__file__).parent
    plan = json.loads((root / "plans/backend-grid.json").read_text())
    datasets = {platform: json.loads((args.results / platform / "summary.json").read_text())
                for platform in ("linux", "macos")}
    indexed = {platform: {(row["case"], row["variant"]): row for row in data["comparisons"]}
               for platform, data in datasets.items()}
    lines = ["# Complete native comparisons", "",
             "Each cell reports a paired geometric mean ratio and its percentile 95% bootstrap interval.",
             "Throughput above 1 favors coalescing; CPU cost below 1 favors coalescing.",
             "The baseline column is median MiB/s. Ratios are not quotients of these medians.",
             "Intervals describe seven process repetitions on one machine and one build; they are not simultaneous guarantees.", ""]
    for platform in datasets:
        lines.extend([f"## {platform}", "",
            "| Workload | Vectored MiB/s | Heap throughput | Heap CPU cost | Pool throughput | Pool CPU cost |",
            "| --- | ---: | ---: | ---: | ---: | ---: |"])
        for case in plan["cases"]:
            heap = indexed[platform][case["id"], "coalesce"]
            pool = indexed[platform][case["id"], "pool"]
            lines.append(f"| {label(case)} | {heap['baseline_mib_per_second']:.1f} | {interval(heap['throughput'])} | {interval(heap['cpu_cost'])} | {interval(pool['throughput'])} | {interval(pool['cpu_cost'])} |")
        lines.append("")
    (args.results / "TABLES.md").write_text("\n".join(lines).rstrip() + "\n")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import Normalize

    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 11,
                         "svg.fonttype": "none", "svg.hashsalt": "commonware-native-20260906"})
    fig, axes = plt.subplots(2, 2, figsize=(10, 9), constrained_layout=False)
    sizes = [4096, 65536, 1048576]
    segments = [1, 8, 32, 128, 256, 1024, 1025]
    norm = Normalize(vmin=-math.log2(3), vmax=math.log2(3))
    platform_titles = {"linux": "Linux · AMD EPYC 8024P", "macos": "macOS · Apple M1 Pro"}
    for row_index, platform in enumerate(datasets):
        for col_index, variant in enumerate(("coalesce", "pool")):
            ax = axes[row_index, col_index]
            cells = [[indexed[platform][f"bytes-{size}-segments-{count}", variant]["throughput"]
                      for size in sizes] for count in segments]
            values = [[math.log2(cell["ratio"]) for cell in row] for row in cells]
            im = ax.imshow(values, cmap="RdBu", norm=norm, aspect="auto")
            for y, row in enumerate(cells):
                for x, cell in enumerate(row):
                    uncertain = cell["ci95"][0] <= 1 <= cell["ci95"][1]
                    color = "white" if abs(math.log2(cell["ratio"])) > 0.85 else "#202830"
                    ax.text(x, y, f"{cell['ratio']:.2f}×" + ("*" if uncertain else ""),
                            ha="center", va="center", color=color, fontsize=11)
            ax.set_xticks(range(3), ["4 KiB", "64 KiB", "1 MiB"])
            ax.set_yticks(range(7), [str(n) for n in segments])
            ax.set_ylabel("Segments")
            ax.set_xlabel("Total bytes per write")
            ax.set_title(platform_titles[platform] + "\n" + ("Heap coalescing" if variant == "coalesce" else "Pool coalescing"), fontsize=12, pad=10)
            ax.set_xticks([0.5, 1.5], minor=True)
            ax.set_yticks([n + 0.5 for n in range(6)], minor=True)
            ax.grid(which="minor", color="white", linewidth=1)
            ax.tick_params(which="both", length=0)
            for spine in ax.spines.values():
                spine.set_visible(False)
    fig.suptitle("Coalescing helps some write shapes and hurts others", fontsize=17, x=0.50, y=0.98)
    fig.text(0.50, 0.936, "Candidate ÷ vectored throughput · buffered overwrites · seven paired process runs", ha="center", fontsize=11)
    fig.subplots_adjust(top=0.855, bottom=0.20, left=0.08, right=0.87, hspace=0.55, wspace=0.28)
    bar = fig.colorbar(im, cax=fig.add_axes([0.90, 0.26, 0.02, 0.49]))
    bar.set_ticks([math.log2(x) for x in (0.5, 1, 2, 3)], labels=["0.5×", "1×", "2×", "3×"])
    bar.set_label("Throughput ratio")
    fig.text(0.08, 0.03, "* The 95% paired bootstrap interval includes 1. Full intervals and controls are in TABLES.md.\n"
             "One reused input allocation; 64 MiB cyclic file; one outstanding write.\n"
             "Compare strategies within each machine. These measurements do not isolate an OS effect.", fontsize=10, linespacing=1.5)
    fig.savefig(args.results / "throughput-grid.png", dpi=180, facecolor="white")
    svg = args.results / "throughput-grid.svg"
    fig.savefig(svg, facecolor="white", metadata={"Date": None})
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
    print(args.results / "throughput-grid.png")


if __name__ == "__main__":
    main()
