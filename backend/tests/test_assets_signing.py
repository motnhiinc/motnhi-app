from urllib.parse import urlparse, parse_qs

from app.assets_signing import sign_asset_url, verify_signature


def _parse(url: str) -> tuple[int, str]:
    q = parse_qs(urlparse(url).query)
    return int(q["exp"][0]), q["sig"][0]


def test_sign_then_verify_ok():
    url = sign_asset_url("aud_x", now=1000)
    assert url.startswith("/v1/assets/aud_x?exp=")
    exp, sig = _parse(url)
    assert verify_signature("aud_x", exp, sig, now=1000) is True


def test_verify_rejects_tampered_sig():
    exp, _sig = _parse(sign_asset_url("aud_x", now=1000))
    assert verify_signature("aud_x", exp, "deadbeef", now=1000) is False


def test_verify_rejects_expired():
    exp, sig = _parse(sign_asset_url("aud_x", now=1000))
    assert verify_signature("aud_x", exp, sig, now=10_000_000) is False


def test_verify_rejects_wrong_asset_id():
    exp, sig = _parse(sign_asset_url("aud_x", now=1000))
    assert verify_signature("aud_y", exp, sig, now=1000) is False


def test_verify_rejects_at_exact_expiry():
    exp, sig = _parse(sign_asset_url("aud_x", now=1000))
    assert verify_signature("aud_x", exp, sig, now=exp) is False
