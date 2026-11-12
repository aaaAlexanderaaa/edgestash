#!/usr/bin/env python3
"""Replay current session recovery and named requests with injected boundaries."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-source", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    work = root / ".build/session-recovery-replay"
    work.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(work / "module-cache")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(work / "module-cache")
    xcode = Path("/Applications/Xcode.app/Contents/Developer")
    if xcode.is_dir() and "DEVELOPER_DIR" not in environment:
        environment["DEVELOPER_DIR"] = str(xcode)
    options = ["--disable-sandbox", "--cache-path", str(work / "swiftpm-cache"),
               "--config-path", str(work / "swiftpm-config"),
               "--security-path", str(work / "swiftpm-security")]
    subprocess.run(["swift", "build", *options, "--product", "EdgeStashLogicTests"],
                   cwd=root, env=environment, check=True)
    binary_dir = Path(subprocess.check_output(["swift", "build", *options, "--show-bin-path"],
                      cwd=root, env=environment, text=True).strip())
    source = args.session_source or root / "Sources/EdgeStash/Engine/StashSession.swift"
    driver = root / "NativeTests/SessionRecoveryReplay.swift"
    methods = ["reconcileScreenSetPresentation", "confirmScreenSetPresentation",
               "cancelPresentationConfirmation", "deferPendingPresentation",
               "cancelPendingRecovery", "prepareForScreenSetChange", "applyScreenSetSlot",
               "rehideCollapsed", "collapse", "confirmOwnedMinimize", "expand",
               "prepareAndExpandSharedMinimize", "commitSeamReveal",
               "finishScreenSetRepair", "finishExpand", "finishCollapse",
               "runPendingPresentation", "adoptSeamRecollapse", "refreshSeamSpaceAvailability"]
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
    combined = work / "SessionRecoveryReplay.swift"
    combined.write_text(driver.read_text().replace("    // INSERT_CURRENT_SESSION_METHODS", bodies))
    objects = sorted((binary_dir / "EdgeStashLogic.build").glob("*.swift.o"))
    if not objects:
        raise SystemExit("No current EdgeStashLogic object files found")
    binary = work / "session-recovery-replay"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
                    "-module-cache-path", environment["CLANG_MODULE_CACHE_PATH"],
                    "-I", str(binary_dir / "Modules"), str(combined),
                    *map(str, objects), "-o", str(binary)], cwd=root, env=environment, check=True)
    replay = subprocess.run([str(binary)], cwd=root, env=environment, capture_output=True, text=True)
    try:
        result = json.loads(replay.stdout)
    except json.JSONDecodeError:
        raise SystemExit(replay.stderr or f"Session replay exited {replay.returncode} without JSON output")
    result["methods"] = methods
    result["clockInjection"] = "ProcessInfo.processInfo.systemUptime replaced by ReplayClock.now"
    result["inputSHA256"] = {
        str(path.relative_to(root)) if path.is_relative_to(root) else str(path):
        hashlib.sha256(path.read_bytes()).hexdigest()
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
