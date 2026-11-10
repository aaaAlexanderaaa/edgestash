#!/usr/bin/env python3
"""Check the English project policy and the completeness of the copy catalog."""
from pathlib import Path
import re
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parents[1]
    listed = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root, capture_output=True, check=True,
    )
    paths = sorted({root / name.decode() for name in listed.stdout.split(b"\0") if name})
    ideograph = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\U00020000-\U000323af]")
    failures = []
    for path in paths:
        if path == root / "README_cn.md" or not path.is_file():
            continue
        try:
            contents = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for line, text in enumerate(contents.splitlines(), 1):
            if ideograph.search(text):
                failures.append(f"{path.relative_to(root)}:{line}: non-English project text")

    catalog = root / "Sources/EdgeStash/Preferences/Localization.swift"
    entries = re.findall(r'^\s*"([\w.]+)":\s*"', catalog.read_text(), re.MULTILINE)
    known = set(entries)
    if len(known) != len(entries):
        failures.append("English copy catalog contains duplicate identifiers")
    for path in (root / "Sources/EdgeStash").rglob("*.swift"):
        contents = path.read_text()
        for identifier in re.findall(r'\b(?:L10n\.)?text\("([\w.]+)"\)', contents):
            if identifier not in known:
                failures.append(f"{path.relative_to(root)}: missing English copy: {identifier}")
    for failure in failures:
        print(failure, file=sys.stderr)
    if failures:
        return 1
    print(f"English project copy OK: {len(known)} catalog entries; README_cn.md is exempt.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
