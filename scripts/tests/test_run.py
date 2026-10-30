"""Exercise install scripts against fake adb and Gradle; no device or build is used."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(os.name == "nt", "run.bat requires Windows")
class InstallSafetyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="juying install ")
        cls.root = Path(cls.directory.name)
        (cls.root / "scripts").mkdir()
        for name in ("run.bat", "run.ps1", "run.sh"):
            source = Path(__file__).resolve().parents[1] / name
            if name.endswith(".sh"):
                (cls.root / "scripts" / name).write_text(source.read_text(encoding="utf-8-sig"), encoding="utf-8", newline="\n")
            else:
                shutil.copyfile(source, cls.root / "scripts" / name)
        for name in (".venv/Scripts/python.exe", ".venv/bin/python"):
            python = cls.root / name
            python.parent.mkdir(parents=True, exist_ok=True)
            python.touch()
            python.chmod(0o755)
        (cls.root / "gradlew.bat").write_text('@echo off\necho %* >> "%FAKE_GRADLE_LOG%"\nexit /b 0\n')
        adb = cls.root / "sdk/platform-tools/adb.exe"
        adb.parent.mkdir(parents=True)
        source = cls.root / "FakeAdb.cs"
        source.write_text('''
using System;
using System.IO;
class FakeAdb {
    static int Main(string[] args) {
        string command = string.Join(" ", args);
        File.AppendAllText(Environment.GetEnvironmentVariable("FAKE_ADB_LOG"), command + "\\n");
        if (command == "devices") {
            Console.WriteLine("List of devices attached");
            foreach (string device in Environment.GetEnvironmentVariable("FAKE_ADB_DEVICES").Split(','))
                Console.WriteLine(device + "\\tdevice");
        }
        else if (command.Contains("getprop")) Console.WriteLine("TestDevice");
        else if (command.Contains(" install ")) {
            string failure = Environment.GetEnvironmentVariable("FAKE_ADB_FAILURE");
            string failedDevice = Environment.GetEnvironmentVariable("FAKE_ADB_FAIL_DEVICE");
            if (failedDevice != "" && args[1] != failedDevice) failure = "";
            if (failure == "") Console.WriteLine("Success");
            else Console.Error.WriteLine("Failure [" + failure + "]");
            return failure == "" ? 0 : 1;
        } else if (command.Contains("am start")) Console.WriteLine("Status: ok");
        return 0;
    }
}
''', encoding="utf-8")
        compiler = Path(os.environ["WINDIR"]) / "Microsoft.NET/Framework64/v4.0.30319/csc.exe"
        subprocess.run([str(compiler), "/nologo", "/out:" + str(adb), str(source)], check=True)
        cls.log = cls.root / "adb.log"
        cls.gradle_log = cls.root / "gradle.log"
        cls.env = dict(os.environ, ANDROID_HOME=(cls.root / "sdk").as_posix(),
                       FAKE_ADB_LOG=str(cls.log), FAKE_GRADLE_LOG=str(cls.gradle_log),
                       TEMP=str(cls.root), TMP=str(cls.root), FAKE_ADB_FAILURE="")
        cls.shells = {"bat": ["cmd.exe", "/d", "/c"]}
        powershell = shutil.which("powershell") or shutil.which("pwsh")
        if powershell:
            cls.shells["ps1"] = [powershell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]
        git = shutil.which("git")
        bash = Path(git).parent.parent / "usr/bin/bash.exe" if git else None
        if bash and bash.is_file():
            cls.shells["sh"] = [str(bash)]
            cls.env["PATH"] = str(bash.parent) + os.pathsep + cls.env["PATH"]

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def setUp(self):
        self.log.write_text("", encoding="utf-8")
        self.gradle_log.write_text("", encoding="utf-8")
        for variant in ("debug", "release"):
            directory = self.root / "app/build/outputs/apk" / variant
            directory.mkdir(parents=True, exist_ok=True)
            for apk in directory.glob("*.apk"):
                apk.unlink()

    def apk(self, variant, suffix, timestamp):
        apk = self.root / f"app/build/outputs/apk/{variant}/JuYing_{variant}_0.1.0_20261030{suffix}.apk"
        apk.touch()
        os.utime(apk, (timestamp, timestamp))
        return apk

    def run_script(self, shell, variant="debug", skip_build=True, failure="",
                   devices=("fake-device",), fail_device=""):
        self.log.write_text("", encoding="utf-8")
        flags = ["-All"] if shell == "ps1" else ["--all"]
        if skip_build:
            flags += ["-SkipBuild"] if shell == "ps1" else ["--skip-build"]
        if variant == "release":
            flags += ["-Release"] if shell == "ps1" else ["--release"]
        result = subprocess.run(self.shells[shell] + [(self.root / f"scripts/run.{shell}").as_posix()] + flags,
                                env=dict(self.env, FAKE_ADB_FAILURE=failure, FAKE_ADB_DEVICES=",".join(devices),
                                         FAKE_ADB_FAIL_DEVICE=fail_device), capture_output=True, timeout=30)
        return result, self.log.read_text(encoding="utf-8").splitlines()

    def test_install_failure_preserves_data_and_returns_failure(self):
        self.apk("debug", "_universal", 100)
        for shell in self.shells:
            for failure in ("INSTALL_FAILED_UPDATE_INCOMPATIBLE", "INSTALL_FAILED_VERSION_DOWNGRADE",
                            "INSTALL_FAILED_INSUFFICIENT_STORAGE", ""):
                with self.subTest(shell=shell, failure=failure or "success"):
                    result, commands = self.run_script(shell, failure=failure)
                    self.assertFalse(any("uninstall" in command or "pm clear" in command for command in commands))
                    self.assertEqual(1, sum(" install " in command for command in commands))
                    self.assertEqual(not failure, result.returncode == 0, result.stdout.decode("utf-8", errors="replace"))
                    self.assertEqual(not failure, any("am start" in command for command in commands))

    def test_one_device_failure_keeps_successful_devices_running_and_returns_failure(self):
        self.apk("debug", "_universal", 100)
        devices = ("first-device", "second-device")
        for shell in self.shells:
            for failed in devices:
                with self.subTest(shell=shell, failed=failed):
                    result, commands = self.run_script(shell, failure="INSTALL_FAILED_UPDATE_INCOMPATIBLE",
                                                       devices=devices, fail_device=failed)
                    self.assertFalse(any("uninstall" in command or "pm clear" in command for command in commands))
                    self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
                    for device in devices:
                        self.assertEqual(1, sum(command.startswith(f"-s {device} install ") for command in commands))
                        self.assertEqual(device != failed, any(command.startswith(f"-s {device} shell am start ")
                                                              for command in commands))

    def test_skip_build_installs_universal_even_when_single_abi_is_newer(self):
        for variant in ("debug", "release"):
            expected = self.apk(variant, "_universal", 100)
            older = expected.with_name(expected.name.replace("0.1.0", "0.0.9"))
            older.touch()
            os.utime(older, (50, 50))
            self.apk(variant, "_arm64-v8a", 200)
            self.apk(variant, "_armeabi-v7a", 300)
            for shell in self.shells:
                with self.subTest(shell=shell, variant=variant):
                    result, commands = self.run_script(shell, variant)
                    self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                    installs = [command for command in commands if " install " in command]
                    self.assertEqual(1, len(installs))
                    self.assertIn(expected.name, installs[0])
                    self.assertIn(expected.name.encode(), result.stdout)
        self.assertEqual("", self.gradle_log.read_text())

    def test_missing_universal_does_not_install_single_abi_or_legacy_apk(self):
        self.apk("debug", "_arm64-v8a", 200)
        self.apk("debug", "_armeabi-v7a", 300)
        self.apk("debug", "", 400)
        for shell in self.shells:
            with self.subTest(shell=shell):
                result, commands = self.run_script(shell)
                self.assertNotEqual(0, result.returncode)
                self.assertFalse(any(" install " in command for command in commands))

    def test_default_build_uses_universal_gradle_task(self):
        self.apk("debug", "_universal", 100)
        for shell in self.shells:
            with self.subTest(shell=shell):
                self.gradle_log.write_text("", encoding="utf-8")
                result, commands = self.run_script(shell, skip_build=False)
                self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                self.assertEqual(":app:assembleDebug", self.gradle_log.read_text().strip())
                self.assertEqual(1, sum("_universal.apk" in command for command in commands))


if __name__ == "__main__":
    unittest.main()
