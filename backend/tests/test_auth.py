import pytest

from app.auth import create_token, decode_token


def test_token_roundtrip():
    token = create_token("user-123")
    assert decode_token(token) == "user-123"


def test_decode_rejects_garbage():
    with pytest.raises(Exception):
        decode_token("not-a-jwt")


def test_device_auth_provisions_user_and_returns_token(client):
    resp = client.post("/v1/auth/device", json={"device_id": "device-abc"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["user_id"]
    assert body["token"]

    # same device id -> same user (idempotent)
    resp2 = client.post("/v1/auth/device", json={"device_id": "device-abc"})
    assert resp2.json()["user_id"] == body["user_id"]
