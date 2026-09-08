#!/usr/bin/env python3
"""Capture relevant native benchmark metadata without account credentials."""

import argparse
import datetime
import hashlib
import json
import pathlib
import platform
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-root", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    data = {"recorded_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "platform": platform.platform(), "data_root": str(args.data_root.resolve()),
            "disk_usage": shutil.disk_usage(args.data_root)._asdict(), "commands": {}, "sysfs": {}}
    commands = [["uname", "-a"], ["rustc", "+1.98.0", "-Vv"], ["cargo", "+1.98.0", "-V"],
                ["git", "rev-parse", "HEAD"], ["git", "status", "--short"],
                ["ps", "-axo", "pid,comm,%cpu,%mem"]]
    if platform.system() == "Linux":
        commands += [["lscpu", "-J"], ["lscpu", "-e=CPU,CORE,SOCKET,NODE,ONLINE"],
                     ["systemd-detect-virt"], ["findmnt", "-T", str(args.data_root), "-J"],
                     ["lsblk", "-J", "-o", "NAME,TYPE,PKNAME,MODEL,SIZE,FSTYPE,MOUNTPOINTS,ROTA"],
                     ["cat", "/proc/mdstat"], ["cat", "/proc/meminfo"], ["cat", "/proc/mounts"],
                     ["perf", "stat", "-e", "task-clock,cycles,instructions", "true"]]
        patterns = ["/sys/block/*/queue/write_cache", "/sys/block/*/queue/fua", "/sys/block/*/queue/scheduler",
                    "/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor", "/sys/devices/system/cpu/smt/active",
                    "/sys/devices/system/cpu/cpufreq/boost", "/proc/sys/kernel/perf_event_paranoid",
                    "/proc/sys/vm/dirty_*", "/sys/fs/cgroup/cpu.max", "/sys/fs/cgroup/cpuset.cpus.effective"]
        for pattern in patterns:
            import glob
            for name in glob.glob(pattern):
                path = pathlib.Path(name)
                try:
                    data["sysfs"][name] = path.read_text().strip()
                except OSError as error:
                    data["sysfs"][name] = str(error)
        for device in pathlib.Path("/sys/class/nvme").glob("nvme*"):
            command = ["nvme", "id-ctrl", "/dev/" + device.name, "-o", "json"]
            try:
                run = subprocess.run(command, capture_output=True, text=True, timeout=15)
                if run.returncode == 0:
                    raw = json.loads(run.stdout)
                    data.setdefault("nvme", {})[device.name] = {k: raw.get(k) for k in ("mn", "fr", "vid", "ssvid", "vwc", "oncs", "fna")}
                else:
                    data["commands"][" ".join(command)] = {"exit_code": run.returncode, "stderr": run.stderr}
            except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
                data["commands"][" ".join(command)] = {"error": str(error)}
            commands += [["nvme", "get-feature", "/dev/" + device.name, "-f", "6", "-H"]]
    else:
        commands += [["sysctl", "machdep.cpu.brand_string", "hw.memsize", "hw.physicalcpu", "hw.logicalcpu",
                      "hw.perflevel0.physicalcpu", "hw.perflevel1.physicalcpu"],
                     ["sw_vers"], ["vm_stat"], ["df", "-h", str(args.data_root)], ["pmset", "-g", "batt"]]
    for command in commands:
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=20)
            data["commands"][" ".join(command)] = {"exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
        except (OSError, subprocess.TimeoutExpired) as error:
            data["commands"][" ".join(command)] = {"error": str(error)}
    data["plan_sha256"] = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                           for path in pathlib.Path(__file__).parent.joinpath("plans").glob("backend-*.json")}
    args.output.write_text(json.dumps(data, indent=2) + "\n")


if __name__ == "__main__":
    main()
