#!/usr/bin/env python3
"""Snapshot only NewMemo's own processes; footprint excludes shared clean mappings."""
import argparse
import json
import pathlib
import re
import subprocess
import unicodedata

parser = argparse.ArgumentParser()
parser.add_argument("label")
parser.add_argument("--output", type=pathlib.Path)
parser.add_argument("--max-app-mib", type=float)
parser.add_argument("--max-finder-mib", type=float)
args = parser.parse_args()
rows = subprocess.check_output(["ps", "-axo", "pid=,rss=,comm="], text=True)
processes = []
for line in rows.splitlines():
    fields = line.strip().split(None, 2)
    if len(fields) != 3:
        continue
    pid, rss, command = fields
    command = unicodedata.normalize("NFC", command)
    if "/새 메모.app/Contents/" not in command:
        continue
    if not command.endswith(("/MacOS/NewMemo", "/MacOS/NewMemoFinder")):
        continue
    result = subprocess.run(["/usr/bin/footprint", "-p", pid, "-f", "bytes"],
                            capture_output=True, text=True, timeout=20)
    footprint = re.search(r"phys_footprint:\s+(\d+) B", result.stdout)
    peak = re.search(r"phys_footprint_peak:\s+(\d+) B", result.stdout)
    processes.append({"pid": int(pid), "role": "finder" if command.endswith("Finder") else "app",
                      "rssBytes": int(rss) * 1024,
                      "footprintBytes": int(footprint[1]) if footprint else None,
                      "peakFootprintBytes": int(peak[1]) if peak else None})
if not processes:
    raise SystemExit("새 메모 앱 또는 Finder 확장을 먼저 실행해 주세요.")
data = {"label": args.label, "processes": processes,
        "totalFootprintBytes": sum(p["footprintBytes"] or 0 for p in processes)}
failures = []
for process in processes:
    limit = args.max_app_mib if process["role"] == "app" else args.max_finder_mib
    if limit is not None:
        if process["footprintBytes"] is None or process["footprintBytes"] > limit * 1024 * 1024:
            failures.append(f'{process["role"]} PID {process["pid"]}: {limit} MiB limit')
data["failures"] = failures
encoded = json.dumps(data, ensure_ascii=False, indent=2)
if args.output:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(encoded + "\n", encoding="utf-8")
print(encoded)
raise SystemExit(1 if failures else 0)
