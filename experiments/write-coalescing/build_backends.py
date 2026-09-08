#!/usr/bin/env python3
"""Build three fixed backend policies in a disposable checkout; restore the source."""

import argparse
import difflib
import hashlib
import json
import pathlib
import shutil
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--toolchain", default="1.98.0")
    args = parser.parse_args()
    repo = pathlib.Path.cwd()
    relative = "runtime/src/storage/tokio/blob.rs"
    source = repo / relative
    original = source.read_bytes()
    committed = subprocess.check_output(["git", "show", f"HEAD:{relative}"])
    if original != committed:
        parser.error("backend already has local changes; use a disposable clean checkout")
    args.output.mkdir(parents=True, exist_ok=True)
    if (args.output / "manifest.json").exists():
        parser.error("output contains a prior build; choose a new output directory")
    anchor = "        let name = sync.then(|| self.name.clone());\n        task::spawn_blocking(move || {\n"
    if original.decode().count(anchor) != 1:
        parser.error("backend changed; review the insertion point before benchmarking")
    manifest = {"base_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
                "backend_source_sha256": sha(original),
                "rustc": subprocess.check_output(["rustc", f"+{args.toolchain}", "-Vv"], text=True),
                "cargo_lock_sha256": sha((repo / "Cargo.lock").read_bytes()),
                "runtime_manifest_sha256": sha((repo / "runtime/Cargo.toml").read_bytes()),
                "scope": "ordinary Tokio storage backend; fixed policies; no heuristic", "variants": {}}
    try:
        for variant in ("vectored", "coalesce", "pool"):
            replacement = anchor
            if variant == "coalesce":
                replacement += "            let bufs: IoBufs = bufs.coalesce().into();\n"
            elif variant == "pool":
                replacement = anchor.replace("        task::spawn_blocking", "        let pool = self.pool.clone();\n        task::spawn_blocking")
                replacement += "            let bufs: IoBufs = bufs.coalesce_with_pool(&pool).into();\n"
            changed = original.decode().replace(anchor, replacement)
            source.write_text(changed)
            patch = "".join(difflib.unified_diff(original.decode().splitlines(True), changed.splitlines(True),
                                                  fromfile="a/" + relative, tofile="b/" + relative))
            (args.output / f"{variant}.patch").write_text(patch)
            command = ["cargo", f"+{args.toolchain}", "bench", "--locked", "-p", "commonware-runtime",
                       "--bench", "storage_coalescing", "--no-run", "--message-format=json"]
            with (args.output / f"{variant}-build.jsonl").open("w") as log:
                subprocess.run(command, stdout=log, check=True)
            artifacts = [json.loads(line) for line in (args.output / f"{variant}-build.jsonl").read_text().splitlines()]
            executable = next(row["executable"] for row in artifacts
                              if row.get("reason") == "compiler-artifact" and row["target"]["name"] == "storage_coalescing"
                              and row.get("executable"))
            destination = args.output / variant
            shutil.copy2(executable, destination)
            manifest["variants"][variant] = {"binary_sha256": sha(destination.read_bytes()),
                                            "backend_source_sha256": sha(changed.encode()),
                                            "patch_sha256": sha(patch.encode()), "command": command}
            print(f"built {variant}", flush=True)
    finally:
        source.write_bytes(original)
    manifest["benchmark_sources"] = {str(path.relative_to(repo)): sha(path.read_bytes())
                                    for path in sorted((repo / "runtime/src/storage/benches").glob("*coalescing*.rs"))}
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
