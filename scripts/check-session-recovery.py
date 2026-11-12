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
               "runPendingPresentation", "adoptSeamRecollapse", "refreshSeamSpaceAvailability",
               "requestPresentation", "performPresentation", "performExpand", "performCollapse",
               "setPresentation", "toggleFromShortcut", "expandFromDock", "mergeReveal", "mergeHide",
               "canBeginHoverReveal"]
    native = source.read_text()
    def extract(text, name):
        start = re.search(r"^    (?:private )?func " + re.escape(name) + r"\(", text, re.M)
        if not start:
            raise SystemExit(f"Missing live method: {name}")
        end = re.search(r"^    }$", text[start.start():], re.M)
        if not end:
            raise SystemExit(f"Missing method end: {name}")
        return text[start.start():start.start() + end.end()]
    extracted = [extract(native, name) for name in methods]
    bodies = "\n\n".join(extracted).replace("ProcessInfo.processInfo.systemUptime", "ReplayClock.now")
    engine = root / "Sources/EdgeStash/Engine/StashEngine.swift"
    merge = root / "Sources/EdgeStash/Overlay/StashMergeCoordinator.swift"
    models = root / "Sources/EdgeStash/Overlay/StashMergeStrip.swift"
    engine_methods = ["handleAppShortcut", "applyPresentationCommand", "applyShowAll"]
    driver_text = driver.read_text().replace("    // INSERT_CURRENT_SESSION_METHODS", bodies)
    driver_text = driver_text.replace("    // INSERT_CURRENT_SESSION_STATE", "\n".join(
        re.search(r"^    var " + name + r"[^\n]+", native, re.M).group()
        for name in ["desiredPresentationIsExpanded", "acceptsPresentationRequests"]))
    driver_text = driver_text.replace("    // INSERT_CURRENT_ENGINE_METHODS",
                                     "\n\n".join(extract(engine.read_text(), name) for name in engine_methods))
    # Whole coordinator, including reconciliation and both hover gates. Only
    # its clock and UI/session boundaries are injected, never its decisions.
    merge_text = merge.read_text().replace("Date()", "ReplayClock.date").replace(
        "ticket.deadline.timeIntervalSinceNow", "ticket.deadline.timeIntervalSince(ReplayClock.date)")
    driver_text = driver_text.replace("// INSERT_CURRENT_MERGE_COORDINATOR", merge_text)
    driver_text = driver_text.replace("// INSERT_CURRENT_MERGE_MODELS",
                                     models.read_text().split("final class StashMergeStrip:")[0])
    combined = work / "SessionRecoveryReplay.swift"
    combined.write_text(driver_text)
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
    result["engineMethods"] = engine_methods
    result["mergeCoordinator"] = "entire current StashMergeCoordinator with injected clock and UI"
    result["clockInjection"] = "ProcessInfo.processInfo.systemUptime replaced by ReplayClock.now"
    result["inputSHA256"] = {
        str(path.relative_to(root)) if path.is_relative_to(root) else str(path):
        hashlib.sha256(path.read_bytes()).hexdigest()
        for path in [source, engine, merge, models, driver, Path(__file__).resolve(),
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
