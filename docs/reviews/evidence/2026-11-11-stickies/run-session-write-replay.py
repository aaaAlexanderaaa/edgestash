#!/usr/bin/env python3
"""Replay selected current session methods against explicit injected boundaries.

Build EdgeStashLogic first, then pass its --show-bin-path as --binary-dir.
Linux additionally needs an explicitly supplied, external CoreGraphics shim.
No native framework or full-session coverage is claimed by this harness.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary-dir", type=Path, required=True)
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--compat-dir", type=Path)
    args = parser.parse_args()
    evidence = Path(__file__).resolve().parent
    root = evidence.parents[3]
    source = root / "Sources/EdgeStash/Engine/StashSession.swift"
    driver = evidence / "session-write-replay.swift"
    methods = ["confirmOwnedMinimize", "confirmScreenSetPresentation", "cancelPresentationConfirmation",
               "reconcilePendingWindowWrites", "releaseOwnedMinimize",
               "refreshCollapsePresentation", "applyScreenSetSlot"]
    native = source.read_text()
    extracted = []
    for name in methods:
        start = re.search(r"^    (?:private )?func " + re.escape(name) + r"\(", native, re.M)
        if not start:
            raise SystemExit(f"Missing live method: {name}")
        end = re.search(r"^    }$", native[start.start():], re.M)
        if not end:
            raise SystemExit(f"Missing method end: {name}")
        extracted.append(native[start.start():start.start() + end.end()])
    bodies = "\n\n".join(extracted).replace("ProcessInfo.processInfo.systemUptime", "ReplayClock.now")
    work = root / ".build/session-write-replay"
    work.mkdir(parents=True, exist_ok=True)
    combined = work / "SessionWriteReplay.swift"
    combined.write_text(driver.read_text().replace("    // INSERT_CURRENT_SESSION_METHODS", bodies))
    objects = sorted((args.binary_dir / "EdgeStashLogic.build").glob("*.swift.o"))
    if not objects:
        raise SystemExit("Build current EdgeStashLogic before replaying")
    binary = work / "session-write-replay"
    command = [args.swiftc, "-swift-version", "5", "-parse-as-library",
               "-I", str(args.binary_dir / "Modules")]
    if args.compat_dir:
        command += ["-I", str(args.compat_dir), "-L", str(args.compat_dir),
                    "-Xlinker", "-rpath", "-Xlinker", str(args.compat_dir)]
    subprocess.run([*command, str(combined), *map(str, objects), "-o", str(binary)], check=True)
    replay = subprocess.run([str(binary)], capture_output=True, text=True)
    result = json.loads(replay.stdout)
    result["methods"] = methods
    result["clockInjection"] = "ProcessInfo.processInfo.systemUptime replaced by ReplayClock.now"
    result["compatibilityModule"] = str(args.compat_dir) if args.compat_dir else None
    result["inputSHA256"] = {
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in [source, driver, Path(__file__).resolve(),
                     *sorted((root / "Sources/EdgeStashLogic").glob("*.swift"))]
    }
    output = json.dumps(result, indent=2, sort_keys=True) + "\n"
    (work / "result.json").write_text(output)
    print(output, end="")
    if replay.stderr:
        print(replay.stderr, end="")
    raise SystemExit(replay.returncode)


if __name__ == "__main__":
    main()
