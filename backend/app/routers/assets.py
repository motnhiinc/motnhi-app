from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.assets_signing import sign_asset_url, verify_signature
from app.auth import get_current_user
from app.config import settings
from app.db import get_db
from app.models import Asset, User
from app.schemas import AssetSignRequest

router = APIRouter(prefix="/v1/assets", tags=["assets"])


@router.post("/sign")
def sign(
    req: AssetSignRequest,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> dict[str, str]:
    registered = set(
        db.execute(
            select(Asset.asset_id).where(Asset.asset_id.in_(req.asset_ids))
        ).scalars()
    )
    return {aid: sign_asset_url(aid) for aid in req.asset_ids if aid in registered}


@router.get("/{asset_id}")
def stream(
    asset_id: str,
    exp: int,
    sig: str,
    db: Session = Depends(get_db),
) -> FileResponse:
    if not verify_signature(asset_id, exp, sig):
        raise HTTPException(status_code=403, detail="invalid or expired signature")
    asset = db.get(Asset, asset_id)
    if asset is None:
        raise HTTPException(status_code=404, detail="asset not found")
    path = Path(settings.storage_dir) / asset.storage_key
    if not path.is_file():
        raise HTTPException(status_code=404, detail="file missing")
    return FileResponse(path, media_type=asset.content_type)
