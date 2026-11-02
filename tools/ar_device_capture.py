#!/usr/bin/env python3
"""Capture Android reader memory/thermal evidence without changing device state.

This does not measure AR/Filament frame pacing or certify visual correctness.
Use Perfetto/Instruments separately for authoritative renderer performance.
"""
import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import re
import subprocess
import time


def parse_total_pss_kib(text):
    """Parse one process report, never a missing value as 0."""
    for pattern in (r"^\s*TOTAL PSS:\s*([\d,]+)\b", r"^\s*TOTAL\s+([\d,]+)\b"):
        match = re.search(pattern, text, re.MULTILINE)
        if match:
            return int(match.group(1).replace(",", ""))
    return None


def parse_thermal_status(text):
    match = re.search(r"^\s*Thermal Status:\s*(\d+)\s*$", text, re.MULTILINE)
    return int(match.group(1)) if match else None


def summarize(samples):
    memory = [s["total_pss_kib"] for s in samples if s["total_pss_kib"] is not None]
    return {
        "memory_metric": "Android summed PSS (KiB) for pidof(package) processes; excludes differently named services; not iOS physical footprint",
        "memory_first_kib": samples[0]["total_pss_kib"] if samples else None,
        "memory_peak_kib": max(memory) if memory else None,
        "memory_last_kib": samples[-1]["total_pss_kib"] if samples else None,
        "memory_samples": len(memory),
        "frame_pacing": None,
        "camera_ready_ms": None,
        "model_ready_ms": None,
        "valid_placement_ms": None,
        "visual_acceptance": "UNVERIFIED",
        "performance_acceptance": "UNVERIFIED",
    }


def command(argv):
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=30)
        return {"exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"exit_code": None, "stdout": "", "stderr": str(error)}


def adb(serial, *args):
    return command(["adb", "-s", serial, *args])


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def take_sample(serial, package, elapsed):
    pid = adb(serial, "shell", "pidof", package)
    pids = [value for value in pid["stdout"].split() if value.isdigit()]
    if pid["exit_code"] != 0:
        pids = []
    # Query each PID separately: package-scoped output can contain multiple TOTAL rows.
    meminfo = {value: adb(serial, "shell", "dumpsys", "meminfo", value)
               for value in dict.fromkeys(pids)}
    process_pss = {value: parse_total_pss_kib(report["stdout"])
                   if report["exit_code"] == 0 else None
                   for value, report in meminfo.items()}
    thermal = adb(serial, "shell", "dumpsys", "thermalservice")
    # A closed/restarted app is recorded explicitly. Never reuse the last PSS sample.
    return {
        "elapsed_seconds": elapsed,
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "process_ids": list(meminfo),
        "process_pss_kib": process_pss,
        "total_pss_kib": sum(process_pss.values())
        if process_pss and all(value is not None for value in process_pss.values()) else None,
        "thermal_status": parse_thermal_status(thermal["stdout"])
        if thermal["exit_code"] == 0 else None,
        "raw": {"pid": pid, "meminfo": meminfo, "thermal": thermal},
    }


def finite_number(value, *, positive=False):
    number = float(value)
    if not math.isfinite(number) or (number <= 0 if positive else number < 0):
        raise argparse.ArgumentTypeError("must be finite and " + ("positive" if positive else "nonnegative"))
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True, help="Explicit adb device serial; never auto-selects")
    parser.add_argument("--output", required=True, type=Path, help="New evidence directory; never overwritten")
    parser.add_argument("--package", default="com.motnhi.app")
    parser.add_argument("--build-mode", required=True, choices=["debug", "profile", "release"])
    parser.add_argument("--character", required=True)
    parser.add_argument("--lighting", required=True)
    parser.add_argument("--duration", type=finite_number, default=900.0, help="Seconds; 0 captures one snapshot")
    parser.add_argument("--interval", type=lambda s: finite_number(s, positive=True), default=10.0)
    args = parser.parse_args()
    # Package is also passed through Android's remote shell: restrict it to package-name syntax.
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+", args.package):
        parser.error("invalid Android package name")
    state = adb(args.serial, "get-state")
    if state["exit_code"] != 0 or state["stdout"].strip() != "device":
        parser.error("selected adb device is unavailable/unauthorized: " + state["stderr"].strip())
    try:
        args.output.mkdir(parents=True, exist_ok=False)
    except OSError as error:
        parser.error("cannot create a new evidence directory (existing output is never overwritten): " + str(error))
    metadata = {
        "started_at": datetime.now(timezone.utc).isoformat(),
        "serial": args.serial, "package": args.package,
        "build_mode": args.build_mode, "character": args.character, "lighting": args.lighting,
        "duration_requested_seconds": args.duration, "interval_seconds": args.interval,
        "device_model": None, "os_version": None, "build_fingerprint": None,
        "battery_at_start": None,
        "capture_status": "initializing",
        "limitations": [
            "Device/process serial and system diagnostic output are included; review before sharing.",
            "PSS and thermal status only; no inferred FPS, startup timings or device temperature.",
            "Unsupported/failed diagnostics are null, not passed or zero.",
            "No logcat, camera, microphone, screen recording, reset or settings changes performed.",
        ],
    }
    initialized_at = time.monotonic()
    start = None
    samples = []
    try:
        write_json(args.output / "metadata.json", metadata)
        for key, query in [
            ("device_model", ["getprop", "ro.product.model"]),
            ("os_version", ["getprop", "ro.build.version.release"]),
            ("build_fingerprint", ["getprop", "ro.build.fingerprint"]),
            ("battery_at_start", ["dumpsys", "battery"]),
        ]:
            metadata[key] = adb(args.serial, "shell", *query)
            write_json(args.output / "metadata.json", metadata)
        metadata["initialization_seconds"] = time.monotonic() - initialized_at
        metadata["capture_status"] = "capturing"
        write_json(args.output / "metadata.json", metadata)
        start = time.monotonic()
        with (args.output / "samples.jsonl").open("w") as stream:
            while True:
                samples.append(take_sample(args.serial, args.package, time.monotonic() - start))
                stream.write(json.dumps(samples[-1]) + "\n")
                stream.flush()
                remaining = args.duration - (time.monotonic() - start)
                if remaining <= 0:
                    break
                time.sleep(min(args.interval, remaining))
        metadata["capture_status"] = "completed"
    except KeyboardInterrupt:
        metadata["capture_status"] = "interrupted"
        print("Capture interrupted; keeping partial evidence.")
    except BaseException:
        metadata["capture_status"] = "failed"
        raise
    finally:
        report = summarize(samples)
        report["duration_observed_seconds"] = time.monotonic() - start if start is not None else 0
        report["samples"] = len(samples)
        report["capture_status"] = metadata["capture_status"]
        write_json(args.output / "metadata.json", metadata)
        write_json(args.output / "summary.json", report)
    print(args.output / "summary.json")


if __name__ == "__main__":
    main()
