"""Exercise optional NVMe probe failures without hardware commands."""

import glob
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import capture_native


class CaptureNativeTests(unittest.TestCase):
    def capture_with_error(self, error):
        def fake_glob(path, pattern):
            if str(path) == "/sys/class/nvme":
                return iter([pathlib.Path("/sys/class/nvme/nvme0")])
            return iter(())

        def fake_run(command, **kwargs):
            if command[0] == "nvme":
                raise error
            return subprocess.CompletedProcess(command, 0, stdout="captured", stderr="")

        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "environment.json"
            argv = ["capture_native.py", "--data-root", directory, "--output", str(output)]
            with (
                mock.patch.object(sys, "argv", argv),
                mock.patch.object(capture_native.platform, "system", return_value="Linux"),
                mock.patch.object(capture_native.platform, "platform", return_value="Linux test"),
                mock.patch.object(glob, "glob", return_value=[]),
                mock.patch.object(pathlib.Path, "glob", new=fake_glob),
                mock.patch.object(capture_native.subprocess, "run", side_effect=fake_run),
            ):
                capture_native.main()
            record = json.loads(output.read_text())

        controller = "nvme id-ctrl /dev/nvme0 -o json"
        feature = "nvme get-feature /dev/nvme0 -f 6 -H"
        self.assertEqual(record["commands"][controller]["error"], str(error))
        self.assertEqual(record["commands"][feature]["error"], str(error))
        self.assertEqual(record["commands"]["uname -a"]["stdout"], "captured")
        self.assertIn("plan_sha256", record)

    def test_missing_nvme_executable_does_not_abort_capture(self):
        self.capture_with_error(FileNotFoundError(2, "No such file or directory", "nvme"))

    def test_nvme_timeout_does_not_abort_capture(self):
        self.capture_with_error(subprocess.TimeoutExpired(["nvme", "id-ctrl"], 15))


if __name__ == "__main__":
    unittest.main()
