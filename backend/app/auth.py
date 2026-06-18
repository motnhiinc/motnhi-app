import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, Header, HTTPException
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.models import User


def generate_secret() -> str:
    return secrets.token_urlsafe(32)


def hash_secret(secret: str) -> str:
    return hashlib.sha256(secret.encode()).hexdigest()


def verify_secret(secret: str, secret_hash: str) -> bool:
    return hmac.compare_digest(hash_secret(secret), secret_hash)


def create_token(user_id: str) -> str:
    payload = {
        "sub": user_id,
        "iat": datetime.now(timezone.utc),
        "exp": datetime.now(timezone.utc) + timedelta(days=30),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> str:
    data = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    return data["sub"]


def get_current_user(
    authorization: str = Header(default=""),
    db: Session = Depends(get_db),
) -> User:
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    try:
        user_id = decode_token(authorization.removeprefix("Bearer "))
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="invalid token")
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="unknown user")
    return user
