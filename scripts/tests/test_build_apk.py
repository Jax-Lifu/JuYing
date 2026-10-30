"""Exercise the PowerShell ABI build loop with a Gradle archive stub."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(os.name == "nt", "build_apk.ps1 requires Windows")
class BuildAbiTest(unittest.TestCase):
    def run_build(self, abi=None, build_type="debug", clean=False,
                  dist_mode=None, fail_abi=None):
        directory = tempfile.TemporaryDirectory(prefix="juying-build-")
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        (root / "scripts").mkdir()
        script = root / "scripts/build_apk.ps1"
        shutil.copyfile(Path(__file__).resolve().parents[1] / "build_apk.ps1", script)
        python = root / ".venv/Scripts/python.exe"
        python.parent.mkdir(parents=True)
        python.touch()
        (root / "gradlew.bat").write_text(
            f'@echo off\n"{sys.executable}" "%~dp0gradle_stub.py" %*\nexit /b %errorlevel%\n')
        (root / "stub-config.json").write_text(json.dumps({"fail_abi": fail_abi}))
        (root / "gradle_stub.py").write_text('''import json
from pathlib import Path
import sys

root = Path(__file__).parent
args = sys.argv[1:]
with (root / "gradle-args.jsonl").open("a") as log:
    log.write(json.dumps(args) + "\\n")
abi = next((arg.split("=", 1)[1] for arg in args if arg.startswith("-PtargetAbi=")), "universal")
config = json.loads((root / "stub-config.json").read_text())
if abi == config["fail_abi"]:
    sys.exit(23)
mode = next(arg.split("=", 1)[1] for arg in args if arg.startswith("-PdistMode="))
folder = {"version": "v0.1.0", "date": "20261030", "version_date": "v0.1.0_20261030"}[mode]
output = root / "dist" / folder
output.mkdir(parents=True, exist_ok=True)
for variant in ("debug", "release"):
    if f":app:assemble{variant.title()}" not in args:
        continue
    name = f"JuYing_{variant}_0.1.0_20261030_{abi}.apk"
    (output / name).write_bytes(f"selected-{variant}-{abi}".encode())
    if variant == "release":
        (output / name.replace(".apk", "_mapping.txt")).write_text(f"mapping-{abi}")
''')
        command = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script)]
        if build_type:
            command.append(f"-{build_type.title()}")
        if abi:
            command.extend(["-Abi", abi])
        if clean:
            command.append("-Clean")
        if dist_mode:
            command.append(f"-By{dist_mode.title()}")
        result = subprocess.run(command, capture_output=True)
        args_file = root / "gradle-args.jsonl"
        calls = [json.loads(line) for line in args_file.read_text().splitlines()] if args_file.exists() else []
        return root, calls, result

    def assert_archive(self, dist, abi, variant):
        name = f"JuYing_{variant}_0.1.0_20261030_{abi}.apk"
        self.assertEqual(f"selected-{variant}-{abi}".encode(), (dist / name).read_bytes())
        if variant == "release":
            self.assertEqual(f"mapping-{abi}", (dist / name.replace(".apk", "_mapping.txt")).read_text())

    def test_default_and_all_archive_three_abis_with_paired_mappings(self):
        for abi in (None, "all"):
            with self.subTest(abi=abi):
                root, calls, result = self.run_build(abi, build_type=None)
                self.assertEqual(0, result.returncode, result.stderr.decode("utf-8", errors="replace"))
                self.assertEqual(3, len(calls))
                dist = root / "dist/v0.1.0_20261030"
                for args, target in zip(calls, ("arm64-v8a", "armeabi-v7a", "universal")):
                    self.assertIn(":app:assembleDebug", args)
                    self.assertIn(":app:assembleRelease", args)
                    properties = [arg for arg in args if arg.startswith("-PtargetAbi=")]
                    self.assertEqual([] if target == "universal" else [f"-PtargetAbi={target}"], properties)
                    for variant in ("debug", "release"):
                        self.assert_archive(dist, target, variant)
                self.assertEqual(9, len(list(dist.iterdir())))

    def test_single_abi_builds_only_requested_architecture(self):
        for abi in ("universal", "arm64-v8a", "armeabi-v7a"):
            with self.subTest(abi=abi):
                root, calls, result = self.run_build(abi, build_type="release")
                self.assertEqual(0, result.returncode, result.stderr.decode("utf-8", errors="replace"))
                self.assertEqual(1, len(calls))
                self.assertNotIn(":app:assembleDebug", calls[0])
                self.assertIn(":app:assembleRelease", calls[0])
                properties = [arg for arg in calls[0] if arg.startswith("-PtargetAbi=")]
                self.assertEqual([] if abi == "universal" else [f"-PtargetAbi={abi}"], properties)
                dist = root / "dist/v0.1.0_20261030"
                self.assert_archive(dist, abi, "release")
                self.assertEqual(2, len(list(dist.iterdir())))

    def test_clean_runs_only_in_first_round(self):
        root, calls, result = self.run_build(clean=True)
        self.assertEqual(0, result.returncode, result.stderr.decode("utf-8", errors="replace"))
        self.assertEqual(3, len(calls))
        self.assertEqual([True, False, False], ["clean" in args for args in calls])
        self.assertTrue(all(":app:assembleRelease" not in args for args in calls))
        self.assertEqual(3, len(list((root / "dist/v0.1.0_20261030").iterdir())))

    def test_build_failure_stops_before_archiving_or_building_next_abi(self):
        root, calls, result = self.run_build(fail_abi="armeabi-v7a", build_type="release")
        self.assertEqual(23, result.returncode)
        self.assertEqual(2, len(calls))
        dist = root / "dist/v0.1.0_20261030"
        self.assert_archive(dist, "arm64-v8a", "release")
        self.assertEqual(2, len(list(dist.iterdir())))

    def test_archive_modes_are_forwarded_and_preserved(self):
        for mode, folder in (("version", "v0.1.0"), ("date", "20261030")):
            with self.subTest(mode=mode):
                root, calls, result = self.run_build("universal", dist_mode=mode)
                self.assertEqual(0, result.returncode, result.stderr.decode("utf-8", errors="replace"))
                self.assertIn(f"-PdistMode={mode}", calls[0])
                self.assert_archive(root / "dist" / folder, "universal", "debug")

    def test_rejects_invalid_abi_before_build(self):
        for abi in ("x86", "ARM64-V8A"):
            with self.subTest(abi=abi):
                _, calls, result = self.run_build(abi)
                self.assertNotEqual(0, result.returncode)
                self.assertEqual([], calls)

    def test_all_switch_builds_debug_and_release(self):
        _, calls, result = self.run_build("universal", build_type="all")
        self.assertEqual(0, result.returncode, result.stderr.decode("utf-8", errors="replace"))
        self.assertEqual(1, len(calls))
        self.assertIn(":app:assembleDebug", calls[0])
        self.assertIn(":app:assembleRelease", calls[0])


if __name__ == "__main__":
    unittest.main()
