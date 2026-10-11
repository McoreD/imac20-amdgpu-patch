"""Hardware gate tests: temporary sysfs fixtures, no root or host writes.

Run with: python3 -m unittest discover -s tests -v
"""
import pathlib
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
HARDWARE = REPO / "scripts/lib/hardware.sh"
TOOL = (REPO / "scripts/imac20-hwaccel").read_text()


class HardwareTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.pci = self.root / "pci"
        self.pci.mkdir()

    def gpu(self, subdevice="0x0219", **overrides):
        device = self.pci / f"0000:03:{len(list(self.pci.iterdir())):02d}.0"
        device.mkdir()
        values = dict(vendor="0x1002", device="0x7340",
                      subsystem_vendor="0x106b", subsystem_device=subdevice)
        values.update(overrides)
        for name, value in values.items():
            if value is not None:
                (device / name).write_text(value + "\n")
        return device

    def check(self):
        return subprocess.run(["bash", "-c", 'set -eu; source "$1"; require_supported_gpu "$2"',
                               "_", str(HARDWARE), str(self.pci)], capture_output=True, text=True)

    def test_supported_gpu_without_driver_or_revision(self):
        self.gpu()
        self.assertEqual(self.check().returncode, 0)

    def test_unsupported_and_incomplete_inventory(self):
        self.assertNotEqual(self.check().returncode, 0)
        for changes in ({"subdevice": "0x0218"}, {"vendor": "0x1234"},
                        {"device": "0x7341"}, {"subsystem_vendor": "0x1002"},
                        {"subsystem_device": None}):
            self.gpu(**changes)
            result = self.check()
            self.assertNotEqual(result.returncode, 0, changes)
            self.assertIn("106b:0219", result.stderr)

    def test_scans_all_pci_devices(self):
        self.gpu("0x0218")
        self.gpu()
        self.assertEqual(self.check().returncode, 0)

    def dispatch(self, command, missing_helper=False):
        # Load real function definitions and real dispatch, but replace all
        # work functions with markers. Never invoke system mutation commands.
        prefix, dispatch = TOOL.split("cmd=${1:-status}\n", 1)
        prefix = prefix.replace("CONF=/etc/imac20-hwaccel.conf", f"CONF={self.root}/absent.conf")
        helper = HARDWARE.read_text().replace("/sys/bus/pci/devices", str(self.pci))
        if not missing_helper:
            (self.root / "hardware.sh").write_text(helper)
        stubs = '\nSHARE="$2"\n'
        for name in ("require_root", "status", "build_module", "rebuild_ukis", "unpatch_module",
                     "disable_hwaccel", "ab_test", "ab_result", "ab_clean", "build_test_entry",
                     "remove_test_entry", "module_is_patched"):
            stubs += f'{name}() {{ echo "called:{name}"; }}\n'
        stubs += 'target_krel() { echo fixture-kernel; }\n'
        script = prefix + stubs + "cmd=${1:-status}\n" + dispatch
        return subprocess.run(["bash", "-c", script, "_", command, str(self.root)],
                              capture_output=True, text=True)

    def test_unsupported_build_and_entry_commands_do_no_work(self):
        self.gpu("0x0218")
        for command in ("repatch", "rebuild-uki", "ab-test", "test-entry", "_testentry", "_hookwork", "hook"):
            result = self.dispatch(command)
            self.assertEqual(result.returncode, 0 if command == "hook" else 1, command)
            self.assertNotIn("called:", result.stdout, command)
            self.assertIn("unsupported GPU", result.stderr, command)

    def test_hook_missing_helper_does_not_fail_transaction(self):
        result = self.dispatch("hook", missing_helper=True)
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("called:", result.stdout)

    def test_supported_repatch_reaches_build(self):
        self.gpu()
        result = self.dispatch("repatch")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("called:build_module", result.stdout)
        self.assertIn("called:rebuild_ukis", result.stdout)

    def test_diagnostics_and_recovery_remain_available(self):
        self.gpu("0x0218")
        for command in ("status", "ab-result", "disable", "unpatch", "ab-clean", "test-entry-remove"):
            result = self.dispatch(command)
            self.assertEqual(result.returncode, 0, (command, result.stderr))
            self.assertIn("called:", result.stdout)

    def test_installer_rejects_before_privilege_or_writes(self):
        self.gpu("0x0218")
        scripts = self.root / "scripts"
        (scripts / "lib").mkdir(parents=True)
        installer = (REPO / "scripts/install.sh").read_text()
        # Exit if the gate is bypassed, before executing *any* installer work.
        before, _ = installer.split('[[ $EUID -eq 0 ]]', 1)
        (scripts / "install.sh").write_text(before + 'echo UNEXPECTED-WORK; exit 99\n')
        (scripts / "lib/hardware.sh").write_text(
            HARDWARE.read_text().replace("/sys/bus/pci/devices", str(self.pci)))
        result = subprocess.run(["bash", str(scripts / "install.sh")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("unsupported GPU", result.stderr)
        self.assertNotIn("UNEXPECTED-WORK", result.stdout)


if __name__ == "__main__":
    unittest.main()
