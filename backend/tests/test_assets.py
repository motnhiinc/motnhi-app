import pytest

from app.assets_signing import sign_asset_url
from app.config import settings
from app.models import Asset


def _auth(client):
    token = client.post("/v1/auth/device", json={"device_id": "dc-assets"}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def asset_file(db, tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "storage_dir", str(tmp_path))
    audio = tmp_path / "audio"
    audio.mkdir()
    (audio / "aud_demo.m4a").write_bytes(b"ABCDEFGH")
    db.add(Asset(asset_id="aud_demo", kind="audio",
                 storage_key="audio/aud_demo.m4a",
                 content_type="audio/mp4", byte_size=8))
    db.flush()
    return "aud_demo"


def test_sign_returns_only_registered(client, asset_file):
    r = client.post("/v1/assets/sign",
                    json={"asset_ids": ["aud_demo", "aud_unknown"]},
                    headers=_auth(client))
    assert r.status_code == 200
    body = r.json()
    assert "aud_demo" in body
    assert "aud_unknown" not in body
    assert body["aud_demo"].startswith("/v1/assets/aud_demo?exp=")


def test_sign_requires_auth(client, asset_file):
    assert client.post("/v1/assets/sign",
                       json={"asset_ids": ["aud_demo"]}).status_code == 401


def test_stream_serves_file(client, asset_file):
    r = client.get(sign_asset_url("aud_demo"))
    assert r.status_code == 200
    assert r.content == b"ABCDEFGH"


def test_stream_supports_range(client, asset_file):
    r = client.get(sign_asset_url("aud_demo"), headers={"Range": "bytes=0-3"})
    assert r.status_code == 206
    assert r.content == b"ABCD"


def test_stream_rejects_bad_sig(client, asset_file):
    assert client.get("/v1/assets/aud_demo?exp=9999999999&sig=deadbeef").status_code == 403


def test_stream_404_unknown_asset(client, asset_file):
    # valid signature, but no asset row
    assert client.get(sign_asset_url("aud_nope")).status_code == 404
