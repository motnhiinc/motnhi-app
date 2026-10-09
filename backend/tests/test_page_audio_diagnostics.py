"""Exercise the real audio handler without database or provider requests."""

import importlib.util
import sys
import unittest
from io import BytesIO
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import Mock, patch
from uuid import UUID
from zipfile import ZipFile


class FakeResponse:
    def __init__(self, content, media_type, headers):
        self.content = content
        self.media_type = media_type
        self.headers = headers


class FakeHttpException(Exception):
    def __init__(self, status_code, detail, headers=None):
        self.status_code = status_code
        self.detail = detail
        self.headers = headers


def module(name, **attributes):
    result = ModuleType(name)
    result.__dict__.update(attributes)
    return result


class PageAudioDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.service = Mock()
        self.service.generate.return_value = b"ID3audio"
        self.approval = SimpleNamespace(verify_approval=Mock(return_value=True))
        router = SimpleNamespace(post=lambda *_: lambda function: function)
        stubs = {
            "fastapi": module(
                "fastapi", APIRouter=lambda **_: router, Depends=lambda _: None,
                Header=lambda **_: None, HTTPException=FakeHttpException, Response=FakeResponse,
            ),
            "sqlalchemy.orm": module("sqlalchemy.orm", Session=object),
            "app.auth": module("app.auth", get_current_user=Mock()),
            "app.db": module("app.db", get_db=Mock()),
            "app.models": module("app.models", User=object),
            "app.repositories": module(
                "app.repositories", privacy=SimpleNamespace(get_settings=Mock()),
                profiles=SimpleNamespace(get_owned=Mock(return_value=object())),
            ),
            "app.schemas": module("app.schemas", PageAudioRequest=object, ValidatePageRequest=object),
            "app.services": module(
                "app.services", page_approval=self.approval, page_validation=SimpleNamespace(),
                privacy=SimpleNamespace(require_core_storage=Mock(), PrivacyError=RuntimeError),
            ),
            "app.services.elevenlabs_tts": module(
                "app.services.elevenlabs_tts", ElevenLabsTtsService=object,
                get_elevenlabs_tts_service=lambda: self.service,
            ),
            "app.services.page_narration": module("app.services.page_narration", normalize_page_narration=list),
            "app.services.tts": module("app.services.tts", TtsUpstreamError=RuntimeError),
        }
        path = Path(__file__).resolve().parents[1] / "app/routers/speakable_page.py"
        spec = importlib.util.spec_from_file_location("page_audio_diagnostics_under_test", path)
        self.module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, stubs):
            spec.loader.exec_module(self.module)
        self.body = SimpleNamespace(profile_id="private-profile", proof="private-proof", lines=["PRIVATE OCR TEXT"])
        self.user = SimpleNamespace(id="private-user")
        self.request_id = "01234567-89ab-4def-8123-456789abcdef"

    def call(self, request_id=None):
        return self.module.generate_page_audio(self.body, db=object(), user=self.user, x_request_id=request_id)

    def test_success_correlates_clips_and_summary_without_private_data(self):
        with self.assertLogs(self.module.logger, level="INFO") as logs:
            response = self.call(self.request_id)
        self.assertEqual(response.headers["X-Request-ID"], self.request_id)
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        self.service.generate.assert_called_once_with(
            "PRIVATE OCR TEXT", request_id=self.request_id, clip_number=1,
        )
        with ZipFile(BytesIO(response.content)) as bundle:
            self.assertEqual(bundle.namelist(), ["000.mp3"])
            self.assertEqual(bundle.read("000.mp3"), b"ID3audio")
        output = "\n".join(logs.output)
        self.assertIn("Page audio clip completed", output)
        self.assertIn("Page audio completed", output)
        self.assertIn(f"request_id={self.request_id}", output)
        self.assertIn("tts_seconds=", output)
        self.assertIn("other_seconds=", output)
        for private in ["PRIVATE OCR TEXT", "private-profile", "private-proof", "private-user"]:
            self.assertNotIn(private, output)

    def test_untrusted_request_id_is_replaced_and_not_logged(self):
        for untrusted in (None, "PRIVATE OCR TEXT\nforged log", "x" * 100):
            with self.subTest(request_id=untrusted):
                with self.assertLogs(self.module.logger, level="INFO") as logs:
                    response = self.call(untrusted)
                UUID(response.headers["X-Request-ID"])
                self.assertNotIn("PRIVATE OCR TEXT", "\n".join(logs.output))
                self.assertNotIn("forged log", "\n".join(logs.output))

    def test_failed_clip_preserves_safe_response_and_request_id(self):
        self.service.generate.side_effect = RuntimeError("private-proof PRIVATE OCR TEXT")
        with self.assertLogs(self.module.logger, level="WARNING") as logs:
            with self.assertRaises(FakeHttpException) as raised:
                self.call(self.request_id)
        self.assertEqual(raised.exception.status_code, 502)
        self.assertEqual(raised.exception.detail, "narration generation failed")
        self.assertEqual(raised.exception.headers["X-Request-ID"], self.request_id)
        output = "\n".join(logs.output)
        self.assertIn("stage=speech", output)
        self.assertIn("clip_number=1", output)
        self.assertIn(f"request_id={self.request_id}", output)
        self.assertIn("tts_seconds=", output)
        self.assertNotIn("PRIVATE OCR TEXT", output)
        self.assertNotIn("private-proof", output)


if __name__ == "__main__":
    unittest.main()
