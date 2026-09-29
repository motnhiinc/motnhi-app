import hashlib
import json
from datetime import datetime, timedelta, timezone

import jwt

from app.config import settings


def line_digest(lines: list[str]) -> str:
    payload = json.dumps(lines, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def issue_approval(user_id: str, profile_id: str, lines: list[str]) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "sub": user_id,
            "profile_id": profile_id,
            "lines_sha256": line_digest(lines),
            "scope": "page_audio",
            "iat": now,
            "exp": now + timedelta(minutes=10),
        },
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )


def verify_approval(proof: str, user_id: str, profile_id: str, lines: list[str]) -> bool:
    try:
        claims = jwt.decode(proof, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except jwt.InvalidTokenError:
        return False
    return (
        claims.get("sub") == user_id
        and claims.get("profile_id") == profile_id
        and claims.get("scope") == "page_audio"
        and claims.get("lines_sha256") == line_digest(lines)
    )
