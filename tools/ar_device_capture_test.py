import argparse
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import ar_device_capture as capture


class DeviceCaptureTests(unittest.TestCase):
    def test_one_snapshot_cli_writes_real_evidence_files_and_never_overwrites(self):
        def fake_command(argv):
            self.assertEqual(argv[:3], ["adb", "-s", "explicit-serial"])
            action = argv[3:]
            self.assertIn(action[0], ["get-state", "shell"])
            text = {
                ("get-state",): "device\n",
                ("shell", "pidof", "com.motnhi.app"): "1234\n",
                ("shell", "dumpsys", "meminfo", "1234"): "TOTAL PSS: 456\n",
                ("shell", "dumpsys", "thermalservice"): "Thermal Status: 1\n",
            }.get(tuple(action), "fixture device metadata\n")
            return {"exit_code": 0, "stdout": text, "stderr": ""}

        with tempfile.TemporaryDirectory(prefix="ar-capture-test-") as directory:
            output = Path(directory) / "evidence"
            args = ["capture", "--serial", "explicit-serial", "--output", str(output),
                    "--build-mode", "profile", "--character", "cute_doll_v01",
                    "--lighting", "warm-indoor", "--duration", "0"]
            with patch("sys.argv", args), patch.object(capture, "command", side_effect=fake_command), \
                    contextlib.redirect_stdout(io.StringIO()):
                capture.main()
                original = (output / "metadata.json").read_text()
                with contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit) as error:
                        capture.main()
                self.assertEqual(error.exception.code, 2)
            self.assertEqual((output / "metadata.json").read_text(), original)
            summary = json.loads((output / "summary.json").read_text())
            self.assertEqual(summary["samples"], 1)
            self.assertEqual(summary["memory_peak_kib"], 456)
            self.assertEqual(summary["visual_acceptance"], "UNVERIFIED")
            sample = json.loads((output / "samples.jsonl").read_text())
            self.assertEqual(sample["process_ids"], ["1234"])
            self.assertEqual(sample["thermal_status"], 1)

    def test_interrupt_during_metadata_preserves_partial_metadata_and_summary(self):
        with tempfile.TemporaryDirectory(prefix="ar-capture-test-") as directory:
            output = Path(directory) / "evidence"
            args = ["capture", "--serial", "serial", "--output", str(output),
                    "--build-mode", "profile", "--character", "fox", "--lighting", "daylight"]
            with patch("sys.argv", args), patch.object(capture, "adb", side_effect=[
                {"exit_code": 0, "stdout": "device\n", "stderr": ""},
                {"exit_code": 0, "stdout": "Fixture phone\n", "stderr": ""},
                KeyboardInterrupt(),
            ]), contextlib.redirect_stdout(io.StringIO()):
                capture.main()
            metadata = json.loads((output / "metadata.json").read_text())
            summary = json.loads((output / "summary.json").read_text())
            self.assertEqual(metadata["device_model"]["stdout"], "Fixture phone\n")
            self.assertIsNone(metadata["os_version"])
            self.assertEqual(metadata["capture_status"], "interrupted")
            self.assertEqual(summary["capture_status"], "interrupted")
            self.assertEqual(summary["samples"], 0)
            self.assertIsNone(summary["memory_peak_kib"])

    def test_invalid_package_is_rejected_before_adb_or_filesystem_work(self):
        args = ["capture", "--serial", "serial", "--output", "unused",
                "--build-mode", "profile", "--character", "fox", "--lighting", "daylight",
                "--package", "com.motnhi.app; echo unsafe"]
        with patch("sys.argv", args), patch.object(capture, "adb") as adb, \
                contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                capture.main()
        self.assertEqual(error.exception.code, 2)
        adb.assert_not_called()

    def test_missing_device_is_rejected_before_output_directory_creation(self):
        args = ["capture", "--serial", "serial", "--output", "unused",
                "--build-mode", "profile", "--character", "fox", "--lighting", "daylight"]
        with patch("sys.argv", args), patch.object(capture, "adb", return_value={
            "exit_code": 1, "stdout": "", "stderr": "device not found",
        }), patch.object(capture.Path, "mkdir") as mkdir, \
                contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                capture.main()
        self.assertEqual(error.exception.code, 2)
        mkdir.assert_not_called()

    def test_modern_pss_takes_precedence_over_legacy_rows(self):
        text = "  TOTAL 999 0 0\n  TOTAL PSS: 12,345    TOTAL RSS: 15000\n"
        self.assertEqual(capture.parse_total_pss_kib(text), 12345)

    def test_legacy_pss_and_real_zero(self):
        self.assertEqual(capture.parse_total_pss_kib(" TOTAL 456 12 34\n"), 456)
        self.assertEqual(capture.parse_total_pss_kib(" TOTAL PSS: 0\n"), 0)

    def test_missing_memory_or_thermal_is_not_zero(self):
        self.assertIsNone(capture.parse_total_pss_kib("No process found for: com.motnhi.app"))
        self.assertIsNone(capture.parse_thermal_status("Can't find service: thermalservice"))
        self.assertEqual(capture.parse_thermal_status("Thermal Status: 2\n"), 2)

    def test_summary_does_not_invent_metrics_or_acceptance(self):
        result = capture.summarize([{"total_pss_kib": n} for n in [100, None, 250, 125]])
        self.assertEqual(result["memory_first_kib"], 100)
        self.assertEqual(result["memory_peak_kib"], 250)
        self.assertEqual(result["memory_last_kib"], 125)
        self.assertEqual(result["memory_samples"], 3)
        self.assertIsNone(result["frame_pacing"])
        self.assertIsNone(result["camera_ready_ms"])
        self.assertEqual(result["performance_acceptance"], "UNVERIFIED")
        self.assertIsNone(capture.summarize([])["memory_peak_kib"])

    def test_closed_process_does_not_report_stale_memory(self):
        with patch.object(capture, "adb", side_effect=[
            {"exit_code": 1, "stdout": "", "stderr": ""},
            {"exit_code": 0, "stdout": "Thermal Status: 1", "stderr": ""},
        ]):
            sample = capture.take_sample("serial", "com.motnhi.app", 12)
        self.assertEqual(sample["process_ids"], [])
        self.assertIsNone(sample["total_pss_kib"])
        self.assertEqual(sample["thermal_status"], 1)

    def test_multiple_named_processes_are_queried_individually_and_summed(self):
        with patch.object(capture, "adb", side_effect=[
            {"exit_code": 0, "stdout": "1234 5678", "stderr": ""},
            {"exit_code": 0, "stdout": "TOTAL 99 0 0\nTOTAL PSS: 100", "stderr": ""},
            {"exit_code": 0, "stdout": "TOTAL PSS: 250", "stderr": ""},
            {"exit_code": 0, "stdout": "Thermal Status: 0", "stderr": ""},
        ]) as adb:
            sample = capture.take_sample("serial", "com.motnhi.app", 0)
        self.assertEqual(sample["total_pss_kib"], 350)
        self.assertEqual(sample["process_pss_kib"], {"1234": 100, "5678": 250})
        self.assertEqual(adb.call_args_list[1].args, ("serial", "shell", "dumpsys", "meminfo", "1234"))
        self.assertEqual(adb.call_args_list[2].args, ("serial", "shell", "dumpsys", "meminfo", "5678"))

    def test_partial_process_memory_does_not_understate_the_total(self):
        with patch.object(capture, "adb", side_effect=[
            {"exit_code": 0, "stdout": "1234 5678", "stderr": ""},
            {"exit_code": 0, "stdout": "TOTAL PSS: 100", "stderr": ""},
            {"exit_code": 1, "stdout": "", "stderr": "process exited"},
            {"exit_code": 0, "stdout": "Thermal Status: 0", "stderr": ""},
        ]):
            sample = capture.take_sample("serial", "com.motnhi.app", 0)
        self.assertIsNone(sample["total_pss_kib"])
        self.assertEqual(sample["process_pss_kib"], {"1234": 100, "5678": None})

    def test_unavailable_first_or_last_snapshot_stays_null_in_summary(self):
        result = capture.summarize([{"total_pss_kib": n} for n in [None, 250, None]])
        self.assertIsNone(result["memory_first_kib"])
        self.assertEqual(result["memory_peak_kib"], 250)
        self.assertIsNone(result["memory_last_kib"])

    def test_failed_command_does_not_parse_partial_memory_output(self):
        with patch.object(capture, "adb", side_effect=[
            {"exit_code": 0, "stdout": "1234", "stderr": ""},
            {"exit_code": 1, "stdout": "TOTAL PSS: 42", "stderr": "error"},
            {"exit_code": 1, "stdout": "Thermal Status: 0", "stderr": "error"},
        ]):
            sample = capture.take_sample("serial", "com.motnhi.app", 0)
        self.assertEqual(sample["process_ids"], ["1234"])
        self.assertIsNone(sample["total_pss_kib"])
        self.assertIsNone(sample["thermal_status"])

    def test_capture_durations_must_be_finite_and_nonnegative(self):
        self.assertEqual(capture.finite_number("0"), 0)
        self.assertEqual(capture.finite_number("10", positive=True), 10)
        for value in ["nan", "inf", "-1"]:
            with self.assertRaises(argparse.ArgumentTypeError):
                capture.finite_number(value)
        with self.assertRaises(argparse.ArgumentTypeError):
            capture.finite_number("0", positive=True)


if __name__ == "__main__":
    unittest.main()
