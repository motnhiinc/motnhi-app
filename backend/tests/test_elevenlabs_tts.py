import importlib.util
import json
import sys
import unittest
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import patch
from urllib.error import HTTPError


class FakeResponse:
    status = 200

    def __init__(self, audio=b"ID3\x04\x00\x00mp3"):
        self.audio = audio
        self.read_limit = None

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return None

    def read(self, limit):
        self.read_limit = limit
        return self.audio[:limit]


class ElevenLabsTtsTests(unittest.TestCase):
    def setUp(self):
        config = ModuleType("app.config")
        config.settings = SimpleNamespace(
            elevenlabs_api_key="private-test-key",
            elevenlabs_voice_id="5yEPTrA0uAhZsBEhHjfi",
            elevenlabs_model_id="eleven_v3",
            elevenlabs_tts_timeout_seconds=60.0,
        )
        tts = ModuleType("app.services.tts")
        tts.TtsUpstreamError = type("TtsUpstreamError", (RuntimeError,), {})
        path = Path(__file__).resolve().parents[1] / "app/services/elevenlabs_tts.py"
        spec = importlib.util.spec_from_file_location("elevenlabs_tts_under_test", path)
        self.module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {"app.config": config, "app.services.tts": tts}):
            spec.loader.exec_module(self.module)
        self.settings = config.settings
        self.service = self.module.ElevenLabsTtsService()

    def test_request_uses_selected_voice_model_and_backend_only_key(self):
        response = FakeResponse()
        def fake_open(request, timeout):
            self.assertEqual(
                request.full_url,
                "https://api.elevenlabs.io/v1/text-to-speech/5yEPTrA0uAhZsBEhHjfi"
                "?output_format=mp3_44100_128",
            )
            self.assertEqual(request.get_method(), "POST")
            self.assertEqual(request.get_header("Xi-api-key"), "private-test-key")
            self.assertEqual(request.get_header("Content-type"), "application/json")
            self.assertEqual(json.loads(request.data), {
                "text": "Có mười ba chú thỏ.", "model_id": "eleven_v3",
            })
            self.assertEqual(timeout, 60.0)
            return response

        with patch.object(self.module, "_open", side_effect=fake_open):
            self.assertEqual(self.service.generate("Có mười ba chú thỏ."), response.audio)
        self.assertEqual(response.read_limit, 2 * 1024 * 1024 + 1)

    def test_mpeg_frame_audio_is_accepted(self):
        with patch.object(self.module, "_open", return_value=FakeResponse(b"\xff\xfb\x10audio")):
            self.assertEqual(self.service.generate("Một câu chuyện."), b"\xff\xfb\x10audio")

    def test_success_logs_header_body_and_total_timings_without_private_data(self):
        response = FakeResponse()
        with patch.object(self.module, "_open", return_value=response):
            with patch.object(self.module, "monotonic", side_effect=[100.0, 102.0, 102.5, 102.75]):
                with self.assertLogs(self.module.logger, level="INFO") as logs:
                    audio = self.service.generate("PRIVATE OCR TEXT", request_id="test-request", clip_number=2)
        self.assertEqual(audio, response.audio)
        output = "\n".join(logs.output)
        self.assertIn("request_id=test-request", output)
        self.assertIn("clip_number=2", output)
        self.assertIn("chars=16", output)
        self.assertIn("headers_seconds=2.000", output)
        self.assertIn("body_seconds=0.500", output)
        self.assertIn("elapsed_seconds=2.750", output)
        self.assertIn(f"audio_bytes={len(audio)}", output)
        self.assertNotIn("PRIVATE OCR TEXT", output)
        self.assertNotIn("private-test-key", output)

    def test_body_timeout_logs_received_headers_and_request_context(self):
        response = FakeResponse()
        with patch.object(response, "read", side_effect=TimeoutError("PRIVATE OCR TEXT")):
            with patch.object(self.module, "_open", return_value=response):
                with patch.object(self.module, "monotonic", side_effect=[100.0, 102.0, 105.0]):
                    with self.assertLogs(self.module.logger, level="WARNING") as logs:
                        with self.assertRaises(self.module.TtsUpstreamError):
                            self.service.generate("PRIVATE OCR TEXT", request_id="test-request", clip_number=3)
        output = "\n".join(logs.output)
        self.assertIn("request_id=test-request", output)
        self.assertIn("clip_number=3", output)
        self.assertIn("headers_seconds=2.0", output)
        self.assertIn("body_seconds=None", output)
        self.assertIn("status=200", output)
        self.assertIn("elapsed_seconds=5.000", output)
        self.assertNotIn("PRIVATE OCR TEXT", output)

    def test_missing_key_and_invalid_voice_fail_before_network(self):
        for key, voice in [(" ", "5yEPTrA0uAhZsBEhHjfi"), ("test", "../other-voice")]:
            self.settings.elevenlabs_api_key = key
            self.settings.elevenlabs_voice_id = voice
            with self.subTest(key=key, voice=voice):
                with self.assertRaises(self.module.TtsUpstreamError):
                    self.module.ElevenLabsTtsService()

    def test_configuration_failures_log_setting_and_code_without_values(self):
        cases = [
            ("elevenlabs_api_key", " ", "missing_api_key", "ELEVENLABS_API_KEY"),
            ("elevenlabs_voice_id", "private-invalid-voice", "invalid_voice_id", "ELEVENLABS_VOICE_ID"),
            ("elevenlabs_model_id", "private-invalid-model", "invalid_model_id", "ELEVENLABS_MODEL_ID"),
            ("elevenlabs_tts_timeout_seconds", float("nan"), "invalid_timeout", "ELEVENLABS_TTS_TIMEOUT_SECONDS"),
        ]
        for attribute, value, code, setting in cases:
            with self.subTest(setting=setting), patch.object(self.settings, attribute, value):
                with patch.object(self.module, "_open") as send:
                    with self.assertLogs(self.module.logger, level="WARNING") as logs:
                        with self.assertRaises(self.module.TtsUpstreamError):
                            self.module.ElevenLabsTtsService()
                    send.assert_not_called()
                output = "\n".join(logs.output)
                self.assertIn(f"code={code}", output)
                self.assertIn(f"setting={setting}", output)
                self.assertNotIn("private-test-key", output)
                self.assertNotIn("private-invalid", output)
                self.assertIsNone(logs.records[0].exc_info)

    def test_urllib_http_error_logs_http_status_without_private_data(self):
        error = HTTPError("https://private-url", 401, "private-test-key", {}, None)
        with patch.object(self.module, "_open", side_effect=error):
            with self.assertLogs(self.module.logger, level="WARNING") as logs:
                with self.assertRaises(self.module.TtsUpstreamError):
                    self.service.generate("PRIVATE OCR TEXT")
        output = "\n".join(logs.output)
        self.assertIn("status=401", output)
        self.assertNotIn("private-url", output)
        self.assertNotIn("private-test-key", output)
        self.assertNotIn("PRIVATE OCR TEXT", output)

    def test_rejects_empty_or_oversized_input_without_network(self):
        with patch.object(self.module, "_open") as send:
            for text in (" ", "x" * 5001):
                with self.assertRaises(self.module.TtsUpstreamError):
                    self.service.generate(text)
            send.assert_not_called()

    def test_rejects_non_mp3_empty_and_oversized_audio(self):
        with patch.object(self.module, "_open") as send:
            for audio in (b"", b"<html>private response</html>", b"ID3" + b"x" * (2 * 1024 * 1024)):
                send.return_value = FakeResponse(audio)
                with self.assertRaises(self.module.TtsUpstreamError):
                    self.service.generate("Một câu chuyện.")
            self.assertEqual(send.call_count, 3)

    def test_timeout_and_http_error_do_not_log_key_or_ocr(self):
        class PrivateHttpError(RuntimeError):
            status = 401

        error = PrivateHttpError("private-test-key PRIVATE OCR TEXT")
        with patch.object(self.module, "_open", side_effect=error) as send:
            with self.assertLogs(self.module.logger, level="WARNING") as logs:
                with self.assertRaises(self.module.TtsUpstreamError) as raised:
                    self.service.generate("PRIVATE OCR TEXT")
        self.assertIs(raised.exception.__cause__, error)
        self.assertEqual(send.call_count, 1)
        output = "\n".join(logs.output)
        self.assertIn("status=401", output)
        self.assertNotIn("private-test-key", output)
        self.assertNotIn("PRIVATE OCR TEXT", output)
        self.assertNotIn("private-test-key", str(raised.exception))

    def test_timeout_is_bounded_and_fails_without_retry(self):
        with patch.object(self.module, "_open", side_effect=TimeoutError("private response")) as send:
            with self.assertLogs(self.module.logger, level="WARNING"):
                with self.assertRaises(self.module.TtsUpstreamError):
                    self.service.generate("Một câu chuyện.")
        send.assert_called_once()

    def test_redirects_are_not_followed_with_the_api_key(self):
        self.assertIsNone(self.module._NoRedirects().redirect_request(
            None, None, 302, "redirect", {}, "https://untrusted.example/audio",
        ))


if __name__ == "__main__":
    unittest.main()
