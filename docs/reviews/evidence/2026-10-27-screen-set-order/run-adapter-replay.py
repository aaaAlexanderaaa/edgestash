#!/usr/bin/env python3
"""Compile the current live coordinator with the injected replay boundaries."""
import hashlib
import json
import os
from pathlib import Path
import subprocess


def main():
    evidence = Path(__file__).resolve().parent
    root = evidence.parents[3]
    work = root / ".build/screen-set-order-replay"
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
    source = root / "Sources/EdgeStash/Engine/ScreenSetCoordinator.swift"
    driver = evidence / "adapter-replay.swift"
    combined = work / "ScreenSetCoordinatorReplay.swift"
    combined.write_text(source.read_text() + "\n" + driver.read_text())
    objects = sorted((binary_dir / "EdgeStashLogic.build").glob("*.swift.o"))
    if not objects:
        raise SystemExit("No current EdgeStashLogic object files found")
    binary = work / "adapter-replay"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
                    "-module-cache-path", environment["CLANG_MODULE_CACHE_PATH"],
                    "-I", str(binary_dir / "Modules"), str(combined),
                    *map(str, objects), "-o", str(binary)], cwd=root, env=environment, check=True)
    replay = subprocess.run([str(binary)], cwd=root, env=environment, capture_output=True, text=True)
    result = json.loads(replay.stdout)
    result["inputSHA256"] = {
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in [source, driver, *sorted((root / "Sources/EdgeStashLogic").glob("*.swift"))]
    }
    output = json.dumps(result, indent=2, sort_keys=True) + "\n"
    (work / "result.json").write_text(output)
    print(output, end="")
    if replay.stderr:
        print(replay.stderr, end="")
    raise SystemExit(replay.returncode)


if __name__ == "__main__":
    main()
