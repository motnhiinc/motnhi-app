import pytest

from app.auth import create_token, decode_token


def test_token_roundtrip():
    token = create_token("user-123")
    assert decode_token(token) == "user-123"


def test_decode_rejects_garbage():
    with pytest.raises(Exception):
        decode_token("not-a-jwt")
