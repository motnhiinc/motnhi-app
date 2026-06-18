"""Ingest assets/data/*.json into the content tables.

The bundled story JSON is the source of truth (spec §4): one manifest listing
slugs, one detail file per slug shaped exactly like GET /v1/stories/{id}.
"""
import json
from pathlib import Path

from sqlalchemy.orm import Session

from app.db import SessionLocal
from app.models import (
    ArScene,
    NarrationSegment,
    Question,
    QuestionChoice,
    Story,
    StoryPage,
)

DATA_DIR = Path(__file__).resolve().parent.parent / "assets" / "data"


def seed_story(db: Session, detail: dict) -> None:
    s = detail["story"]
    db.merge(Story(
        id=s["id"], title=s["title"], slug=s["slug"], description=s.get("description"),
        age_min=s.get("age_min", 3), age_max=s.get("age_max", 8),
        language_code=s.get("language_code", "en"),
        duration_seconds=s.get("duration_seconds", 0),
        cover_asset_id=s.get("cover_asset_id"), content_status=s.get("content_status", "published"),
        rights_owner_id=s.get("rights_owner_id"), themes=s.get("themes", []),
    ))
    for p in detail.get("pages", []):
        db.merge(StoryPage(
            id=p["id"], story_id=p["story_id"], page_number=p["page_number"],
            page_text=p.get("page_text"), page_image_asset_id=p.get("page_image_asset_id"),
            image_target_id=p.get("image_target_id"),
        ))
    # Flush pages first so FK constraints on ar_scenes/segments/questions are satisfied.
    db.flush()
    for seg in detail.get("segments", []):
        db.merge(NarrationSegment(
            id=seg["id"], story_id=seg["story_id"], page_id=seg["page_id"],
            speaker_key=seg["speaker_key"], text=seg["text"], voice_id=seg["voice_id"],
            emotion=seg.get("emotion"), speed=seg.get("speed"),
            audio_asset_id=seg.get("audio_asset_id"),
            start_ms=seg.get("start_ms"), end_ms=seg.get("end_ms"), sort_order=seg["sort_order"],
        ))
    for scene in detail.get("ar_scenes", []):
        db.merge(ArScene(
            id=scene["id"], story_id=scene["story_id"], page_id=scene["page_id"],
            scene_json=scene["scene_json"], status=scene.get("status", "published"),
        ))
    for qi, q in enumerate(detail.get("questions", [])):
        db.merge(Question(
            id=q["id"], story_id=s["id"], page_id=q["page_id"],
            type=q["type"], prompt=q["prompt"], sort_order=qi,
        ))
        for ci, c in enumerate(q.get("choices", [])):
            db.merge(QuestionChoice(
                id=c["id"], question_id=q["id"], label=c["label"], emoji=c.get("emoji"),
                is_correct=c.get("is_correct", False), sort_order=ci,
            ))


def seed_all(db: Session, data_dir: Path = DATA_DIR) -> int:
    manifest = json.loads((data_dir / "manifest.json").read_text())
    slugs = manifest["stories"]
    for slug in slugs:
        detail = json.loads((data_dir / f"{slug}.json").read_text())
        seed_story(db, detail)
    db.commit()
    return len(slugs)


if __name__ == "__main__":
    db = SessionLocal()
    try:
        count = seed_all(db)
        print(f"seeded {count} stories")
    finally:
        db.close()
