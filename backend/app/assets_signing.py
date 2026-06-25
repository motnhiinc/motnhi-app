"""Short-lived HMAC-signed URLs for asset streaming (spec §7.1).

A signed URL is `/v1/assets/{asset_id}?exp=<unix>&sig=<hex>` where
`sig = HMAC_SHA256(ASSET_URL_SECRET, "{asset_id}:{exp}")`. The media request
carries no Bearer token; the signature + expiry are the access proof.
"""
import hashlib
import hmac
import time

from app.config import settings


def _sig(asset_id: str, exp: int) -> str:
    msg = f"{asset_id}:{exp}".encode()
    return hmac.new(settings.asset_url_secret.encode(), msg, hashlib.sha256).hexdigest()


def sign_asset_url(asset_id: str, now: int | None = None) -> str:
    exp = (now if now is not None else int(time.time())) + settings.asset_url_ttl_seconds
    return f"/v1/assets/{asset_id}?exp={exp}&sig={_sig(asset_id, exp)}"


def verify_signature(asset_id: str, exp: int, sig: str, now: int | None = None) -> bool:
    current = now if now is not None else int(time.time())
    if exp <= current:
        return False
    return hmac.compare_digest(sig, _sig(asset_id, exp))
