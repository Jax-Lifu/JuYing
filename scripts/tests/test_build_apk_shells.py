"""Check Bash/Batch build orchestration with a Gradle archive stub."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


def find_bash():
    if os.name != "nt":
        return shutil.which("bash")
    git = shutil.which("git")
    candidate = Path(git).parent.parent / "bin/bash.exe" if git else None
    return str(candidate) if candidate and candidate.is_file() else None


BASH = find_bash()
ABIS = ("arm64-v8a", "armeabi-v7a", "universal")


class BuildShellChecks:
    def run_build(self, args=(), fail_abi=None):
        directory = tempfile.TemporaryDirectory(prefix="juying shell-")
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        (root / "scripts").mkdir()
        script = root / "scripts" / self.script_name
        script.write_text((Path(__file__).resolve().parents[1] / self.script_name).read_text(encoding="utf-8"),
                          encoding="utf-8", newline="\n" if self.script_name.endswith(".sh") else "\r\n")
        python = root / (".venv/Scripts/python.exe" if os.name == "nt" else ".venv/bin/python")
        python.parent.mkdir(parents=True)
        python.touch()
        python.chmod(0o755)
        (root / "fail-abi.txt").write_text(fail_abi or "")
        (root / "gradle_stub.py").write_text('''import json
from pathlib import Path
import shutil
import sys

root = Path(__file__).parent
args = sys.argv[1:]
with (root / "gradle-args.jsonl").open("a") as log:
    log.write(json.dumps(args) + "\\n")
abi = next((arg.split("=", 1)[1] for arg in args if arg.startswith("-PtargetAbi=")), "universal")
if abi == (root / "fail-abi.txt").read_text():
    sys.exit(23)
mode = next(arg.split("=", 1)[1] for arg in args if arg.startswith("-PdistMode="))
folder = {"version": "v0.1.0", "date": "20261030", "version_date": "v0.1.0_20261030"}[mode]
dist = root / "dist" / folder
dist.mkdir(parents=True, exist_ok=True)
for variant in ("debug", "release"):
    if f":app:assemble{variant.title()}" not in args:
        continue
    output = root / f"app/build/outputs/apk/{variant}"
    output.mkdir(parents=True, exist_ok=True)
    for old in output.glob("*.apk"):
        old.unlink()
    name = f"JuYing_{variant}_0.1.0_20261030_{abi}.apk"
    apk = output / name
    apk.write_text(f"selected-{variant}-{abi}")
    (output / "output-metadata.json").write_text(json.dumps({"elements": [{"outputFile": name}]}))
    shutil.copyfile(apk, dist / name)
    if variant == "release":
        mapping = root / "app/build/outputs/mapping/release/mapping.txt"
        mapping.parent.mkdir(parents=True, exist_ok=True)
        mapping.write_text(f"mapping-{abi}")
        shutil.copyfile(mapping, dist / name.replace(".apk", "_mapping.txt"))
    (output / f"JuYing_{variant}_0.1.0_20261030_x86.apk").write_text("stale")
''')
        if os.name == "nt":
            (root / "gradlew.bat").write_text(
                f'@echo off\n"{sys.executable}" "%~dp0gradle_stub.py" %*\nexit /b %errorlevel%\n')
        else:
            wrapper = root / "gradlew"
            wrapper.write_text(f'#!/usr/bin/env bash\nexec "{sys.executable}" "$(dirname "$0")/gradle_stub.py" "$@"\n')
            wrapper.chmod(0o755)
        if self.script_name.endswith(".bat"):
            command = ["cmd.exe", "/d", "/c", str(script), *args]
        else:
            command = [BASH, script.as_posix(), *args]
        result = subprocess.run(command, capture_output=True, timeout=30)
        log = root / "gradle-args.jsonl"
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return root, calls, result

    def assert_ok(self, result):
        self.assertEqual(0, result.returncode, (result.stdout + result.stderr).decode("utf-8", errors="replace"))

    def assert_archive(self, dist, abi, variant):
        name = f"JuYing_{variant}_0.1.0_20261030_{abi}.apk"
        self.assertEqual(f"selected-{variant}-{abi}", (dist / name).read_text())
        if variant == "release":
            self.assertEqual(f"mapping-{abi}", (dist / name.replace(".apk", "_mapping.txt")).read_text())

    def test_default_and_all_archive_three_abis_and_leave_universal_last(self):
        for args in ((), ("--abi", "all")):
            with self.subTest(args=args):
                root, calls, result = self.run_build(args)
                self.assert_ok(result)
                self.assertEqual(3, len(calls))
                dist = root / "dist/v0.1.0_20261030"
                for call, abi in zip(calls, ABIS):
                    self.assertEqual([] if abi == "universal" else [f"-PtargetAbi={abi}"],
                                     [arg for arg in call if arg.startswith("-PtargetAbi=")])
                    for variant in ("debug", "release"):
                        self.assertIn(f":app:assemble{variant.title()}", call)
                        self.assert_archive(dist, abi, variant)
                self.assertEqual(9, len(list(dist.iterdir())))
                metadata = json.loads((root / "app/build/outputs/apk/debug/output-metadata.json").read_text())
                self.assertTrue(metadata["elements"][0]["outputFile"].endswith("_universal.apk"))

    def test_single_abi_release_archive(self):
        for abi in ABIS:
            with self.subTest(abi=abi):
                root, calls, result = self.run_build(("--release", "--abi", abi))
                self.assert_ok(result)
                self.assertEqual(1, len(calls))
                self.assertNotIn(":app:assembleDebug", calls[0])
                self.assert_archive(root / "dist/v0.1.0_20261030", abi, "release")
                self.assertEqual(2, len(list((root / "dist/v0.1.0_20261030").iterdir())))

    def test_clean_only_first_round_and_debug_only(self):
        root, calls, result = self.run_build(("--debug", "--clean"))
        self.assert_ok(result)
        self.assertEqual([True, False, False], ["clean" in call for call in calls])
        self.assertTrue(all(":app:assembleRelease" not in call for call in calls))
        self.assertEqual(3, len(list((root / "dist/v0.1.0_20261030").iterdir())))

    def test_dist_modes(self):
        for mode, folder in (("version", "v0.1.0"), ("date", "20261030")):
            with self.subTest(mode=mode):
                root, calls, result = self.run_build(("--debug", "--abi", "universal", f"--by-{mode}"))
                self.assert_ok(result)
                self.assertIn(f"-PdistMode={mode}", calls[0])
                self.assert_archive(root / "dist" / folder, "universal", "debug")

    def test_invalid_or_missing_abi_stops_before_gradle(self):
        for args in (("--abi", "x86"), ("--abi",)):
            with self.subTest(args=args):
                root, calls, result = self.run_build(args)
                self.assertNotEqual(0, result.returncode)
                self.assertEqual([], calls)
                self.assertFalse((root / "dist").exists())

    def test_failure_does_not_build_or_archive_later_abis(self):
        root, calls, result = self.run_build(("--release",), fail_abi="armeabi-v7a")
        self.assertNotEqual(0, result.returncode)
        self.assertEqual(2, len(calls))
        dist = root / "dist/v0.1.0_20261030"
        self.assert_archive(dist, "arm64-v8a", "release")
        self.assertEqual(2, len(list(dist.iterdir())))


@unittest.skipUnless(BASH, "Bash is unavailable")
class BashBuildTest(BuildShellChecks, unittest.TestCase):
    script_name = "build_apk.sh"


@unittest.skipUnless(os.name == "nt", "Batch requires Windows")
class BatchBuildTest(BuildShellChecks, unittest.TestCase):
    script_name = "build_apk.bat"


if __name__ == "__main__":
    unittest.main()
