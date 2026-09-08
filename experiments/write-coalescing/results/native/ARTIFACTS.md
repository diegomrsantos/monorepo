# Native evidence inventory

This directory contains the records needed to audit the measurements and
recompute the report. Raw trials, plans, manifests, patches, and archived audit
results retain their original bytes.

| Evidence | Purpose |
| --- | --- |
| `linux/grid.jsonl`, `macos/grid.jsonl` | 672 measured trials per platform, with input parameters, commands, completed work, timing, and recorded executable identities |
| `summary.json` in each platform directory | All 64 paired candidate comparisons, individual ratios, absolute rates, and intervals |
| `validation.json` in each platform directory | Archived passing audit with input, plan, and manifest hashes |
| Linux `aa*.jsonl` and their summaries | All three baseline pilots, including the two earlier configurations with more noise |
| Mac `aa.jsonl`, `earlier-aa.jsonl`, and summaries | Final and earlier pilots, with their corresponding manifests |
| `smoke.jsonl` in each platform directory | 96 correctness trials per platform, excluded from performance analysis |
| Linux `*-correctness.json` | 180 native correctness checks across three builds |
| Linux environment, CPU placement, RAID preparation, and final state records | Measurement conditions and changes made before the main grid |
| Mac environment records | Hardware and environment before and after measurement |
| Linux `binaries/manifest.json`, Mac `manifest.json`, and patches | Compiler identity, source hashes, build commands, experimental changes, and executable hashes |
| `TABLES.md`, `throughput-grid.png`, `throughput-grid.svg` | Generated views of the paired summaries |

The Rust benchmark sources are included under
`runtime/src/storage/benches`. The frozen main, smoke, and baseline pilot plans
are under `experiments/write-coalescing/plans`. Their paths and hashes can be
checked against the build and audit manifests.

Each grid has 32 cases, three variants, and seven repetitions. The selected
examples in the report are backed by the complete grids. No main trial was
discarded because of its timing result.

Executable archives and diagnostic profiler captures are outside this source
package. Recomputing the numerical results uses the versioned records and
Python's standard library. The manifests identify the executables used for
measurement; a later rebuild should record its own identity.

The Mac build manifest predates the helper's runtime manifest hash field.
The following `runtime/Cargo.toml` hash was recorded separately after
measurement, rather than inserted retrospectively into the build record:

```text
e73d5e0f53b189747ded6f7c2022809ecb4ff878ee7c1b8b7ec9388f1327f40e
```

Environment records are retained for interpreting the measurements. The Mac
copies already omit the unrelated process inventory. Neither a successful
readback nor these records establish behavior under power loss.
