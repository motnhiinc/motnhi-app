"""Register dropped audio recordings into the assets table (spec §8).

Scans <storage_dir>/audio for `<audio_asset_id>.m4a` files. For each file whose
stem matches a seeded narration_segments.audio_asset_id, upserts an `assets`
row. Reports orphan files (no matching segment) and segments still missing
audio. Idempotent (uses merge). Does not delete anything.
"""
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.db import SessionLocal
from app.models import Asset, NarrationSegment

AUDIO_SUBDIR = "audio"
CONTENT_TYPE = "audio/mp4"


def register(db: Session, storage_dir: Path) -> dict:
    known = set(
        db.execute(
            select(NarrationSegment.audio_asset_id)
            .where(NarrationSegment.audio_asset_id.is_not(None))
        ).scalars()
    )
    audio_dir = Path(storage_dir) / AUDIO_SUBDIR
    files = sorted(audio_dir.glob("*.m4a")) if audio_dir.exists() else []

    registered: list[str] = []
    orphans: list[str] = []
    for f in files:
        asset_id = f.stem
        if asset_id not in known:
            orphans.append(f.name)
            continue
        db.merge(Asset(
            asset_id=asset_id,
            kind="audio",
            storage_key=f"{AUDIO_SUBDIR}/{f.name}",
            content_type=CONTENT_TYPE,
            byte_size=f.stat().st_size,
            duration_ms=None,
        ))
        registered.append(asset_id)
    db.flush()

    have = set(
        db.execute(select(Asset.asset_id).where(Asset.kind == "audio")).scalars()
    )
    missing = sorted(known - have)
    return {"registered": registered, "orphans": orphans, "missing": missing}


if __name__ == "__main__":
    db = SessionLocal()
    try:
        result = register(db, Path(settings.storage_dir))
        db.commit()
        print(f"registered {len(result['registered'])} asset(s)")
        if result["orphans"]:
            print(f"orphan files (no matching segment): {result['orphans']}")
        if result["missing"]:
            print(f"segments still missing audio: {len(result['missing'])}")
    finally:
        db.close()
