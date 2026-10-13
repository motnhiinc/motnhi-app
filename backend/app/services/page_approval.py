import hashlib
import json
import math
from datetime import datetime, timedelta, timezone

import jwt

from app.config import settings


def line_digest(lines: list[str]) -> str:
    payload = json.dumps(lines, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def issue_approval(user_id: str, profile_id: str, lines: list[str], content_language: str | None = None) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "sub": user_id,
            "profile_id": profile_id,
            "lines_sha256": line_digest(lines),
            "scope": "page_audio",
            "version": 2,
            "content_language": content_language,
            "iat": now,
            "exp": now + timedelta(minutes=10),
        },
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )


def approval_reason(proof: str, user_id: str, profile_id: str, lines: list[str], content_language: str | None = None) -> str | None:
    try:
        # Verify signature and all bindings BEFORE distinguishing expiry. An
        # expired token is never authorization, even when otherwise authentic.
        claims = jwt.decode(proof, settings.jwt_secret, algorithms=[settings.jwt_algorithm],
                            options={"verify_exp": False, "require": ["exp"]})
    except jwt.InvalidTokenError:
        return "page_approval_invalid"
    bound = (
        claims.get("sub") == user_id
        and claims.get("profile_id") == profile_id
        and claims.get("scope") == "page_audio"
        and claims.get("lines_sha256") == line_digest(lines)
        and claims.get("content_language") == content_language
        and (content_language is None or claims.get("version") == 2)
    )
    if not bound or type(claims.get("exp")) not in (int, float) or not math.isfinite(claims["exp"]):
        return "page_approval_invalid"
    if claims["exp"] <= datetime.now(timezone.utc).timestamp():
        return "page_approval_expired"
    return None


def verify_approval(proof: str, user_id: str, profile_id: str, lines: list[str], content_language: str | None = None) -> bool:
    return approval_reason(proof, user_id, profile_id, lines, content_language) is None
