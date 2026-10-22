#!/usr/bin/env python3
"""Exercise release failure handling and ZIP/Cask consistency with fake Apple tools.

Uses real ditto/ZIP/plist handling on macOS. These checks do not prove signing,
notarization, Gatekeeper acceptance, or permission retention on a real Mac.
"""

import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parent.parent
TEAM = "ABCDEFGHIJ"
IDENTITY = f"Developer ID Application: Fixture ({TEAM})"

# One executable is linked under each tool name. No Keychain or Apple service
# is contacted; each call is recorded to check sequencing and failure isolation.
APPLE_TOOLS = r'''
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import zipfile

name, args = Path(sys.argv[0]).name, sys.argv[1:]
with open(os.environ["EDGESTASH_TEST_LOG"], "a") as stream:
    stream.write(json.dumps([name, *args]) + "\n")
failure = os.environ.get("EDGESTASH_TEST_FAILURE", "")

def fail_if(point):
    if failure == point:
        sys.exit(1)

def output_path(option):
    return Path(args[args.index(option) + 1])

if name == "security":
    print('  1) ' + 'A' * 40 + ' "' + os.environ["EDGESTASH_SIGNING_IDENTITY"] + '"')
elif name == "codesign":
    app = Path(args[-1])
    signature = app / "Contents/signature.fixture"
    if "--sign" in args:
        fail_if("sign")
        signature.write_text(args[args.index("--sign") + 1])
    elif "--verify" in args:
        if not signature.exists() or ("-R" in args and signature.read_text() == "-"):
            sys.exit(1)
        if "-R" in args:
            # Exercise Apple's real requirement parser, including its literal
            # '=' prefix; the fake signer alone cannot catch malformed input.
            parsed = subprocess.run(
                ["/usr/bin/csreq", "-r", args[args.index("-R") + 1]],
                capture_output=True,
            )
            if parsed.returncode:
                sys.stderr.buffer.write(parsed.stderr)
                sys.exit(parsed.returncode)
    elif "--display" in args:
        if failure != "runtime":
            print("flags=0x10000(runtime)")
        if failure != "timestamp":
            print("Timestamp=fixture")
elif name == "spctl":
    fail_if("gatekeeper")
    if not (Path(args[-1]) / "Contents/notarization-ticket.fixture").exists():
        sys.exit(1)
elif name == "xcodebuild":
    configuration = args[args.index("-configuration") + 1]
    product = output_path("-derivedDataPath") / "Build/Products" / configuration / "EdgeStash.app"
    (product / "Contents/MacOS").mkdir(parents=True)
    (product / "Contents/MacOS/EdgeStash").write_text("fixture executable")
    source = Path(os.environ["EDGESTASH_TEST_ROOT"]) / "Sources/Info.plist"
    (product / "Contents/Info.plist").write_bytes(source.read_bytes())
elif name == "xcrun":
    if args[0] == "--find":
        print("/fixture/" + args[1])
    elif args[0] in ("swiftc", "clang"):
        output_path("-o").write_text("fixture executable")
    elif args[0] == "lipo":
        print("arm64")
    elif args[:2] == ["notarytool", "submit"]:
        with zipfile.ZipFile(args[2]) as archive:
            if "EdgeStash.app/Contents/notarization-ticket.fixture" in archive.namelist():
                sys.exit("submission must precede stapling")
        status = "Invalid" if failure == "notary" else "Accepted"
        sys.stdout.buffer.write(plistlib.dumps({"id": "fixture-submission", "status": status}))
        fail_if("notary-command")
    elif args[:2] == ["notarytool", "log"]:
        print("fixture notary log")
    elif args[:2] == ["stapler", "staple"]:
        fail_if("staple")
        (Path(args[2]) / "Contents/notarization-ticket.fixture").write_text("fixture ticket")
    elif args[:2] == ["stapler", "validate"]:
        if not (Path(args[2]) / "Contents/notarization-ticket.fixture").exists():
            sys.exit(1)
    else:
        sys.exit("unexpected xcrun arguments: " + repr(args))
else:
    sys.exit("unexpected tool: " + name)
'''


