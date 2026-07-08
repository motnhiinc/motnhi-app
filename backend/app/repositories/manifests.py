from sqlalchemy import select
from sqlalchemy.orm import Session

from app.assets_signing import sign_asset_url
from app.config import settings
from app.models import Asset, Story, StoryPage
from app.schemas import ImageTargetEntry, ImageTargetManifest


def build_image_target_manifest(db: Session, story_id: str) -> ImageTargetManifest | None:
    story = db.get(Story, story_id)
    if story is None:
        return None

    pages = list(db.scalars(
        select(StoryPage)
        .where(StoryPage.story_id == story_id, StoryPage.image_target_id.is_not(None))
        .order_by(StoryPage.page_number)
    ))

    # Sign reference_image_url only for page images registered in the assets table
    # (mirrors app/routers/assets.py sign()). Today seeded page_image_asset_id values
    # are path strings, not registered assets, so this is truthfully None.
    candidate_ids = [p.page_image_asset_id for p in pages if p.page_image_asset_id is not None]
    registered = set(
        db.execute(
            select(Asset.asset_id).where(Asset.asset_id.in_(candidate_ids))
        ).scalars()
    )

    targets = [
        ImageTargetEntry(
            page_id=p.id,
            page_number=p.page_number,
            image_target_id=p.image_target_id,
            reference_image_url=(
                sign_asset_url(p.page_image_asset_id)
                if p.page_image_asset_id in registered
                else None
            ),
            physical_width_mm=settings.default_target_physical_width_mm,
        )
        for p in pages
    ]

    return ImageTargetManifest(story_id=story_id, version=1, targets=targets)
