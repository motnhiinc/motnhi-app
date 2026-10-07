import importlib.util
import sys
import unittest
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import Mock, patch


class QuotaError(RuntimeError):
    status_code = 429
    code = "insufficient_quota"


class TtsDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        # Load the real service with mocked SDK/config boundaries. These unit
        # checks need neither an installed OpenAI SDK nor a database fixture.
        self.client = Mock()
        sdk = ModuleType("openai")
        sdk.OpenAI = Mock(return_value=self.client)
        config = ModuleType("app.config")
        config.settings = SimpleNamespace(
            openai_api_key="sk-private-test-key",
            openai_tts_timeout_seconds=30.0,
            openai_tts_model="gpt-4o-mini-tts",
            openai_tts_voice="coral",
        )
        path = Path(__file__).resolve().parents[1] / "app/services/tts.py"
        spec = importlib.util.spec_from_file_location("tts_diagnostics_under_test", path)
        self.module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {"openai": sdk, "app.config": config}):
            spec.loader.exec_module(self.module)
        self.service = self.module.OpenAiTtsService()

    def test_upstream_failure_logs_status_code_and_duration_without_private_data(self):
        error = QuotaError("sk-private-test-key PRIVATE OCR TEXT")
        self.client.audio.speech.create.side_effect = error
        with patch.object(self.module, "monotonic", side_effect=[100.0, 101.25]):
            with self.assertLogs(self.module.logger, level="WARNING") as logs:
                with self.assertRaises(self.module.TtsUpstreamError) as raised:
                    self.service.generate("PRIVATE OCR TEXT")

        self.assertIs(raised.exception.__cause__, error)
        output = "\n".join(logs.output)
        self.assertIn("error_type=QuotaError", output)
        self.assertIn("status=429", output)
        self.assertIn("code=insufficient_quota", output)
        self.assertIn("elapsed_seconds=1.250", output)
        self.assertNotIn("PRIVATE OCR TEXT", output)
        self.assertNotIn("sk-private-test-key", output)
        self.assertIsNone(logs.records[0].exc_info)

    def test_timeout_without_http_response_is_logged_and_wrapped(self):
        error = TimeoutError("PRIVATE OCR TEXT")
        self.client.audio.speech.create.side_effect = error
        with self.assertLogs(self.module.logger, level="WARNING") as logs:
            with self.assertRaises(self.module.TtsUpstreamError):
                self.service.generate("PRIVATE OCR TEXT")

        output = "\n".join(logs.output)
        self.assertIn("error_type=TimeoutError", output)
        self.assertIn("status=None", output)
        self.assertIn("code=unknown", output)
        self.assertNotIn("PRIVATE OCR TEXT", output)

    def test_unexpected_error_code_is_not_logged(self):
        error = QuotaError("private response")
        error.code = "sk-private-test-key PRIVATE OCR TEXT"
        self.client.audio.speech.create.side_effect = error
        with self.assertLogs(self.module.logger, level="WARNING") as logs:
            with self.assertRaises(self.module.TtsUpstreamError):
                self.service.generate("PRIVATE OCR TEXT")

        output = "\n".join(logs.output)
        self.assertIn("code=unknown", output)
        self.assertNotIn("PRIVATE OCR TEXT", output)
        self.assertNotIn("sk-private-test-key", output)

    def test_success_keeps_the_openai_speech_request_and_audio_response(self):
        self.client.audio.speech.create.return_value = SimpleNamespace(content=b"MP3 audio")

        self.assertEqual(self.service.generate("Read this line"), b"MP3 audio")
        self.client.audio.speech.create.assert_called_once_with(
            model="gpt-4o-mini-tts",
            voice="coral",
            input="Read this line",
            response_format="mp3",
        )


if __name__ == "__main__":
    unittest.main()
