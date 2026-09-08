# Write coalescing experiment

This experiment supplies measurements for the benchmark prerequisite in
[issue #3440](https://github.com/commonwarexyz/monorepo/issues/3440).
It compares the ordinary Tokio storage backend with heap and pool coalescing
across write sizes and fragment counts on native Linux and macOS.

Start with [the results](NATIVE_RESULTS.md). The report shows where coalescing
helped, where it hurt, and which environment and workload limits apply.

- [Measurement protocol and reproduction](BACKEND_PROTOCOL.md)
- [Complete comparisons](results/native/TABLES.md)
- [Evidence inventory](results/native/ARTIFACTS.md)
- [Frozen measurement plan](plans/backend-grid.json)

The Rust harness lives in `runtime/src/storage/benches/coalescing.rs`.
It follows the existing standalone storage benchmark pattern and reports
completed work over its own measured interval. The scripts retain independent
process repetitions and their randomized order. These results do not select a
production heuristic or change the production backend.