@unittest.skipUnless(sys.platform == "darwin", "requires macOS ditto and PlistBuddy")
class DistributionToolingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="edgestash-release-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        shutil.copytree(ROOT / "scripts", self.root / "scripts")
        shutil.copytree(ROOT / "packaging", self.root / "packaging")
        for directory in ("Sources/EdgeStashLogic", "Sources/EdgeStash/Engine", "bin", "dist"):
            (self.root / directory).mkdir(parents=True)
        shutil.copy2(ROOT / "Sources/Info.plist", self.root / "Sources/Info.plist")
        (self.root / "Sources/EdgeStash/AppIcon.icns").write_bytes(b"fixture icon")
        (self.root / "Sources/EdgeStash/Fixture.swift").touch()
        (self.root / "Sources/EdgeStashLogic/Fixture.swift").touch()
        (self.root / "Sources/EdgeStash/Engine/DisplaySpaceBridge.m").touch()
        (self.root / "dist/CURRENT.txt").write_text("previous build\n")
        (self.root / "dist/EdgeStash.zip").write_bytes(b"previous archive")
        self.log = self.root / "calls.jsonl"
        shim = self.root / "bin/apple-tool-fixture"
        shim.write_text(f"#!{sys.executable}\n" + APPLE_TOOLS)
        shim.chmod(0o755)
        for name in ("security", "codesign", "xcrun", "xcodebuild", "spctl"):
            (self.root / "bin" / name).symlink_to(shim)
        self.environment = {k: v for k, v in os.environ.items() if not k.startswith("EDGESTASH_")}
        self.environment.update(
            PATH=f"{self.root / 'bin'}:{os.environ['PATH']}",
            EDGESTASH_SIGNING_IDENTITY=IDENTITY,
            EDGESTASH_TEAM_ID=TEAM,
            EDGESTASH_NOTARY_PROFILE="fixture-notary",
            EDGESTASH_TEST_LOG=str(self.log),
            EDGESTASH_TEST_ROOT=str(self.root),
        )
        with (self.root / "Sources/Info.plist").open("rb") as stream:
            self.version = plistlib.load(stream)["CFBundleShortVersionString"]

    def run_script(self, script, *arguments, environment=None):
        return subprocess.run(
            [str(self.root / "scripts" / script), *arguments],
            env=self.environment if environment is None else environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def snapshot(self):
        return {
            str(path.relative_to(self.root / "dist")): path.read_bytes()
            for path in (self.root / "dist").rglob("*") if path.is_file()
        }

    def stage_distribution(self):
        result = self.run_script("stage-app.sh", "Release", "--distribution")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_credentials_preserve_previous_outputs(self):
        for missing in ("EDGESTASH_SIGNING_IDENTITY", "EDGESTASH_TEAM_ID", "EDGESTASH_NOTARY_PROFILE"):
            with self.subTest(missing=missing):
                environment = self.environment.copy()
                del environment[missing]
                before = self.snapshot()
                result = self.run_script("stage-app.sh", "Release", "--distribution", environment=environment)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.snapshot(), before)
                self.assertFalse(self.log.exists())

    def test_debug_distribution_is_rejected_before_building(self):
        before = self.snapshot()
        result = self.run_script("stage-app.sh", "Debug", "--distribution")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(self.log.exists())

    def test_diagnostic_release_keeps_release_configuration_and_signed_metadata(self):
        result = self.run_script("stage-app.sh", "Release", "--diagnostics")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        app = self.root / "dist/EdgeStash.app/Contents/Info.plist"
        metadata = plistlib.loads(app.read_bytes())
        self.assertIs(metadata["EdgeStashRuntimeDiagnostics"], True)
        self.assertEqual(metadata["EdgeStashBuildConfiguration"], "Release")
        current = (self.root / "dist/CURRENT.txt").read_text()
        self.assertIn("configuration: Release", current)
        self.assertIn("diagnostics: true", current)
        with zipfile.ZipFile(self.root / "dist/EdgeStash.zip") as archive:
            self.assertEqual(archive.read("EdgeStash.app/Contents/Info.plist"), app.read_bytes())
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        for call in calls:
            if call[:2] == ["xcrun", "swiftc"]:
                self.assertIn("-O", call)
                self.assertNotIn("-Onone", call)
                self.assertNotIn("DEBUG", call)
            if call[0] == "xcodebuild":
                self.assertEqual(call[call.index("-configuration") + 1], "Release")

    def test_ordinary_release_disables_diagnostics_even_after_diagnostic_stage(self):
        for arguments, expected in [(("Debug",), True), (("Release", "--diagnostics"), True), (("Release",), False)]:
            with self.subTest(arguments=arguments):
                result = self.run_script("stage-app.sh", *arguments)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                metadata = plistlib.loads((self.root / "dist/EdgeStash.app/Contents/Info.plist").read_bytes())
                self.assertIs(metadata["EdgeStashRuntimeDiagnostics"], expected)

    def test_invalid_stage_options_preserve_previous_outputs(self):
        for arguments in [("--unknown",), ("Debug", "Release"), ("Release", "--diagnostics", "--diagnostics")]:
            with self.subTest(arguments=arguments):
                before = self.snapshot()
                result = self.run_script("stage-app.sh", *arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.snapshot(), before)
                self.assertFalse(self.log.exists())

    def test_failed_release_does_not_replace_previous_outputs(self):
        for failure in ("sign", "runtime", "timestamp", "notary", "notary-command", "staple", "gatekeeper"):
            with self.subTest(failure=failure):
                environment = dict(self.environment, EDGESTASH_TEST_FAILURE=failure)
                before = self.snapshot()
                result = self.run_script("stage-app.sh", "Release", "--distribution", environment=environment)
                self.assertNotEqual(result.returncode, 0, failure)
                self.assertEqual(self.snapshot(), before)

    def test_final_archive_contains_stapled_app_and_only_three_outputs(self):
        self.stage_distribution()
        self.assertEqual(
            sorted(path.name for path in (self.root / "dist").iterdir()),
            ["CURRENT.txt", "EdgeStash.app", "EdgeStash.zip"],
        )
        with zipfile.ZipFile(self.root / "dist/EdgeStash.zip") as archive:
            self.assertIn("EdgeStash.app/Contents/notarization-ticket.fixture", archive.namelist())
        self.assertIn("mode: distribution", (self.root / "dist/CURRENT.txt").read_text())
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        submit = next(i for i, call in enumerate(calls) if call[1:3] == ["notarytool", "submit"])
        staple = next(i for i, call in enumerate(calls) if call[1:3] == ["stapler", "staple"])
        gatekeeper = next(i for i, call in enumerate(calls) if call[0] == "spctl")
        self.assertLess(submit, staple)
        self.assertLess(staple, gatekeeper)

    def test_cask_uses_archive_metadata_and_exact_archive_checksum(self):
        self.stage_distribution()
        # Adjacent app metadata must not influence a Cask for the existing ZIP.
        plist = self.root / "dist/EdgeStash.app/Contents/Info.plist"
        with plist.open("rb") as stream:
            data = plistlib.load(stream)
        data["CFBundleShortVersionString"] = "999.0.0"
        plist.write_bytes(plistlib.dumps(data))
        result = self.run_script("generate-cask.sh", f"v{self.version}")
        self.assertEqual(result.returncode, 0, result.stderr)
        checksum = hashlib.sha256((self.root / "dist/EdgeStash.zip").read_bytes()).hexdigest()
        self.assertIn(f'  version "{self.version}"', result.stdout)
        self.assertIn(f'  sha256 "{checksum}"', result.stdout)
        self.assertIn("/releases/download/v#{version}/EdgeStash.zip", result.stdout)
        cask = self.root / "edgestash.rb"
        cask.write_text(result.stdout)
        syntax = subprocess.run(["ruby", "-c", str(cask)], capture_output=True, text=True)
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        if brew := shutil.which("brew"):
            # Evaluate the actual DSL without installing a tap or app. Set
            # developer mode only in this process; `brew ruby` otherwise
            # persists that setting for the person's Homebrew installation.
            environment = dict(
                self.environment,
                HOMEBREW_DEVELOPER="1",
                HOMEBREW_NO_AUTO_UPDATE="1",
                HOMEBREW_NO_ANALYTICS="1",
                HOMEBREW_NO_INSTALL_FROM_API="1",
                HOMEBREW_CACHE=str(self.root / "homebrew-cache"),
            )
            expression = (
                'require "cask/cask_loader"; '
                'cask = Cask::CaskLoader::FromContentLoader.new(File.read(ARGV.fetch(0))).load(config: nil); '
                'raise "wrong app artifact" unless cask.artifacts.any? { |a| a.is_a?(Cask::Artifact::App) }'
            )
            parsed = subprocess.run(
                [brew, "ruby", "-e", expression, str(cask)],
                env=environment, capture_output=True, text=True,
            )
            self.assertEqual(parsed.returncode, 0, parsed.stdout + parsed.stderr)

    def test_cask_rejects_tag_mismatch_and_failed_gatekeeper_without_output(self):
        self.stage_distribution()
        result = self.run_script("generate-cask.sh", "v999.0.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        environment = dict(self.environment, EDGESTASH_TEST_FAILURE="gatekeeper")
        result = self.run_script("generate-cask.sh", f"v{self.version}", environment=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_cask_rejects_development_archive_without_output(self):
        result = self.run_script("stage-app.sh", "Release")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.run_script("generate-cask.sh", f"v{self.version}")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
